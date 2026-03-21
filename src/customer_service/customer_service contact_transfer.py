import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
from config import *

conn=psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

color_fetch_query = """
        with color as (
        select  distinct on (fr.lead_id) fr.lead_id,fr.color, fr.assigned_to  from feedback_response fr where fr.lead_id in (
        select
            l.lead_id 
        from
            onboarding o
        join lead l on
            o.lead_id = l.lead_id
        where
            o.subscription_start_date::date between '2025-01-01' and '2025-01-31' and l.substatus_id =29) and fr.color is not null order by fr.lead_id,fr.feedback_response_id desc)
        select  distinct on (fr.lead_id) fr.lead_id,coalesce (fr.color, c.color) as color, fr.assigned_to  from feedback_response fr left join color c on c.lead_id=fr.lead_id where fr.lead_id in (
        select
            l.lead_id 
        from
            onboarding o
        join lead l on
            o.lead_id = l.lead_id 
        where
            o.subscription_start_date::date between '2025-01-01' and '2025-01-31' and l.substatus_id =29)  order by fr.lead_id,fr.feedback_response_id desc
    """

cur.execute(color_fetch_query)
contact_data = cur.fetchall()
df2=pd.DataFrame(contact_data)
print(df2.head())

df2["mark"] = None
df3 = df2.drop_duplicates(subset=['color', 'assigned_to'])

rm_list = [1495, 2279, 2278, 470, 2277, 433, 432, 2686, 2275, 2528, 122, 2274, 2273, 2146, 444, 2280]
print(f"Total Data in data is {df3.shape}")
for _, d in df3.iterrows():
    assigned_to = int(d["assigned_to"])
    if assigned_to not in rm_list:
        continue

    lead_id = int(d["lead_id"])
    lead_id = int(d["lead_id"])
    fb_lead_fetch_query = """ SELECT feedback_response_id,contact_id FROM feedback_response fr WHERE  lead_id = %s order by feedback_response_id desc limit 1"""

    cur.execute(fb_lead_fetch_query, (lead_id,))
    validation=cur.fetchone()
    if validation:
        feedback_response_id = validation["feedback_response_id"]
        contact_id = validation["contact_id"]

        fb_update_query = """
            UPDATE public.feedback_response SET assigned_to=%s,  updated_at=now(), updated_by=1 WHERE feedback_response_id=%s and completed_on is null
            """
        cur.execute(fb_update_query, (assigned_to, feedback_response_id))

        print(cur.mogrify(fb_update_query, (assigned_to, feedback_response_id)).decode() + ";\n")
        

        follow_up_fetch_query = """SELECT lead_id, contact_id, follow_up_id FROM follow_up WHERE lead_id = %s AND is_completed IS FALSE AND substatus_id = 29 ORDER BY follow_up_id DESC LIMIT 1"""

        cur.execute(follow_up_fetch_query, (lead_id,))
        follow_up_data = cur.fetchall()

        for curr in follow_up_data:
            follow_up_id = curr["follow_up_id"]

        if follow_up_id:
            print(follow_up_id)

        follow_up_update_query = """
            UPDATE follow_up SET completed_on = now(), is_completed = TRUE, updated_by = 1, updated_at = now()  WHERE follow_up_id = %s  """
        cur.execute(follow_up_update_query, (follow_up_id,))

        follow_up_ins_query = """
            INSERT INTO follow_up (
                activity_id, company_id, lead_id, onboarding_id, contact_id,
                rm_id, customer_id, activity_type_id, status_id, substatus_id,
                follow_up, is_completed, created_at, created_by, updated_at,
                updated_by, reference_id, source, source_info, completed_on
            )
            SELECT
                activity_id, company_id, lead_id, onboarding_id, contact_id,
                rm_id, customer_id, activity_type_id, status_id, substatus_id,
                follow_up, is_completed, created_at, created_by, updated_at,
                updated_by, reference_id, source, source_info, completed_on
            FROM follow_up
            WHERE follow_up_id = %s
        """
        cur.execute(follow_up_ins_query, (follow_up_id,))

        new_follow_up_query = """
            SELECT follow_up_id FROM follow_up WHERE lead_id = %s ORDER BY follow_up_id DESC LIMIT 1
        """
        cur.execute(new_follow_up_query, (lead_id,))
        new_row = cur.fetchone()

        if new_row:
            new_follow_up_id = new_row["follow_up_id"]

            follow_new_update_query = """
                UPDATE follow_up
                SET completed_on = NULL,
                    is_completed = FALSE,
                    rm_id = %s
                WHERE follow_up_id = %s
            """
            cur.execute(follow_new_update_query, (rm_id, new_follow_up_id))
        else:
            follow_up_insert_query = """
                    INSERT INTO follow_up ( company_id, lead_id, contact_id, rm_id,activity_type_id , status_id, substatus_id, follow_up, is_completed, created_at, created_by, updated_at, updated_by ) VALUES ( 1, %s, %s, %s,6, 6, 29, NOW(), FALSE, NOW(), 1, NOW(), 1  )
                """
            cur.execute(follow_up_insert_query, (lead_id, contact_id, assigned_to))

            contact_mapping_insert_query = """
                    INSERT INTO contact_mapping ( contact_id, rm_id, type, is_transferred, from_date, company_id, created_at, created_by, updated_at, updated_by, lead_id
                    ) VALUES (  %s, %s, 'Sales', FALSE, CURRENT_DATE, 1, NOW(), 1, NOW(), 1, %s  )
                """
        
        cm_rm_update_query = """UPDATE contact_mapping SET end_date = now(), is_transferred = TRUE, updated_by = 1, updated_at = now()
            WHERE mapping_id = ( SELECT mapping_id FROM contact_mapping WHERE lead_id = %s AND end_date IS NULL AND type = 'Customer Service' ORDER BY mapping_id DESC  LIMIT 1  )"""
        cur.execute(cm_rm_update_query, (lead_id,))

        contact_mapping_ins_query = """
            INSERT INTO contact_mapping ( contact_id, lead_id, rm_id, type, from_date,  company_id, created_at, created_by, updated_at, updated_by
            ) SELECT contact_id, lead_id, rm_id, type, from_date, company_id, created_at, created_by, updated_at, updated_by FROM contact_mapping
            WHERE mapping_id = ( SELECT mapping_id FROM contact_mapping WHERE lead_id = %s AND end_date IS NOT NULL  AND type = 'Customer Service' ORDER BY mapping_id DESC LIMIT 1 )RETURNING mapping_id
            """
        cur.execute(contact_mapping_ins_query, (lead_id,))
        new_contact_mapping_id = cur.fetchone()["mapping_id"]

        cm_rm_reopen_query = """ UPDATE contact_mapping SET end_date = NULL,is_transferred = FALSE,  rm_id = %s WHERE mapping_id = %s """
        cur.execute(cm_rm_reopen_query, (rm_id, new_contact_mapping_id))
        df2.loc[df2["lead_id"] == lead_id, "mark"] = "done"
        
pending_df = df2[df2["mark"].isna()]

print(f"Pending records: {pending_df.shape[0]}")

for _, d in pending_df.iterrows():
    rm_id = rm_list[i % len(rm_list)]

    lead_id = int(d["lead_id"])

    fb_lead_fetch_query = """
        SELECT feedback_response_id, contact_id
        FROM feedback_response
        WHERE lead_id = %s
        ORDER BY feedback_response_id DESC
        LIMIT 1
    """

    cur.execute(fb_lead_fetch_query, (lead_id,))
    validation = cur.fetchone()

    if not validation:
        continue

    feedback_response_id = validation["feedback_response_id"]
    contact_id = validation["contact_id"]

    fb_update_query = """
        UPDATE public.feedback_response
        SET assigned_to = %s, updated_at = now(), updated_by = 1
        WHERE feedback_response_id = %s AND completed_on IS NULL
    """
    cur.execute(fb_update_query, (rm_id, feedback_response_id))

    follow_up_fetch_query = """SELECT lead_id, contact_id, follow_up_id FROM follow_up WHERE lead_id = %s AND is_completed IS FALSE AND substatus_id = 29 ORDER BY follow_up_id DESC LIMIT 1"""

    cur.execute(follow_up_fetch_query, (lead_id,))
    follow_up_data = cur.fetchall()

    for curr in follow_up_data:
        follow_up_id = curr["follow_up_id"]

    if follow_up_id:
        print(follow_up_id)

        follow_up_update_query = """
            UPDATE follow_up SET completed_on = now(), is_completed = TRUE, updated_by = 1, updated_at = now()  WHERE follow_up_id = %s  """
        cur.execute(follow_up_update_query, (follow_up_id,))

        follow_up_ins_query = """
            INSERT INTO follow_up (
                activity_id, company_id, lead_id, onboarding_id, contact_id,
                rm_id, customer_id, activity_type_id, status_id, substatus_id,
                follow_up, is_completed, created_at, created_by, updated_at,
                updated_by, reference_id, source, source_info, completed_on
            )
            SELECT
                activity_id, company_id, lead_id, onboarding_id, contact_id,
                rm_id, customer_id, activity_type_id, status_id, substatus_id,
                follow_up, is_completed, created_at, created_by, updated_at,
                updated_by, reference_id, source, source_info, completed_on
            FROM follow_up
            WHERE follow_up_id = %s
        """
        cur.execute(follow_up_ins_query, (follow_up_id,))

        new_follow_up_query = """
            SELECT follow_up_id FROM follow_up WHERE lead_id = %s ORDER BY follow_up_id DESC LIMIT 1
        """
        cur.execute(new_follow_up_query, (lead_id,))
        new_row = cur.fetchone()

        if new_row:
            new_follow_up_id = new_row["follow_up_id"]

            follow_new_update_query = """
                UPDATE follow_up
                SET completed_on = NULL,
                    is_completed = FALSE,
                    rm_id = %s
                WHERE follow_up_id = %s
            """
            cur.execute(follow_new_update_query, (rm_id, new_follow_up_id))
        else:
            follow_up_insert_query = """
                    INSERT INTO follow_up ( company_id, lead_id, contact_id, rm_id,activity_type_id , status_id, substatus_id, follow_up, is_completed, created_at, created_by, updated_at, updated_by ) VALUES ( 1, %s, %s, %s,6, 6, 29, NOW(), FALSE, NOW(), 1, NOW(), 1  )
                """
            cur.execute(follow_up_insert_query, (lead_id, contact_id, rm_id))

        contact_mapping_insert_query = """
                    INSERT INTO contact_mapping ( contact_id, rm_id, type, is_transferred, from_date, company_id, created_at, created_by, updated_at, updated_by, lead_id
                    ) VALUES (  %s, %s, 'Sales', FALSE, CURRENT_DATE, 1, NOW(), 1, NOW(), 1, %s  )
            """
        
        cm_rm_update_query = """UPDATE contact_mapping SET end_date = now(), is_transferred = TRUE, updated_by = 1, updated_at = now()
            WHERE mapping_id = ( SELECT mapping_id FROM contact_mapping WHERE lead_id = %s AND end_date IS NULL AND type = 'Customer Service' ORDER BY mapping_id DESC  LIMIT 1  )"""
        cur.execute(cm_rm_update_query, (lead_id,))

        contact_mapping_ins_query = """
            INSERT INTO contact_mapping ( contact_id, lead_id, rm_id, type, from_date,  company_id, created_at, created_by, updated_at, updated_by
            ) SELECT contact_id, lead_id, rm_id, type, from_date, company_id, created_at, created_by, updated_at, updated_by FROM contact_mapping
            WHERE mapping_id = ( SELECT mapping_id FROM contact_mapping WHERE lead_id = %s AND end_date IS NOT NULL  AND type = 'Customer Service' ORDER BY mapping_id DESC LIMIT 1 )RETURNING mapping_id
            """
        cur.execute(contact_mapping_ins_query, (lead_id,))
        new_contact_mapping_id = cur.fetchone()["mapping_id"]

        cm_rm_reopen_query = """ UPDATE contact_mapping SET end_date = NULL,is_transferred = FALSE,  rm_id = %s WHERE mapping_id = %s """
        cur.execute(cm_rm_reopen_query, (rm_id, new_contact_mapping_id))

    df2.loc[df2["lead_id"] == lead_id, "mark"] = "done"    
conn.commit()
    
output_path = r"E:\Download\customer_service_task.csv"
df2.to_csv(output_path, index=False)
print("CSV exported:", output_path)