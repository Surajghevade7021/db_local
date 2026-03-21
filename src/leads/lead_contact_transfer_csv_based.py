import psycopg2
from psycopg2.extras import RealDictCursor
from config import db_credentials
from datetime import datetime
import csv
import sys
import os

print("Start -->", datetime.now())

CSV_FILE = input("Enter CSV file path: ").strip()
COMPANY_ID = 1
SYSTEM_USER_ID = 1

# ── Read CSV ─────────────────────────────────────────────────────────────────
with open(CSV_FILE, newline='', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    rows = [r for r in reader]

print(f"Total rows in CSV: {len(rows)}")

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)

# ── Session ID ────────────────────────────────────────────────────────────────
cur.execute("SELECT MAX(session_id) FROM contact_transfer_backup")
session_id = str((cur.fetchone()['max'] or 0) + 1)

# ── Audit file setup ──────────────────────────────────────────────────────────
timestamp      = datetime.now().strftime("%Y%m%d_%H%M%S")
audit_filename = f"audit_{timestamp}.csv"
audit_dir      = os.path.dirname(os.path.abspath(CSV_FILE))
audit_path     = os.path.join(audit_dir, audit_filename)

AUDIT_COLS = [
    # original CSV columns
    "contact_name", "email_address", "mobile_number",
    "Current Counselor", "status", "substatus", "Move to Owner",
    # resolved / enriched columns
    "contact_id", "lead_id",
    "old_rm_id", "new_rm_id",
    "status_id", "substatus_id",
    "new_mapping_id", "session_id",
    # outcome columns
    "remarks", "transfer_status",
]

audit_file   = open(audit_path, "w", newline='', encoding='utf-8')
audit_writer = csv.DictWriter(audit_file, fieldnames=AUDIT_COLS)
audit_writer.writeheader()

def write_audit(row, resolved, remarks, status):
    audit_writer.writerow({
        "contact_name"     : row.get("contact_name", "").strip(),
        "email_address"    : row.get("email_address", "").strip(),
        "mobile_number"    : row.get("mobile_number", "").strip(),
        "Current Counselor": row.get("Current Counselor", "").strip(),
        "status"           : row.get("status", "").strip(),
        "substatus"        : row.get("substatus", "").strip(),
        "Move to Owner"    : row.get("Move to Owner", "").strip(),
        "contact_id"       : resolved.get("contact_id", ""),
        "lead_id"          : resolved.get("lead_id", ""),
        "old_rm_id"        : resolved.get("old_rm_id", ""),
        "new_rm_id"        : resolved.get("new_rm_id", ""),
        "status_id"        : resolved.get("status_id", ""),
        "substatus_id"     : resolved.get("substatus_id", ""),
        "new_mapping_id"   : resolved.get("new_mapping_id", ""),
        "session_id"       : session_id,
        "remarks"          : " | ".join(remarks) if remarks else "OK",
        "transfer_status"  : status,
    })
    audit_file.flush()

# ── Helpers ───────────────────────────────────────────────────────────────────
def get_user_id(full_name):
    cur.execute(
        "SELECT user_id FROM mst_user WHERE mu.is_Active and full_name = %s LIMIT 1",
        (full_name.strip(),)
    )
    row = cur.fetchone()
    return row['user_id'] if row else None

def get_status_id(name):
    cur.execute(
        "SELECT status_id FROM mst_status WHERE LOWER(name) = LOWER(%s) LIMIT 1",
        (name.strip(),)
    )
    row = cur.fetchone()
    return row['status_id'] if row else None

def get_substatus_id(name):
    cur.execute(
        "SELECT substatus_id FROM mst_substatus WHERE LOWER(name) = LOWER(%s) LIMIT 1",
        (name.strip(),)
    )
    row = cur.fetchone()
    return row['substatus_id'] if row else None

def get_contact_id(email, mobile):
    if email:
        cur.execute(
            "SELECT contact_id FROM contact WHERE email_address = %s LIMIT 1",
            (email,)
        )
        row = cur.fetchone()
        if row:
            return row['contact_id']
    if mobile:
        cur.execute(
            "SELECT contact_id FROM contact WHERE mobile_number = %s LIMIT 1",
            (mobile,)
        )
        row = cur.fetchone()
        if row:
            return row['contact_id']
    return None

# ── Validate all rows first ───────────────────────────────────────────────────
print("\nValidating rows...")
valid_rows = []
skipped    = 0

for i, row in enumerate(rows, start=2):
    email      = row.get('email_address', '').strip()
    mobile     = row.get('mobile_number', '').strip()
    counselor  = row.get('Current Counselor', '').strip()
    status_nm  = row.get('status', '').strip()
    subst_nm   = row.get('substatus', '').strip()
    new_owner  = row.get('Move to Owner', '').strip()
    c_name     = row.get('contact_name', '').strip()

    errors   = []
    resolved = {}

    # contact_id
    contact_id = get_contact_id(email, mobile)
    if contact_id:
        resolved['contact_id'] = contact_id
    else:
        errors.append("contact_not_found")

    # old RM
    old_rm_id = get_user_id(counselor)
    if old_rm_id:
        resolved['old_rm_id'] = old_rm_id
    else:
        errors.append("old_rm_not_found")

    # new RM
    new_rm_id = get_user_id(new_owner)
    if new_rm_id:
        resolved['new_rm_id'] = new_rm_id
    else:
        errors.append("new_rm_not_found")

    # status
    status_id = get_status_id(status_nm)
    if status_id:
        resolved['status_id'] = status_id
    else:
        errors.append("status_not_found")

    # substatus
    substatus_id = get_substatus_id(subst_nm)
    if substatus_id:
        resolved['substatus_id'] = substatus_id
    else:
        errors.append("substatus_not_found")

    # lead lookup (only if all above resolved)
    if not errors:
        cur.execute("""
            SELECT l.lead_id
            FROM lead l join mst_user mu on l.rm_id=mu.user_id
            WHERE l.contact_id   = %s
                    AND mu.location_id=12
              AND l.is_active    = TRUE
              AND NOT (23 = ANY(l.sub_product_ids))
              AND l.status_id < 6
              AND NOT (
                    l.substatus_id IN (10, 11)
                    AND COALESCE(l.updated_at, l.created_at) <= NOW() - INTERVAL '61 days'
                  )
            ORDER BY l.lead_id DESC
            LIMIT 1
        """, (contact_id,  ))
        lead_row = cur.fetchone()
        if lead_row:
            resolved['lead_id'] = lead_row['lead_id']
        else:
            errors.append("lead_not_found")

    if errors:
        skipped += 1
        print(f"  [SKIP] Row {i} ({c_name}): {' | '.join(errors)}")
        write_audit(row, resolved, errors, "failed")
    else:
        valid_rows.append({
            'csv_row'     : i,
            'raw_row'     : row,
            'contact_name': c_name,
            'lead_id'     : resolved['lead_id'],
            'contact_id'  : contact_id,
            'old_rm_id'   : old_rm_id,
            'new_rm_id'   : new_rm_id,
            'status_id'   : status_id,
            'substatus_id': substatus_id,
            'resolved'    : resolved,
        })

print(f"\nValid: {len(valid_rows)}  |  Skipped: {skipped}")
print(f"Audit file: {audit_path}")

if not valid_rows:
    print("Nothing to process. Exiting.")
    audit_file.close()
    cur.close()
    conn.close()
    sys.exit(0)

confirm = input("\nType YES to continue execution: ")
if confirm != "YES":
    print("Execution cancelled.")
    for item in valid_rows:
        write_audit(item['raw_row'], item['resolved'], ["execution_cancelled"], "failed")
    audit_file.close()
    cur.close()
    conn.close()
    sys.exit(0)

# ── Process valid rows ────────────────────────────────────────────────────────
print("\nProcessing...")
count = 0

for item in valid_rows:
    lead_id      = item['lead_id']
    contact_id   = item['contact_id']
    old_rm_id    = item['old_rm_id']
    new_rm_id    = item['new_rm_id']
    status_id    = item['status_id']
    substatus_id = item['substatus_id']
    resolved     = item['resolved'].copy()

    print(f"  Processing lead_id={lead_id} ({item['contact_name']}) -> new_rm={new_rm_id}")

    try:
        # 1. Close old contact_mapping
        cur.execute("""
            SELECT mapping_id
            FROM contact_mapping
            WHERE lead_id   = %s
              AND rm_id     = %s
              AND type      = 'Sales'
              AND end_date IS NULL
            ORDER BY mapping_id DESC
            LIMIT 1
        """, (lead_id, old_rm_id))
        mapping = cur.fetchone()

        if mapping:
            cur.execute("""
                UPDATE contact_mapping
                SET end_date       = NOW(),
                    is_transferred = TRUE,
                    updated_at     = NOW(),
                    updated_by     = %s
                WHERE mapping_id   = %s
            """, (SYSTEM_USER_ID, mapping['mapping_id']))

        # 2. Insert new contact_mapping
        cur.execute("""
            INSERT INTO contact_mapping
                (contact_id, lead_id, rm_id, type, from_date,
                 company_id, created_at, created_by, updated_at, updated_by)
            VALUES (%s, %s, %s, 'Sales', NOW(), %s, NOW(), %s, NOW(), %s)
            RETURNING mapping_id
        """, (contact_id, lead_id, new_rm_id, COMPANY_ID, SYSTEM_USER_ID, SYSTEM_USER_ID))
        new_mapping_id = cur.fetchone()['mapping_id']
        resolved['new_mapping_id'] = new_mapping_id

        # 3. Update lead.rm_id
        cur.execute("""
            UPDATE lead
            SET rm_id      = %s,
                updated_at = NOW()
            WHERE lead_id  = %s
        """, (new_rm_id, lead_id))

        # 4. Complete old follow_up
        cur.execute("""
            SELECT follow_up_id
            FROM follow_up
            WHERE lead_id      = %s
              AND rm_id        = %s
              AND is_completed = FALSE
            ORDER BY follow_up_id DESC
            LIMIT 1
        """, (lead_id, old_rm_id))
        fu = cur.fetchone()

        if fu:
            cur.execute("""
                UPDATE follow_up
                SET is_completed = TRUE,
                    completed_on = NOW(),
                    updated_at   = NOW()
                WHERE follow_up_id = %s
            """, (fu['follow_up_id'],))

        # 5. Insert new follow_up
        cur.execute("""
            INSERT INTO follow_up
                (company_id, lead_id, contact_id, rm_id, status_id, substatus_id,
                 activity_type_id, follow_up, is_completed,
                 created_at, created_by, updated_at, updated_by)
            VALUES (%s, %s, %s, %s, %s, %s, 1, NOW(), FALSE, NOW(), %s, NOW(), %s)
        """, (COMPANY_ID, lead_id, contact_id, new_rm_id,
              status_id, substatus_id, SYSTEM_USER_ID, SYSTEM_USER_ID))

        # 6. Backup record
        cur.execute("""
            INSERT INTO contact_transfer_backup
                (lead_id, rm_id, old_rm_id, status_id, substatus_id,
                 mapping_id, created_at, session_id)
            VALUES (%s, %s, %s, %s, %s, %s, NOW(), %s)
        """, (lead_id, new_rm_id, old_rm_id, status_id,
              substatus_id, new_mapping_id, session_id))

        # conn.commit()
        count += 1
        write_audit(item['raw_row'], resolved, [], "success")
        print(f"  [{count}] Lead {lead_id} transferred successfully")

    except Exception as e:
        conn.rollback()
        err_msg = f"db_error: {str(e)}"
        print(f"  [ERROR] lead_id={lead_id}: {err_msg}")
        write_audit(item['raw_row'], resolved, [err_msg], "failed")

# ── Cleanup ───────────────────────────────────────────────────────────────────
conn.commit()
audit_file.close()
cur.close()
conn.close()

# ── Summary ───────────────────────────────────────────────────────────────────
print(f"\n{'='*55}")
print(f"Transferred : {count}")
print(f"Skipped     : {skipped}")
print(f"Audit file  : {audit_path}")
print("End -->", datetime.now())