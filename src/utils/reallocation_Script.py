import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor, execute_batch
from config import db_credentials

audit_rows = []
file_path = r"E:\Download\Winback.csv"
df = pd.read_csv(file_path, encoding="latin-1")
# print(df.shape)

df.columns = (
    df.columns
    .str.strip()
    .str.lower()
    .str.replace(r"\s+", " ", regex=True)
)

df = df.rename(columns={
    "cutomer_email": "customer_email",
    "instalment id": "instalment_id",
    "rm email": "rm_email",
    "Counsellor": "counsellor"
})

# df =df.loc[106]
# print(df)
# print(df.shape)
# exit()
required_cols = {'customer_email', 'instalment_id', 'rm_email', 'counsellor'}
missing_cols = required_cols - set(df.columns)
if missing_cols:
    raise ValueError(f"Missing required columns: {missing_cols}")

print("All required columns exist")


df["instalment_id"] = df["instalment_id"].astype(str).str.strip()
df = df[df["instalment_id"].str.fullmatch(r"\d+")]
df["instalment_id"] = df["instalment_id"].astype(int)

df["customer_email"] = df["customer_email"].astype(str).str.strip().str.lower()
df["rm_email"] = df["rm_email"].astype(str).str.strip().str.lower()
df["counsellor"] = df["counsellor"].astype(str).str.strip().str.lower()

print("Rows after instalment cleaning:", len(df))

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)

old_rm_emails = df["rm_email"].dropna().unique().tolist()

cur.execute("""
    SELECT user_id, lower(email_address) AS email_address
    FROM mst_user
    WHERE is_active
    AND lower(email_address) = ANY(%s)
""", (old_rm_emails,))

old_rm_df = pd.DataFrame(cur.fetchall())
rm_map = dict(zip(old_rm_df["email_address"], old_rm_df["user_id"]))

df["old_rm_id"] = df["rm_email"].map(rm_map)
print("Old RM not found:", df["old_rm_id"].isna().sum())

new_rm_names = df["counsellor"].dropna().unique().tolist()

cur.execute("""
    SELECT user_id, lower(full_name) AS counsellor
    FROM mst_user
    WHERE is_active
    --AND department_id = 18
    AND lower(full_name) = ANY(%s)
""", (new_rm_names,))

new_rm_df = pd.DataFrame(cur.fetchall())
new_rm_map = dict(zip(new_rm_df["counsellor"], new_rm_df["user_id"]))

df["new_rm_id"] = df["counsellor"].map(new_rm_map)
print("New RM not found:", df["new_rm_id"].isna().sum())

customer_emails = df["customer_email"].dropna().unique().tolist()

cur.execute("""
    SELECT contact_id, lower(email_address) AS email_address
    FROM contact
    WHERE lower(email_address) = ANY(%s)
""", (customer_emails,))

df_contact = pd.DataFrame(cur.fetchall())

df = df.merge(
    df_contact,
    left_on="customer_email",
    right_on='email_address',
    how="left"
)

print("Contacts not found:", df["contact_id"].isna().sum())

valid_contacts = df["contact_id"].dropna().unique().tolist()

cur.execute("""
    SELECT lead_id, contact_id
    FROM onboarding l
    WHERE 
     l.status_id >= 6 AND
      l.substatus_id = 29 AND
       4 = l.sub_product_id
      AND l.contact_id = ANY(%s)
""", (valid_contacts,))

df_lead = pd.DataFrame(cur.fetchall())

df = df.merge(
    df_lead,
    on="contact_id",
    how="left"
)

print("Leads not found:", df["lead_id"].isna().sum())

df_final = df.dropna(subset=["lead_id", "old_rm_id", "new_rm_id"])

df_final = df_final[["lead_id", "old_rm_id", "new_rm_id"]].drop_duplicates()

print("Records ready for update:", len(df_final))

print("Lead RM reassignment completed successfully.")

for row in df_final.itertuples(index=False):

    lead_id = int(row.lead_id)
    old_rm_id = int(row.old_rm_id)
    new_rm_id = int(row.new_rm_id)

    follow_up_id = None
    payment_collection_id = None
    status = ""

    try:
        # conn.autocommit = False

        cur.execute("""
            SELECT follow_up_id
            FROM follow_up
            WHERE lead_id = %s
              AND rm_id = %s
            ORDER BY follow_up_id DESC
            LIMIT 1
        """, (lead_id, old_rm_id))

        follow = cur.fetchone()

        if not follow:
            conn.rollback()
            status = "follow_up not available"
            audit_rows.append((lead_id, old_rm_id, new_rm_id, follow_up_id, payment_collection_id, status))
            continue

        follow_up_id = follow["follow_up_id"]

        cur.execute("""
            SELECT payment_collection_id
            FROM payment_collection
            WHERE status_id = 7
              AND substatus_id = 43
             -- AND department_id = 18
              AND lead_id = %s
              and assigned_to =%s
        """, (lead_id, old_rm_id))

        payment = cur.fetchone()

        if not payment:
            conn.rollback()
            status = "payment_collection not available OR rm mismatch"
            audit_rows.append((lead_id, old_rm_id, new_rm_id, follow_up_id, payment_collection_id, status))
            continue

        payment_collection_id = payment["payment_collection_id"]

        cur.execute("""
            UPDATE follow_up
            SET rm_id = %s,
                is_completed = FALSE,
                completed_on = NULL
            WHERE follow_up_id = %s
        """, (new_rm_id, follow_up_id))

        cur.execute("""
            UPDATE payment_collection
            SET assigned_to  = %s,department_id=20
            WHERE payment_collection_id = %s
              AND assigned_to = %s
        """, (new_rm_id, payment_collection_id, old_rm_id))

        # conn.commit()
        conn.rollback()
        status = "updated successfully"

    except Exception as e:
        conn.rollback()
        status = f"error: {str(e)}"

    audit_rows.append((lead_id, old_rm_id, new_rm_id, follow_up_id, payment_collection_id, status))


audit_df = pd.DataFrame(
    audit_rows,
    columns=[
        "lead_id",
        "old_rm_id",
        "new_rm_id",
        "follow_up_id",
        "payment_collection_id",
        "status"
    ]
)
df = df.merge(
    audit_df,
    on=["lead_id", "old_rm_id", "new_rm_id"],
    how="left"
)
cur.close()
conn.close()
print("Database connection closed.")
df.to_csv(r"E:\Download\lead_rm_reassignment_Winback_audit.csv", index=False)