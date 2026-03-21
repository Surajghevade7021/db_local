import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
from config import db_credentials
import datetime, os


RUN_MODE = input("Please enter run mode (DRY_RUN / EXECUTE): ").strip().upper()

if RUN_MODE not in ["DRY_RUN", "EXECUTE"]:
    print("Invalid run mode. Please enter DRY_RUN or EXECUTE.")
    exit()

SYSTEM_USER_ID = 1
COMPANY_ID = 1
BATCH_SIZE = 100

file_path = input("Please enter CSV file full path: ").strip()
# file_path = r"C:\Users\suraj.ghevade_equent\Downloads\Feedback mapping changed for Nerve Cell and CS.csv"
print("Reading File:", file_path)

df = pd.read_csv(file_path, encoding="latin-1")

print("======================================")
print("RUN MODE :", RUN_MODE)
print("FILE :", file_path)
print("======================================")

if RUN_MODE == "DRY_RUN":
    print("DRY RUN MODE - No database updates will happen")
else:
    print("EXECUTION MODE - Database WILL be updated")

    confirm = input("Type YES to continue execution: ")
    if confirm != "YES":
        print("Execution cancelled")
        exit()

df["PROCESS_STATUS"] = "PENDING"
df["REMARKS"] = ""
df["NEW_RM_ID"] = None
df["LEAD_ID"] = None

for col in ["New RM","OLD RM","Revised Email id","Final Product"]:
    df[col] = df[col].astype(str).str.strip().str.lower()

print("Total rows:", len(df))

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)

products = df["Final Product"].dropna().unique().tolist()

cur.execute("""
SELECT product_id,
       sub_product_id,
       LOWER(TRIM(name)) AS name
FROM mst_subproduct
WHERE LOWER(TRIM(name)) = ANY(%s)
AND is_active = TRUE
""", (products,))

product_df = pd.DataFrame(cur.fetchall())

product_map = {
    row["name"]: (row["product_id"], row["sub_product_id"])
    for _, row in product_df.iterrows()
}

df["product_tuple"] = df["Final Product"].map(product_map)
df["product_id"] = df["product_tuple"].apply(lambda x: x[0] if pd.notna(x) else None)

mask = (df["product_id"].isna()) & (df["PROCESS_STATUS"]=="PENDING")
df.loc[mask,"PROCESS_STATUS"]="FAILED"
df.loc[mask,"REMARKS"]="PRODUCT NOT FOUND"

rm_names = list(set(df["New RM"].tolist() + df["OLD RM"].tolist()))

cur.execute("""
SELECT user_id, lower(full_name) AS rm_name
FROM mst_user
WHERE is_active
AND lower(full_name) = ANY(%s)
""",(rm_names,))

rm_df = pd.DataFrame(cur.fetchall())

df = df.merge(
    rm_df.rename(columns={"user_id":"new_owner_id","rm_name":"New RM"}),
    on="New RM",
    how="left"
)

df = df.merge(
    rm_df.rename(columns={"user_id":"old_owner_id","rm_name":"OLD RM"}),
    on="OLD RM",
    how="left"
)

mask = (df["new_owner_id"].isna()) & (df["PROCESS_STATUS"]=="PENDING")
df.loc[mask,"PROCESS_STATUS"]="FAILED"
df.loc[mask,"REMARKS"]="NEW RM NOT FOUND"

emails = df["Revised Email id"].unique().tolist()

cur.execute("""
SELECT contact_id, lower(email_address) AS email
FROM contact
WHERE lower(email_address) = ANY(%s)
""",(emails,))

contact_df = pd.DataFrame(cur.fetchall())

df = df.merge(
    contact_df.rename(columns={"email":"Revised Email id"}),
    on="Revised Email id",
    how="left"
)

mask = (df["contact_id"].isna()) & (df["PROCESS_STATUS"]=="PENDING")
df.loc[mask,"PROCESS_STATUS"]="FAILED"
df.loc[mask,"REMARKS"]="CONTACT NOT FOUND"

contact_ids = df["contact_id"].dropna().astype(int).tolist()

cur.execute("""
SELECT lead_id,contact_id
FROM lead
WHERE substatus_id=29 AND status_id=6
AND contact_id = ANY(%s)
""",(contact_ids,))

lead_df = pd.DataFrame(cur.fetchall())

df = df.merge(lead_df,on="contact_id",how="left")

mask = (df["lead_id"].isna()) & (df["PROCESS_STATUS"]=="PENDING")
df.loc[mask,"PROCESS_STATUS"]="FAILED"
df.loc[mask,"REMARKS"]="QUALIFIED LEAD NOT FOUND"
print(df.head())

processed=0

try:
    for row in df.itertuples(index=True):

        if row.PROCESS_STATUS!="PENDING":
            continue

        try:
            contact_id=int(row.contact_id)
            lead_id=int(row.lead_id)
            new_rm_id=int(row.new_owner_id)
            old_rm_id=int(row.old_owner_id) if pd.notna(row.old_owner_id) else None

            mapping=None


            if old_rm_id:

                cur.execute("""
                SELECT mapping_id
                FROM contact_mapping
                WHERE contact_id=%s
                AND rm_id=%s
                AND type='Customer Service'
                AND end_date IS NULL
                ORDER BY mapping_id DESC
                LIMIT 1
                """,(contact_id,old_rm_id))

                mapping=cur.fetchone()

            if mapping and RUN_MODE=="EXECUTE":

                cur.execute("""
                UPDATE contact_mapping
                SET end_date=NOW(),
                    is_transferred=TRUE,
                    updated_at=NOW(),
                    updated_by=%s
                WHERE mapping_id=%s
                """,(SYSTEM_USER_ID,mapping["mapping_id"]))

            if RUN_MODE=="EXECUTE":

                cur.execute("""
                INSERT INTO contact_mapping
                (contact_id,lead_id,rm_id,type,from_date,
                 company_id,created_at,created_by,updated_at,updated_by)
                VALUES (%s,%s,%s,'Customer Service',current_date,
                        %s,NOW(),%s,NOW(),%s)
                RETURNING mapping_id
                """,(contact_id,lead_id,new_rm_id,
                     COMPANY_ID,SYSTEM_USER_ID,SYSTEM_USER_ID))


            if RUN_MODE=="EXECUTE":

                cur.execute("""
                UPDATE feedback_response
                SET assigned_to=%s,
                    updated_at=NOW()
                WHERE feedback_response_id=(
                    SELECT feedback_response_id
                    FROM feedback_response
                    WHERE contact_id=%s
                    ORDER BY feedback_response_id DESC
                    LIMIT 1
                )
                """,(new_rm_id,contact_id))

            if RUN_MODE=="EXECUTE":

                cur.execute("""
                UPDATE follow_up
                SET is_completed=TRUE,
                    completed_on=NOW(),
                    updated_at=NOW()
                WHERE follow_up_id=(
                    SELECT follow_up_id
                    FROM follow_up
                    WHERE contact_id=%s
                    ORDER BY follow_up_id DESC
                    LIMIT 1
                )
                """,(contact_id,))

            if RUN_MODE=="EXECUTE":
             
                cur.execute(
                    """
                    INSERT INTO follow_up
                    (company_id, lead_id, onboarding_id, contact_id, rm_id,
                     customer_id, activity_type_id, status_id, substatus_id,
                     follow_up, is_completed, created_at, created_by,
                     updated_at, updated_by, reference_id)
                    SELECT
                        company_id,
                        lead_id,
                        onboarding_id,
                        contact_id,
                        %s,
                        customer_id,
                        6,
                        status_id,
                        substatus_id,
                        NOW(),
                        FALSE,
                        NOW(),
                        %s,
                        NOW(),
                        %s,
                        reference_id
                    FROM follow_up
                    WHERE contact_id = %s
                    ORDER BY follow_up_id DESC
                    LIMIT 1
                    """,
                    (new_rm_id, SYSTEM_USER_ID, SYSTEM_USER_ID, contact_id)
                )

            df.at[row.Index,"PROCESS_STATUS"]="SUCCESS"
            df.at[row.Index,"REMARKS"]="TRANSFERRED"
            df.at[row.Index,"NEW_RM_ID"]=new_rm_id
            df.at[row.Index,"LEAD_ID"]=lead_id

            processed+=1

            if processed % BATCH_SIZE == 0:

                if RUN_MODE == "EXECUTE":
                    conn.commit()
                    print("Committed:", processed)
                else:
                    conn.rollback()

        except Exception as row_error:
            conn.rollback()
            df.at[row.Index,"PROCESS_STATUS"]="FAILED"
            df.at[row.Index,"REMARKS"]=str(row_error)

    if RUN_MODE == "EXECUTE":
        conn.commit()
    else:
        conn.rollback()

except Exception as fatal:
    conn.rollback()
    print("Fatal Error:",fatal)

finally:
    cur.close()
    conn.close()

timestamp=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
audit_path = os.path.dirname(file_path)
output = os.path.join(
    audit_path,
    f"CS_TRANSFER_AUDIT_{RUN_MODE}_{timestamp}.csv"
)
df.to_csv(output,index=False)

print("SUCCESS:",processed)
print("FAILED:",len(df)-processed)
print("Audit File:",output)