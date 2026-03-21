import psycopg2
from psycopg2.extras import RealDictCursor
from config import db_credentials
from datetime import datetime

print("Start -->", datetime.now())

lead_ids = list(map(int, input("Enter Lead IDs separated by space: ").split()))
location_id = int(input("Enter Location ID: "))

COMPANY_ID = 1
SYSTEM_USER_ID = 1
SYSTEM_USERS = (1,2,3,4)

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)


cur.execute("""
SELECT center_head_id
FROM mst_location
WHERE location_id = %s
""",(location_id,))

center_head_id = cur.fetchone()["center_head_id"]

print("Center Head ID:",center_head_id)


def is_sales_user(user_id):

    if user_id in SYSTEM_USERS:
        return False

    cur.execute("""
    SELECT mu.user_id
    FROM mst_user mu
    JOIN mst_department md
    ON md.department_id = mu.department_id
    WHERE mu.user_id=%s
    AND mu.is_active = TRUE
    AND md.group_name ILIKE '%%sales%%'
    """,(user_id,))

    return cur.fetchone() is not None


# ----------------------------------------------------
# Function to climb hierarchy
# ----------------------------------------------------
def find_valid_manager(user_id):

    visited=set()

    while user_id and user_id not in visited:

        visited.add(user_id)

        if is_sales_user(user_id):
            return user_id

        cur.execute("""
        SELECT reporting_manager_id
        FROM mst_user
        WHERE user_id=%s
        """,(user_id,))

        row=cur.fetchone()

        if not row:
            break

        user_id=row["reporting_manager_id"]

    return center_head_id



cur.execute("""
SELECT 
l.lead_id,
l.contact_id,
l.status_id,
l.substatus_id,
l.rm_id
FROM lead l
WHERE l.lead_id = ANY(%s)
""",(lead_ids,))

lead_data=cur.fetchall()

print("Total Leads:",len(lead_data))

count=0

try:

    for lead in lead_data:

        lead_id=lead["lead_id"]
        contact_id=lead["contact_id"]
        status_id=lead["status_id"]
        substatus_id=lead["substatus_id"]
        current_rm=lead["rm_id"]

        if current_rm and is_sales_user(current_rm):

            print(f"Lead {lead_id} valid RM {current_rm} → skipping")
            continue

        new_rm=find_valid_manager(current_rm)

        print(f"Lead {lead_id} assigning RM {new_rm}")


        cur.execute("""
        SELECT mapping_id
        FROM contact_mapping
        WHERE lead_id=%s
        AND rm_id=%s
        AND type='Sales'
        AND end_date IS NULL
        ORDER BY mapping_id DESC
        LIMIT 1
        """,(lead_id,current_rm))

        mapping=cur.fetchone()

        if mapping:

            cur.execute("""
            UPDATE contact_mapping
            SET end_date=NOW(),
            is_transferred=TRUE,
            updated_at=NOW(),
            updated_by=%s
            WHERE mapping_id=%s
            """,(SYSTEM_USER_ID,mapping["mapping_id"]))


        cur.execute("""
        INSERT INTO contact_mapping
        (contact_id,lead_id,rm_id,type,from_date,
        company_id,created_at,created_by,updated_at,updated_by)
        VALUES (%s,%s,%s,'Sales',NOW(),%s,NOW(),%s,NOW(),%s)
        """,(contact_id,lead_id,new_rm,
        COMPANY_ID,SYSTEM_USER_ID,SYSTEM_USER_ID))


        cur.execute("""
        UPDATE lead
        SET rm_id=%s,updated_at=NOW()
        WHERE lead_id=%s
        """,(new_rm,lead_id))


        cur.execute("""
        SELECT follow_up_id
        FROM follow_up
        WHERE lead_id=%s
        AND rm_id=%s
        AND is_completed=false
        ORDER BY follow_up_id DESC
        LIMIT 1
        """,(lead_id,current_rm))

        fu=cur.fetchone()

        if fu:

            cur.execute("""
            UPDATE follow_up
            SET is_completed=TRUE,
            completed_on=NOW(),
            updated_at=NOW()
            WHERE follow_up_id=%s
            """,(fu["follow_up_id"],))


        cur.execute("""
        INSERT INTO follow_up
        (company_id,lead_id,contact_id,rm_id,
        status_id,substatus_id,activity_type_id,
        follow_up,is_completed,created_at,
        created_by,updated_at,updated_by)
        VALUES (%s,%s,%s,%s,%s,%s,1,NOW(),FALSE,
        NOW(),%s,NOW(),%s)
        """,(COMPANY_ID,lead_id,contact_id,new_rm,
        status_id,substatus_id,
        SYSTEM_USER_ID,SYSTEM_USER_ID))

        conn.commit()

        count+=1

        print(f"{count} Lead {lead_id} transferred")

except Exception as e:

    conn.rollback()
    raise e

finally:

    cur.close()
    conn.close()

print("End -->",datetime.now())