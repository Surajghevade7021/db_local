import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
from config import db_credentials
import os
import datetime

SYSTEM_USER_ID = 1
COMPANY_ID = 1

# ----------------------------------
# CONNECT DATABASE
# ----------------------------------

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)

# ----------------------------------
# USER INPUT
# ----------------------------------

file_path = input("Enter CSV File Path: ").strip().strip('"').strip("'")

if not os.path.exists(file_path):
    raise Exception("CSV file not found.")

df = pd.read_csv(file_path, encoding="latin-1")

print("Total Rows in File:", len(df))

# ----------------------------------
# INITIALIZE PROCESS COLUMNS
# ----------------------------------

df["PROCESS_STATUS"] = "PENDING"
df["REMARKS"] = ""
df["NEW_RM_ID"] = None
df["NEW_MAPPING_ID"] = None

# ----------------------------------
# CLEAN DATA
# ----------------------------------

df["Product"] = df["Product"].fillna("").astype(str).str.lower().str.strip()
df["Email"] = df["Email"].fillna("").astype(str).str.lower().str.strip()
df["CSRM"] = df["CSRM"].fillna("").astype(str).str.lower().str.strip()

# ----------------------------------
# PRODUCT VALIDATION
# ----------------------------------

product_names = df["Product"].unique().tolist()

if product_names:

    cur.execute("""
        SELECT product_id,
               sub_product_id,
               LOWER(TRIM(name)) AS name
        FROM mst_subproduct
        WHERE is_active = TRUE
          AND LOWER(TRIM(name)) = ANY(%s)
    """, (product_names,))

    product_df = pd.DataFrame(cur.fetchall())

    product_map = {
        row["name"]: row["product_id"]
        for _, row in product_df.iterrows()
    }

    df["product_id"] = df["Product"].map(product_map)

mask = df["product_id"].isna()
df.loc[mask, "PROCESS_STATUS"] = "FAILED"
df.loc[mask, "REMARKS"] = "PRODUCT NOT FOUND"

# ----------------------------------
# CONTACT VALIDATION
# ----------------------------------

emails = df["Email"].unique().tolist()

if emails:

    cur.execute("""
        SELECT LOWER(email_address) AS email_address, contact_id
        FROM contact
        WHERE LOWER(email_address) = ANY(%s)
    """, (emails,))

    contact_df = pd.DataFrame(cur.fetchall())

    contact_map = {
        row["email_address"]: row["contact_id"]
        for _, row in contact_df.iterrows()
    }

    df["contact_id"] = df["Email"].map(contact_map)

mask = df["contact_id"].isna()
df.loc[(mask) & (df["PROCESS_STATUS"] == "PENDING"), "PROCESS_STATUS"] = "FAILED"
df.loc[(mask) & (df["PROCESS_STATUS"] == "PENDING"), "REMARKS"] = "CONTACT EMAIL NOT FOUND"

# ----------------------------------
# LEAD VALIDATION
# ----------------------------------

contact_ids = df["contact_id"].dropna().unique().tolist()

if contact_ids:

    cur.execute("""
        SELECT contact_id, lead_id
        FROM lead
        WHERE is_active = TRUE
          AND status_id = 6
          AND substatus_id = 29
          AND contact_id = ANY(%s)
    """, (contact_ids,))

    lead_df = pd.DataFrame(cur.fetchall())

    lead_map = {
        row["contact_id"]: row["lead_id"]
        for _, row in lead_df.iterrows()
    }

    df["lead_id"] = df["contact_id"].map(lead_map)

mask = df["lead_id"].isna()
df.loc[(mask) & (df["PROCESS_STATUS"] == "PENDING"), "PROCESS_STATUS"] = "FAILED"
df.loc[(mask) & (df["PROCESS_STATUS"] == "PENDING"), "REMARKS"] = "ACTIVE LEAD NOT FOUND"

# ----------------------------------
# RM VALIDATION
# ----------------------------------

csrms = df["CSRM"].unique().tolist()

if csrms:

    cur.execute("""
        SELECT LOWER(email_address) AS email_address, user_id
        FROM mst_user
        WHERE is_active = TRUE
          AND LOWER(email_address) = ANY(%s)
    """, (csrms,))

    rm_df = pd.DataFrame(cur.fetchall())

    rm_map = {
        row["email_address"]: row["user_id"]
        for _, row in rm_df.iterrows()
    }

    df["USER_ID"] = df["CSRM"].map(rm_map)

mask = df["USER_ID"].isna()
df.loc[(mask) & (df["PROCESS_STATUS"] == "PENDING"), "PROCESS_STATUS"] = "FAILED"
df.loc[(mask) & (df["PROCESS_STATUS"] == "PENDING"), "REMARKS"] = "ACTIVE RM NOT FOUND"

# ----------------------------------
# PROCESS TRANSFER
# ----------------------------------

valid_df = df[df["PROCESS_STATUS"] == "PENDING"].copy()

print("Valid Rows To Process:", len(valid_df))

processed = 0
# valid_df=valid_df[:2]
try:

    for row in valid_df.itertuples(index=True):
        print(processed)
        contact_id = row.contact_id
        lead_id = row.lead_id
        rm_id = row.USER_ID

        # ----------------------------------
        # CLOSE OLD MAPPING
        # ----------------------------------

        cur.execute("""
            SELECT mapping_id
            FROM contact_mapping
            WHERE contact_id = %s
              AND type = 'Customer Service'
              AND end_date IS NULL
            ORDER BY mapping_id DESC
            LIMIT 1
        """, (contact_id,))

        mapping = cur.fetchone()

        if mapping:

            cur.execute("""
                UPDATE contact_mapping
                SET end_date = NOW(),
                    is_transferred = TRUE,
                    updated_at = NOW(),
                    updated_by = %s
                WHERE mapping_id = %s
            """, (SYSTEM_USER_ID, mapping["mapping_id"]))

        # ----------------------------------
        # INSERT NEW MAPPING
        # ----------------------------------

        cur.execute("""
            INSERT INTO contact_mapping
            (contact_id, lead_id, rm_id, type, from_date,
             company_id, created_at, created_by, updated_at, updated_by)
            VALUES (%s,%s,%s,'Customer Service',NOW(),
                    %s,NOW(),%s,NOW(),%s)
            RETURNING mapping_id
        """, (
            contact_id,
            lead_id,
            rm_id,
            COMPANY_ID,
            SYSTEM_USER_ID,
            SYSTEM_USER_ID
        ))

        new_mapping_id = cur.fetchone()["mapping_id"]

        df.at[row.Index, "NEW_MAPPING_ID"] = new_mapping_id
        df.at[row.Index, "NEW_RM_ID"] = rm_id

        # ----------------------------------
        # FEEDBACK CHECK
        # ----------------------------------

        cur.execute("""
            SELECT feedback_response_id
            FROM feedback_response
            WHERE contact_id = %s
            ORDER BY feedback_response_id DESC
            LIMIT 1
        """, (contact_id,))

        feedback = cur.fetchone()

        if feedback:

            feedback_id = feedback["feedback_response_id"]

            cur.execute("""
                UPDATE feedback_response
                SET assigned_to = %s,
                    updated_at = NOW(),
                    updated_by = %s
                WHERE feedback_response_id = %s
            """, (rm_id, SYSTEM_USER_ID, feedback_id))

        else:

            cur.execute("""
                INSERT INTO feedback_response
                (company_id, contact_id, lead_id, assigned_to,
                 created_at, created_by, updated_at, updated_by, feedback_for_date)
                VALUES (%s,%s,%s,%s,NOW(),%s,NOW(),%s,NOW())
                RETURNING feedback_response_id
            """, (
                COMPANY_ID,
                contact_id,
                lead_id,
                rm_id,
                SYSTEM_USER_ID,
                SYSTEM_USER_ID
            ))

            feedback_id = cur.fetchone()["feedback_response_id"]

        # ----------------------------------
        # FOLLOW UP
        # ----------------------------------

        cur.execute("""
            SELECT follow_up_id
            FROM follow_up
            WHERE activity_type_id = 11
              AND contact_id = %s
              AND is_completed = FALSE
            ORDER BY follow_up_id DESC
            LIMIT 1
        """, (contact_id,))

        last_followup = cur.fetchone()

        if last_followup:

            cur.execute("""
                UPDATE follow_up
                SET is_completed = TRUE,
                    completed_on = NOW(),
                    updated_at = NOW(),
                    updated_by = %s
                WHERE follow_up_id = %s
            """, (
                SYSTEM_USER_ID,
                last_followup["follow_up_id"]
            ))

        cur.execute("""
            INSERT INTO follow_up
            (company_id, lead_id, contact_id, rm_id,
             activity_type_id, status_id, substatus_id,
             follow_up, is_completed,
             created_at, created_by, updated_at, updated_by,
             reference_id)
            VALUES (%s,%s,%s,%s,
                    11,6,29,
                    NOW(),FALSE,
                    NOW(),%s,NOW(),%s,
                    %s)
        """, (
            COMPANY_ID,
            lead_id,
            contact_id,
            rm_id,
            SYSTEM_USER_ID,
            SYSTEM_USER_ID,
            feedback_id
        ))

        conn.commit()

        df.at[row.Index, "PROCESS_STATUS"] = "SUCCESS"
        df.at[row.Index, "REMARKS"] = "TRANSFERRED"

        processed += 1

except Exception as e:

    conn.rollback()
    print("Fatal Error:", str(e))

finally:

    cur.close()
    conn.close()

print("Total Successfully Processed:", processed)

# ----------------------------------
# EXPORT AUDIT FILE
# ----------------------------------

timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

output_file = f"E:\\Download\\CS_TRANSFER_AUDIT_{timestamp}.csv"
output_path = os.path.join( output_file)

df.to_csv(output_path, index=False)

print("Audit File Generated:", output_path)