import psycopg2
from psycopg2.extras import RealDictCursor
from config import db_credentials
from datetime import datetime
from itertools import cycle

print("Start -->", datetime.now())


COMPANY_ID = 1
SYSTEM_USER_ID = 1

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)


lead_fetch_query = """
            SELECT
	t.*
FROM
	(
	SELECT
		pba.*,
		l.lead_id,
		l.lead_number,
		l.contact_id,
		l.status_id,
		l.substatus_id,
		l.rm_id,
        mu.user_id,
        pba."Customer Email",
		ROW_NUMBER() OVER (PARTITION BY l.contact_id
	ORDER BY
		l.created_at DESC) AS rn
	FROM
		public.lead l
	 JOIN contact c ON
		l.contact_id = c.contact_id
	RIGHT JOIN pull_back_allocation pba ON
		trim(lower(pba."Customer Email" ))= trim(lower(c.email_address))
	 JOIN mst_user mu ON
		trim(lower(mu.email_address))= trim(lower(pba."Counsellor Email"))
		--AND mu.is_active 
		--JOIN public.mst_user mu ON mu.user_id = l.rm_id
	WHERE
		l.is_active
		AND l.lead_source_id = 57
) AS t
WHERE
	rn = 1
"""

cur.execute(lead_fetch_query)
lead_data = cur.fetchall()

print("Total leads:", len(lead_data))
print("Retrieval -->", datetime.now())

# exit()
try:
    count = 0

    for lead in lead_data:

        lead_id = lead["lead_id"]
        contact_id = lead["contact_id"]
        status_id = lead["status_id"]
        substatus_id = lead["substatus_id"]
        old_rm_id = lead["rm_id"]
        customer_email=lead["Customer Email"]
        rm_id = lead["user_id"]

        print(f"Processing lead_id={lead_id} -> new_rm={rm_id}")

        cur.execute("""
            SELECT mapping_id
            FROM contact_mapping
            WHERE lead_id=%s
              AND rm_id=%s
              AND type='Sales'
              AND end_date IS NULL
            ORDER BY mapping_id DESC
            LIMIT 1
        """, (lead_id, old_rm_id))

        mapping = cur.fetchone()

        if mapping:
            old_mapping_id = mapping["mapping_id"]

            cur.execute("""
                UPDATE contact_mapping
                SET end_date = NOW(),
                    is_transferred = TRUE,
                    updated_at = NOW(),
                    updated_by = %s
                WHERE mapping_id = %s
            """, (SYSTEM_USER_ID, old_mapping_id))

        cur.execute("""
            INSERT INTO contact_mapping
            (contact_id, lead_id, rm_id, type, from_date,
             company_id, created_at, created_by, updated_at, updated_by)
            VALUES (%s,%s,%s,'Sales',NOW(),%s,NOW(),%s,NOW(),%s)
            RETURNING mapping_id
        """, (contact_id, lead_id, rm_id, COMPANY_ID, SYSTEM_USER_ID, SYSTEM_USER_ID))

        new_mapping_id = cur.fetchone()["mapping_id"]

        cur.execute("""
            UPDATE lead
            SET rm_id=%s,
                updated_at=NOW()
            WHERE lead_id=%s
        """, (rm_id, lead_id))

        cur.execute("""
            SELECT follow_up_id
            FROM follow_up
            WHERE lead_id=%s
              AND rm_id=%s
              AND is_completed=false
            ORDER BY follow_up_id DESC
            LIMIT 1
        """, (lead_id, old_rm_id))

        fu = cur.fetchone()

        if fu:
            cur.execute("""
                UPDATE follow_up
                SET is_completed=TRUE,
                    completed_on=NOW(),
                    updated_at=NOW()
                WHERE follow_up_id=%s
            """, (fu["follow_up_id"],))

        cur.execute("""
            INSERT INTO follow_up
            (company_id, lead_id, contact_id, rm_id, status_id, substatus_id,
             follow_up, is_completed, created_at, created_by, updated_at, updated_by)
            VALUES (%s,%s,%s,%s,%s,%s,NOW(),FALSE,NOW(),%s,NOW(),%s)
        """, (COMPANY_ID, lead_id, contact_id, rm_id, status_id, substatus_id,
              SYSTEM_USER_ID, SYSTEM_USER_ID))

        cur.execute("""
            INSERT INTO contact_transfer_backup
            (lead_id, rm_id, old_rm_id, status_id, substatus_id, mapping_id, created_at)
            VALUES (%s,%s,%s,%s,%s,%s,NOW())
        """, (lead_id, rm_id, old_rm_id, status_id, substatus_id, new_mapping_id))
        
        cur.execute("""
            UPDATE pull_back_allocation
            SET record_insert = 1
            WHERE "Customer Email" = %s
        """, (customer_email,))

        conn.commit()   

        count += 1
        print(f"{count} Lead {lead_id} transferred successfully")
        exit()
except Exception as e:
    conn.rollback()
    raise e

finally:
    cur.close()
    conn.close()

print("End -->", datetime.now())