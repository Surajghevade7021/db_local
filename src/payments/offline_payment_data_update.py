import pandas as pd
import datetime
import psycopg2
from psycopg2.extras import RealDictCursor, Json
from config import db_credentials, port
import sys
import os
import json
import requests

# ----------------------------------------------------------
# FILE INPUT
# ----------------------------------------------------------
file_path = sys.argv[1]
print("Processing File:", file_path)

# ----------------------------------------------------------
# LOAD CSV
# ----------------------------------------------------------
df = pd.read_csv(file_path, encoding="latin-1")

# ---------------- COLUMN NORMALIZATION ----------------
df.columns = (
    df.columns
    .str.strip()
    .str.lower()
    .str.replace(" ", "_")
    .str.replace("-", "_")
    .str.replace(".", "")
)

print("Detected Columns:", list(df.columns))

# ----------------------------------------------------------
# AUDIT COLUMNS
# ----------------------------------------------------------
df["process_status"] = "PENDING"
df["remarks"] = ""
df["offline_payment_id"] = None
df["api_status"] = None

print("Total rows:", len(df))

# ----------------------------------------------------------
# REQUIRED COLUMNS
# ----------------------------------------------------------
required_cols = {
'sales_table_date','client_name','email_id','team_head','sales_rep',
'location','pmt_type','lead_no','payment_reference','price','tds',
'discount','gift_shares','net_price','product','status','mode',
'user_code','due_date'
}

missing_cols = required_cols - set(df.columns)
if missing_cols:
    raise ValueError(f"Missing required columns: {missing_cols}")

# ----------------------------------------------------------
# CLEANING
# ----------------------------------------------------------
df["email_id"] = df["email_id"].astype(str).str.strip().str.lower()
df["user_code"] = pd.to_numeric(df["user_code"], errors="coerce")
df["lead_no"] = pd.to_numeric(df["lead_no"], errors="coerce")

df["due_date"] = pd.to_datetime(df["due_date"], errors="coerce", dayfirst=True)
df["sales_table_date"] = pd.to_datetime(df["sales_table_date"], errors="coerce", dayfirst=True)

df["discount_percentage"] = (df["discount"] / df["price"]) * 100

# ----------------------------------------------------------
# PAYMENT MODE MAP
# ----------------------------------------------------------
payment_provider = {
    "NEFT":111,
    "Razorpay":166,
    "Razorpay-New":166
}

df["mode"] = df["mode"].astype(str).str.strip()
df["payment_provider_ids"] = df["mode"].map(payment_provider)

mask = df["payment_provider_ids"].isna()
df.loc[mask,"process_status"]="FAILED"
df.loc[mask,"remarks"]="PAYMENT MODE NOT MAPPED"

# ----------------------------------------------------------
# DB CONNECTION
# ----------------------------------------------------------
conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)

# ----------------------------------------------------------
# CONTACT FETCH
# ----------------------------------------------------------
email_ids = df["email_id"].unique().tolist()

cur.execute("""
SELECT contact_id, lower(email_address) as email_address
FROM contact
WHERE lower(email_address) = ANY(%s)
""",(email_ids,))

contact_df = pd.DataFrame(cur.fetchall(),columns=["contact_id","email_address"])

df = df.merge(contact_df, how="left", left_on="email_id", right_on="email_address")

mask = df["contact_id"].isna()
df.loc[mask,"process_status"]="FAILED"
df.loc[mask,"remarks"]="CONTACT NOT FOUND"

# ----------------------------------------------------------
# VALID PMP LEAD FETCH
# ----------------------------------------------------------
contact_ids=df["contact_id"].dropna().unique().tolist()

cur.execute("""
SELECT lead_id, contact_id
FROM lead
WHERE product_id=1
AND 4 = ANY(sub_product_ids)
AND status_id>=6
AND is_active
AND contact_id = ANY(%s)
""",(contact_ids,))

lead_df=pd.DataFrame(cur.fetchall(),columns=["lead_id","contact_id"])

df=df.merge(lead_df,how="left",on="contact_id")

mask=df["lead_id"].isna()
df.loc[mask,"process_status"]="FAILED"
df.loc[mask,"remarks"]="VALID PMP LEAD NOT FOUND"

# ----------------------------------------------------------
# INSTALLMENT MATCH
# ----------------------------------------------------------
valid_leads=df[df["process_status"]=="PENDING"].copy()

lead_ids=valid_leads["lead_id"].tolist()
due_dates=valid_leads["due_date"].dt.date.tolist()

cur.execute("""
SELECT lead_id,trackrr_customer_id,instalment_id,onboarding_id
FROM instalment
WHERE balance_amount>0
AND payment_id IS NULL
AND (lead_id,payable_on::date) IN (
    SELECT * FROM unnest(%s::int[],%s::date[])
)
""",(lead_ids,due_dates))

inst_df=pd.DataFrame(cur.fetchall(),columns=["lead_id","trackrr_customer_id","instalment_id","onboarding_id"])

df=df.merge(inst_df,how="left",on="lead_id")

mask=df["instalment_id"].isna()
df.loc[mask,"process_status"]="FAILED"
df.loc[mask,"remarks"]="INSTALLMENT NOT FOUND FOR DUE DATE"

cur.close()
conn.close()

# ----------------------------------------------------------
# PROCESS PAYMENTS ROW-BY-ROW
# ----------------------------------------------------------
valid_df=df[df["process_status"]=="PENDING"].copy()
print("Valid rows for processing:",len(valid_df))

headers={
"Authorization":"Bearer YOUR_TOKEN_HERE",
"Content-Type":"application/json"
}

for i,row in valid_df.iterrows():

    try:
        conn=psycopg2.connect(**db_credentials)
        cur=conn.cursor(cursor_factory=RealDictCursor)

        meta_info=json.dumps({
            "source":"Bulk Upload",
            "approved_by":"nikita choksi",
            "uploaded_via":"tech team"
        })

        cur.execute("""
        INSERT INTO offline_payment(
            onboarding_id,contact_id,trackrr_customer_id,lead_id,
            amount,sub_product_id,payment_method,payment_utr_number,
            payment_date,net_amount,status,company_id,
            created_by,created_at,instalment_id,
            meta_info,discount_amount,discount_percentage
        )
        VALUES(%s,%s,%s,%s,%s,4,%s,%s,%s,%s,'Pending',1,1,NOW(),%s,%s,%s,%s)
        RETURNING offline_payment_id
        """,(
            int(row["onboarding_id"]),
            int(row["contact_id"]),
            int(row["trackrr_customer_id"]) if pd.notna(row["trackrr_customer_id"]) else None,
            int(row["lead_id"]),
            int(row["price"]),
            int(row["payment_provider_ids"]),
            row["payment_reference"],
            row["sales_table_date"],
            int(row["net_price"]),
            [int(row["instalment_id"])],
            Json(meta_info),
            int(row["discount"]),
            int(row["discount_percentage"])
        ))

        offline_payment_id=cur.fetchone()["offline_payment_id"]
        df.at[i,"offline_payment_id"]=offline_payment_id

        # API APPROVAL
        url=f"https://api-backend-equeconnect.equentis.com/offline-payment/request/{offline_payment_id}"
        response=requests.patch(url,json={"status":"Approved"},headers=headers)

        df.at[i,"api_status"]=response.status_code

        if response.status_code==200:
            df.at[i,"process_status"]="SUCCESS"
            df.at[i,"remarks"]="PAYMENT CREATED & APPROVED"
            conn.commit()
        else:
            df.at[i,"process_status"]="FAILED"
            df.at[i,"remarks"]="API APPROVAL FAILED"
            conn.rollback()

    except Exception as e:
        conn.rollback()
        df.at[i,"process_status"]="FAILED"
        df.at[i,"remarks"]=str(e)

    finally:
        cur.close()
        conn.close()

# ----------------------------------------------------------
# EXPORT AUDIT
# ----------------------------------------------------------
timestamp=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
output_file=f"PMP_PAYMENT_AUDIT_{timestamp}.csv"
df.to_csv(output_file,index=False)

print("Audit file generated:",output_file)