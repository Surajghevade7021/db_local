import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
from config import db_credentials, DB_PORT
import sys
import ast
import os
import datetime

# -------------------- READ INPUT --------------------
file_path = sys.argv[1]

rm_list = []
if len(sys.argv) > 2:
    try:
        rm_list = ast.literal_eval(sys.argv[2])
    except:
        rm_list = []

print("RM List from CMD:", rm_list)
print("File Path:", file_path)

# -------------------- LOAD AND READ CSV --------------------
df = pd.read_csv(file_path, encoding="latin-1")
# df=df[:10]
df.columns = (
    df.columns
    .str.strip()
    .str.lower()
    .str.replace(r"\s+", " ", regex=True)
)
df["PROCESS_STATUS"] = "PENDING"
df["REMARKS"] = ""
print("Total rows in file:", len(df), "\n")

required_cols = {
    "lead number","emailasperleadsquared","product","client name",
    "contact no.","cust id","subscription date","original expiry date",
    "final expiry date","account status","allocated to"
}

missing_cols = required_cols - set(df.columns.str.strip())
if missing_cols:
    raise ValueError(f"Missing required columns: {missing_cols}")

print("All required columns exist")

# -------------------- DB ENV --------------------
if int(DB_PORT) == 5444:
    print("Database is UAT")
elif int(DB_PORT) == 5445:
    print("Database is Production")
else:
    raise ValueError(f"Unknown Database port: {DB_PORT}")

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)

# -------------------- CLEAN LEAD NUMBERS --------------------
df["lead number"] = df["lead number"].astype(str).str.strip()
df = df[df["lead number"].str.fullmatch(r"\d+")]

if df.empty:
    raise ValueError("No valid numeric Lead Numbers found")

df["lead_number"] = df["lead number"].astype(int)

# -------------------- EMAIL LIST --------------------
df["emailasperleadsquared"] = df["emailasperleadsquared"].astype(str).str.strip().str.lower()
email_add = df["emailasperleadsquared"].unique().tolist()
Product_names = df["product"].astype(str).str.strip().str.lower().unique().tolist()


product_fetch_query = """
SELECT product_id,
       sub_product_id,
       LOWER(TRIM(name)) AS name
FROM mst_subproduct
WHERE LOWER(TRIM(name)) = ANY(%s)
AND is_active = TRUE
"""
cur.execute(product_fetch_query, (Product_names,))
product_data = cur.fetchall()

product_df = pd.DataFrame(product_data)

if product_df.empty:
    raise ValueError("No products matched in mst_sub_product table")

print("Matched Products in DB:\n", product_df)

# -------------------- PRODUCT MAP --------------------
# PRODUCT_MAP = {
#     "5*5 Strategy": 1,
#     "MisPriced": 3,
#     "5*5+MisPriced": 2,
#     "5*5+Mispriced": 2,
#     "Dhanwaan + MisPriced":8,
#     "Mispriced":3,
#     "Vision-2025 Portfolio":20
# }

df["product"] = df["product"].astype(str).str.strip().str.lower().astype(str).str.strip()

product_map = {
    row["name"]: (row["product_id"], row["sub_product_id"])
    for _, row in product_df.iterrows()
}
df["product_tuple"] = df["product"].map(product_map)
df["product_id"] = df["product_tuple"].apply(lambda x: x[0] if pd.notna(x) else None)
df["sub_product_id"] = df["product_tuple"].apply(lambda x: x[1] if pd.notna(x) else None)

unmapped_products = df[df["product_id"].isna()]["product"].unique()


mask = df["product_id"].isna()
df.loc[mask, "PROCESS_STATUS"] = "FAILED"
df.loc[mask, "REMARKS"] = "PRODUCT NOT FOUND"


# if len(unmapped_products) > 0:
#     print("Unmapped products in file:", unmapped_products)
#     raise ValueError("Some products not found in mst_sub_product")
# exit()
# df["product_id"] = df["Product"].map(PRODUCT_MAP)

# if df["product_id"].isna().any():
#     print("Unmapped products:", df[df["product_id"].isna()]["Product"].unique())
#     raise ValueError("Unmapped product found in file")

# -------------------- FETCH CONTACT --------------------
contact_fetch_query = """
SELECT contact_id, lower(email_address) as email_address
FROM contact
WHERE email_address = ANY(%s)
"""
cur.execute(contact_fetch_query, (email_add,))
contact_data = cur.fetchall()

df2 = pd.DataFrame(contact_data)

if not df2.empty:
    df2.columns = ['contact_id','email_address']
    df2['contact_id'] = df2['contact_id'].astype(int)
else:
    df2 = pd.DataFrame(columns=['contact_id','email_address'])
# if df2.empty:
#     raise ValueError("No matching contacts found in DB")
df = df.merge(df2, right_on="email_address", left_on='emailasperleadsquared', how="left")
# print(df.head())
email_missing_mask = df["contact_id"].isna()
df.loc[email_missing_mask, "PROCESS_STATUS"] = "FAILED"
df.loc[email_missing_mask, "REMARKS"] = "EMAIL NOT FOUND"


# df2.columns = ['contact_id','email_address']
df2['contact_id'] = df2['contact_id'].astype(int)

# df = df.merge(df2, right_on="email_address",left_on='EmailasperLeadsquared', how="left")
print("Matched contacts:", len(df))

use_allocated_to = False

if len(rm_list) == 0:
    print("RM list not provided → Using Allocated to EMAIL mapping")

    # clean Allocated to email
    df["allocated to"] = df["allocated to"].astype(str).str.strip().str.lower()

    rm_emails = df["allocated to"].dropna().unique().tolist()
    # rm_emails = tuple(e.lower() for e in rm_emails)
    print("Unique RM emails from file:", rm_emails)

    rm_fetch_query = """
    SELECT user_id, lower(email_address) as email_address
    FROM mst_user
    WHERE is_active
      AND lower(email_address) = ANY(%s)
    """

    cur.execute(rm_fetch_query, (rm_emails,))
    rm_data = cur.fetchall()

    if not rm_data:
        print(rm_data)
        raise ValueError("No RM emails matched in mst_user table")
    

    rm_df = pd.DataFrame(rm_data)

    # create email -> user_id mapping
    rm_map = dict(zip(rm_df["email_address"], rm_df["user_id"]))
    print("RM Email Mapping:", rm_map)

    # map to dataframe
    df["rm_id"] = df["allocated to"].map(rm_map)

    # check unmatched
    unmatched = df[df["rm_id"].isna()]["allocated to"].unique()
    rm_missing_mask = df["rm_id"].isna()
    df.loc[rm_missing_mask, "PROCESS_STATUS"] = "FAILED"
    df.loc[rm_missing_mask, "REMARKS"] = "RM NOT FOUND"

    # if len(unmatched) > 0:
    #     print("Unmatched RM emails:", unmatched)
    #     raise ValueError("Some RM emails not found in mst_user table")

    use_allocated_to = True

valid_df = df[df["PROCESS_STATUS"] == "PENDING"].copy()
print("Valid records for processing:", len(valid_df))

# ============================================================
# INSERT LEADS
# ============================================================

print(f"Processing {len(df)} records...")
df["lead_id"] = None
df["follow_up_id"]=None
df["mapping_id"]=None
# exit()
try:
    for i, row in enumerate(valid_df.itertuples(index=True)):
        try:
            if use_allocated_to:
                rm_id = int(row.rm_id)
            else:
                rm_id = rm_list[i % len(rm_list)]

            contact_id = int(row.contact_id)
            lead_number = int(row.lead_number)
            product_id = int(row.product_id)
            sub_product_id = int(row.sub_product_id)

            # ---------- Check existing lead ----------
            pb_lead_fetch_query = """
            SELECT lead_id
            FROM lead
            WHERE contact_id=%s
              AND lead_source_id=57
              AND status_id=1
              AND substatus_id=2
            """
            cur.execute(pb_lead_fetch_query, (contact_id,))
            validation = cur.fetchone()

            if validation:
                lead_update_query=""" update lead set is_Active=False where contact_id=%s and lead_source_id=57 and status_id=1 and substatus_id=2 """
                cur.execute(pb_lead_fetch_query, (contact_id,))
                # df.at[row.Index, "PROCESS_STATUS"] = "SKIPPED"
                # df.at[row.Index, "REMARKS"] = "LEAD ALREADY EXISTS"
                # continue

            # ---------- Insert lead ----------
            print(f"Inserting Lead for contact_id  {contact_id} → RM {rm_id}")

            lead_insert_query = """
            INSERT INTO lead
            (lead_number, company_id, contact_id, rm_id, lead_source_id,
             product_id, status_id, substatus_id, created_at, created_by,
             updated_at, updated_by, is_active, sub_product_ids)
            VALUES (%s,1,%s,%s,57,%s,1,2,NOW(),1,NOW(),1,TRUE,%s)
            RETURNING lead_id
            """

            cur.execute(lead_insert_query, (lead_number, contact_id, rm_id,product_id, [sub_product_id]))
            lead_id = cur.fetchone()["lead_id"]

            # ---------- Follow up INSERT----------
            follow_up_insert_query = """
            INSERT INTO follow_up
            (company_id, lead_id, contact_id, rm_id, status_id, substatus_id,
             follow_up, is_completed, created_at, created_by, updated_at, updated_by)
            VALUES (1,%s,%s,%s,1,2,NOW(),FALSE,NOW(),1,NOW(),1)
            RETURNING follow_up_id
            """
            cur.execute(follow_up_insert_query, (lead_id, contact_id, rm_id))
            follow_up_id = cur.fetchone()["follow_up_id"]

            # ---------- Contact mapping INSERT----------
            contact_mapping_insert_query = """
            INSERT INTO contact_mapping
            (contact_id, rm_id, type, is_transferred, from_date, company_id,
             created_at, created_by, updated_at, updated_by, lead_id)
            VALUES (%s,%s,'Sales',FALSE,CURRENT_DATE,1,NOW(),1,NOW(),1,%s)
            RETURNING mapping_id
            """
            cur.execute(contact_mapping_insert_query, (contact_id, rm_id, lead_id))
            mapping_id = cur.fetchone()["mapping_id"]


            # -------------------------Updating File ---------------------------
            df.at[row.Index, "lead_id"] = lead_id
            df.at[row.Index, "rm_id"] = rm_id
            df.at[row.Index, "follow_up_id"] = follow_up_id
            df.at[row.Index, "mapping_id"] = mapping_id
            df.at[row.Index, "PROCESS_STATUS"] = "SUCCESS"
            df.at[row.Index, "REMARKS"] = "LEAD CREATED"

            conn.commit()
        except Exception as row_error:
            
            conn.rollback()

            df.at[row.Index, "PROCESS_STATUS"] = "FAILED"
            df.at[row.Index, "REMARKS"] = str(row_error)
            print(f"Row failed for contact_id {row.contact_id}: {row_error}")

    # -------------------- COMMIT DATA --------------------

    # conn.commit()
# -------------------- CONNECTION ROLLBACK--------------------

except Exception:
    conn.rollback()
    raise
# -------------------- CURSOR CLOSE --------------------
finally:
    cur.close()
    conn.close()


print("All records inserted successfully")

# -------------------- EXPORT FILE --------------------
script_dir = os.path.dirname(os.path.abspath(__file__))
timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
output_file = f"Pullback_File_{timestamp}.csv"
output_path = os.path.join(script_dir, output_file)
df.to_csv(output_path, index=False)
print("CSV exported:", output_path)
