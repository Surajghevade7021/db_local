import psycopg2
from psycopg2.extras import RealDictCursor
from config import db_credentials
from datetime import datetime

print("Recovery Started →", datetime.now())

conn = psycopg2.connect(**db_credentials)
conn.autocommit = False
cur = conn.cursor(cursor_factory=RealDictCursor)

cur.execute("""
WITH corrupted_leads AS (
    SELECT lead_id
    FROM contact_mapping
    WHERE updated_at BETWEEN '2026-02-16 00:00:00'
                        AND '2026-02-17 23:59:59'
      AND end_date IS NOT NULL
    GROUP BY lead_id
    HAVING COUNT(*) > 1
),
valid_closed AS (
    SELECT cm.mapping_id
    FROM contact_mapping cm
    JOIN contact_transfer_backup ctb
      ON ctb.lead_id = cm.lead_id
     AND ctb.old_rm_id = cm.rm_id
    WHERE cm.updated_at BETWEEN '2026-02-16 00:00:00'
                           AND '2026-02-17 23:59:59'
)
SELECT cm.mapping_id, cm.lead_id
FROM contact_mapping cm
WHERE cm.lead_id IN (SELECT lead_id FROM corrupted_leads)
  AND cm.updated_at BETWEEN '2026-02-16 00:00:00'
                       AND '2026-02-17 23:59:59'
  AND cm.end_date IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM valid_closed vc
        WHERE vc.mapping_id = cm.mapping_id
  )
ORDER BY cm.lead_id;
""")

rows = cur.fetchall()

print("Total corrupted mappings found:", len(rows))
print("--------------------------------------------------")

restored = 0
skipped = 0
failed = 0
exit()
for row in rows:

    mapping_id = row["mapping_id"]
    lead_id = row["lead_id"]

    print(f"\nProcessing → Lead: {lead_id} | Mapping: {mapping_id}")

    try:
        conn.rollback()   
        cur.execute("""
            SELECT rm_id, end_date, is_transferred, updated_at, updated_by
            FROM contact_mapping_log
            WHERE mapping_id = %s
              AND log_timestamp < '2026-02-16 00:00:00'
            ORDER BY log_timestamp DESC
            LIMIT 1
        """, (mapping_id,))

        log = cur.fetchone()

        if not log:
            print(" No log found → SKIPPED")
            skipped += 1
            continue

        original_rm = log["rm_id"]

        print(f" Restoring RM → {original_rm}")

        cur.execute("""
            UPDATE contact_mapping
            SET rm_id=%s,
                end_date=%s,
                is_transferred=%s,
                updated_at=%s,
                updated_by=%s
            WHERE mapping_id=%s
        """, (
            log["rm_id"],
            log["end_date"],
            log["is_transferred"],
            log["updated_at"],
            log["updated_by"],
            mapping_id
        ))

        cur.execute("""
            SELECT rm_id
            FROM contact_mapping
            WHERE lead_id=%s
            AND end_date IS NULL
            LIMIT 1
        """, (lead_id,))

        active = cur.fetchone()

        if active:
            active_rm = active["rm_id"]

            cur.execute("""
                UPDATE lead
                SET rm_id=%s
                WHERE lead_id=%s
            """, (active_rm, lead_id))

            print(f"  Lead owner corrected → RM {active_rm}")
        else:
            cur.execute("""
                UPDATE contact_mapping
                SET end_date=NULL
                WHERE mapping_id=%s
            """, (mapping_id,))

            cur.execute("""
                UPDATE lead
                SET rm_id=%s
                WHERE lead_id=%s
            """, (original_rm, lead_id))

            print(f"  Activated mapping & assigned RM {original_rm}")

        conn.commit()
        restored += 1
        print("  Restored")

    except Exception as e:
        conn.rollback()
        failed += 1
        print("  FAILED:", e)

print("\n---------------- SUMMARY ----------------")
print("Restored :", restored)
print("Skipped  :", skipped)
print("Failed   :", failed)
print("Completed →", datetime.now())

cur.close()
conn.close()