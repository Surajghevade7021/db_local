import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
from config import db_credentials

SYSTEM_USER_ID = 1
BATCH_SIZE = 100
COMPANY_ID = 1
SYSTEM_USER_ID = 1

PRODUCT_MAP = {
    "dhanwaan": 5,
    "dhanwaan + mpo": 8,
    "dhanwaan pmp": 11,
    "pmp": 4,
    "5*5 strategy": 1,
    "5*5+mispriced": 2,
    "mispriced": 3
}

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)

file_path = r"E:\Download\Jan T2 Calling for CS RM Change (1).csv"
df = pd.read_csv(file_path, encoding="latin-1")
# print(df.shape)
# exit()
print("Total rows in CSV:", len(df))

df["New RM"] = df["New RM"].astype(str).str.strip().str.lower()
df["OLD RM"] = df["OLD RM"].astype(str).str.strip().str.lower()
df["Revised Email id"] = df["Revised Email id"].astype(str).str.strip().str.lower()
df["Final Product"] = df["Final Product"].astype(str).str.strip().str.lower()

df["product_id"] = df["Final Product"].map(PRODUCT_MAP)
df = df[~df["product_id"].isna()].copy()

df["Mark"] = "Not Done"

new_rm_names = df["New RM"].unique().tolist()
old_rm_names = df["OLD RM"].unique().tolist()
email_ids = df["Revised Email id"].unique().tolist()

cur.execute(
    """
    SELECT user_id, lower(full_name) AS rm_name
    FROM mst_user
    WHERE is_active
      AND lower(full_name) = ANY(%s)
    """,
    (new_rm_names + old_rm_names,)
)
rm_df = pd.DataFrame(cur.fetchall())

cur.execute(
    """
    SELECT contact_id, lower(email_address) AS email
    FROM contact
    WHERE lower(email_address) = ANY(%s)
    """,
    (email_ids,)
)
contact_df = pd.DataFrame(cur.fetchall())

df = df.merge(
    rm_df.rename(columns={"user_id": "new_owner_id", "rm_name": "New RM"}),
    on="New RM",
    how="inner"
)

rm_df.rename(columns={"rm_name": "OLD RM"})

df = df.merge(
    rm_df.rename(columns={"user_id": "old_owner_id", "rm_name": "OLD RM"}),
    on="OLD RM",
    how="left"
)
df["old_owner_id"] = df["old_owner_id"].fillna(9999999).astype(int)

df = df.merge(
    contact_df.rename(columns={"email": "Revised Email id"}),
    on="Revised Email id",
    how="inner"
)

contact_ids = df['contact_id'].astype(int).tolist()
cur.execute(
    """
    SELECT lead_id,contact_id
    FROM lead l
    WHERE l.substatus_id=29 and l.status_id=6 and l.contact_id = ANY(%s)
    """,
    (contact_ids,)
)
lead_df = pd.DataFrame(cur.fetchall())

df = df.merge(
    lead_df,
    on="contact_id",
    how="left"
)
processed = 0
print(df)
df.to_csv("E:\\Download\\retail_customer_feedback_24_12.csv")
print("Qualified rows to process:", len(df))
exit()
try:
    for row in df.itertuples(index=True):

        contact_id = int(row.contact_id)
        lead_id = int(row.lead_id)
        new_rm_id = int(row.new_owner_id)
        old_rm_id = int(row.old_owner_id)

        cur.execute(
            """
            SELECT mapping_id, lead_id
            FROM contact_mapping
            WHERE contact_id = %s
              AND rm_id = %s
              AND type = 'Customer Service'
              AND end_date IS NULL
            ORDER BY mapping_id DESC
            LIMIT 1
            """,
            (contact_id, old_rm_id)
            # (contact_id, )
        )

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
            VALUES (%s,%s,%s,'Customer Service',NOW(),%s,NOW(),%s,NOW(),%s)
            RETURNING mapping_id
        """, (contact_id, lead_id, rm_id, COMPANY_ID, SYSTEM_USER_ID, SYSTEM_USER_ID))

        new_mapping_id = cur.fetchone()["mapping_id"]

        cur.execute(
            """
            UPDATE feedback_response
            SET assigned_to = %s,
                updated_at = NOW()
            WHERE feedback_response_id = (
                SELECT feedback_response_id
                FROM feedback_response
                WHERE contact_id = %s
                ORDER BY 
                    (assigned_to IS NOT DISTINCT FROM %s) DESC,
                    feedback_response_id DESC
                LIMIT 1
            )
            """,
        (new_rm_id, contact_id, old_rm_id)
        )

        cur.execute(
            """
            UPDATE follow_up
            SET is_completed = TRUE,
                completed_on = NOW(),
                updated_at = NOW()
            WHERE follow_up_id = (
                SELECT follow_up_id
                FROM follow_up
                WHERE contact_id = %s
                  AND rm_id = %s
                ORDER BY follow_up_id DESC
                LIMIT 1
            )
            """,
            (contact_id, old_rm_id)
        )

        cur.execute(
            """
            INSERT INTO follow_up
            (company_id, lead_id, onboarding_id, contact_id, rm_id,
             customer_id, activity_type_id, status_id, substatus_id,
             follow_up, is_completed, created_at, created_by,
             updated_at, updated_by, reference_id, source, source_info)
            SELECT
                company_id,
                lead_id,
                onboarding_id,
                contact_id,
                %s,
                customer_id,
                1,
                status_id,
                substatus_id,
                NOW(),
                FALSE,
                NOW(),
                %s,
                NOW(),
                %s,
                reference_id,
                source,
                source_info
            FROM follow_up
            WHERE contact_id = %s
            ORDER BY follow_up_id DESC
            LIMIT 1
            """,
            (new_rm_id, SYSTEM_USER_ID, SYSTEM_USER_ID, contact_id)
        )

        df.at[row.Index, "Mark"] = "Done"
        processed += 1
        
        # conn.commit()
        # exit()
        print(f"contact_id is {contact_id}")
        
        if processed % BATCH_SIZE == 0:
            conn.commit()
            print(f"Committed {processed} records")

    conn.commit()

except Exception as e:
    conn.rollback()
    raise e

finally:
    cur.close()
    conn.close()

output_path = r"E:\Download\retail_customer_feedback_1.csv"
df.to_csv(output_path, index=False)
print("Processing complete. Output written to:", output_path)