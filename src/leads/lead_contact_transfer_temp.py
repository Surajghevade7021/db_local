import psycopg2
from psycopg2.extras import RealDictCursor
import sys
import os
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, "..", ".."))
if project_root not in sys.path:
    sys.path.insert(0, project_root)
from config import db_credentials
from datetime import datetime
from itertools import cycle

print("Start -->", datetime.now())

# new_rm_list = [2993, 2924]
new_rm_list=list(map(int, input("Enter NEW RM IDs separated by space: ").split()))
rm_cycle = cycle(new_rm_list)

# Old_RM_ID = [2230]
Old_RM_ID=list(map(int, input("Enter OLD RM IDs separated by space: ").split()))
COMPANY_ID = 1
SYSTEM_USER_ID = 1
#substatus_id=[]
substatus_id = list(map(int, input("Enter Substatus separated by space: ").split()))
# print(substatus_id)
LIMIT=int(input("ENTER NUMBER OF Lead ReAssigned: "))


# LIMIT=10

if len(substatus_id)<=0:
    substatus_id=[1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 54, 55, 56, 57, 58, 59, 60, 61, 62, 64, 65]
else:
    pass
conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)


lead_fetch_query = """
SELECT l.lead_id,
       l.lead_number,
       l.contact_id,
       l.status_id,
       l.substatus_id,
       l.rm_id,
       coalesce(l.updated_at,l.created_at) as old_pool
FROM public.lead l
JOIN public.mst_user mu ON mu.user_id = l.rm_id
WHERE l.is_active
  AND NOT (23 = ANY(l.sub_product_ids))  
  AND l.status_id < 6
  AND l.lead_id in (571418)
  AND l.substatus_id = ANY(%s) 
   -- AND NOT (
    --    l.substatus_id IN (10,11)
    --    AND COALESCE(l.updated_at, l.created_at) <= NOW() - INTERVAL '61 days'
    --  )
ORDER BY l.lead_id
LIMIT %s;
"""

cur.execute(lead_fetch_query, (substatus_id,LIMIT))
lead_data = cur.fetchall()

cur.execute("select max(session_id ) from contact_transfer_backup")
session_id=cur.fetchall()
session_id=session_id[0]['max']
session_id=str(session_id+1)

print("Total leads:", len(lead_data))
print("Retrieval -->", datetime.now())

# exit()
confirm = input("Type YES to continue execution: ")
if confirm != "YES":
    print("Execution cancelled")
    exit()
try:
    count = 0

    for lead in lead_data:

        lead_id = lead["lead_id"]
        contact_id = lead["contact_id"]
        status_id = lead["status_id"]
        substatus_id = lead["substatus_id"]
        old_rm_id = lead["rm_id"]

        rm_id = next(rm_cycle)

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
            (company_id, lead_id, contact_id, rm_id, status_id, substatus_id, activity_type_id,
             follow_up, is_completed, created_at, created_by, updated_at, updated_by)
            VALUES (%s,%s,%s,%s,%s,%s,1,NOW(),FALSE,NOW(),%s,NOW(),%s)
        """, (COMPANY_ID, lead_id, contact_id, rm_id, status_id, substatus_id,
            SYSTEM_USER_ID, SYSTEM_USER_ID))

        cur.execute("""
            INSERT INTO contact_transfer_backup
            (lead_id, rm_id, old_rm_id, status_id, substatus_id, mapping_id, created_at,session_id )
            VALUES (%s,%s,%s,%s,%s,%s,NOW(),%s)
        """, (lead_id, rm_id, old_rm_id, status_id, substatus_id, new_mapping_id,session_id))

        conn.commit()   

        count += 1
        print(f"{count} Lead {lead_id} transferred successfully")

except Exception as e:
    conn.rollback()
    raise e

finally:
    cur.close()
    conn.close()

print("End -->", datetime.now())