import pandas as pd
import datetime
import psycopg2
from psycopg2.extras import RealDictCursor, Json
import sys
import os

current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, "..", ".."))
if project_root not in sys.path:
    sys.path.insert(0, project_root)
from config import db_credentials
import json
import requests

file_path = r"C:\Users\suraj.ghevade_equent\Downloads\Effective From 2nd Mar 2026_Refund Request - Refund Request.csv"
print("Processing File:", file_path)
df = pd.read_csv(file_path, encoding="latin-1")
df.columns = df.columns.str.strip()
df.columns = df.columns.str.replace("\n", " ", regex=True).str.strip()
df.columns = df.columns.str.replace("  ", " ", regex=True)
print(df.columns)
df["process_status"] = "PENDING"
df["remarks"] = ""
df["refund_id"] = None
df["api_status"] = None
print("Total rows:", len(df))
required_cols = {
    "Counselor Counsellor/RM",
    "Client Name",
    "Client Email ID",
    "Client Phone Number",
    "Lead / Contact ID",
    "Onboarding Date",
    "Refund Request Date from Client",
    "Detail Concern",
    "Ops Status",
    "Refund Category",
    "Refund Sub Category",
    "Reason",
    "Reason Sub Category",
    "Amount",
    "GST Amount",
    "Refund Amount",
    "Refund Category",
    "Bank proof",
    "Deactivation Yes/No",
    "Refunded Product",
    "Date of Request Raised to Finance (Ops)",
    "Ops Remarks",
    "Refund Date(Finance)",
    "UTR (Finance)",
    "Amount paid",
    "Finance Remarks",
    "EC Status (Refunded )",
    "Dashboard Deactivation Dated",
    "Deactivation Email to Client",
}
missing_cols = required_cols - set(df.columns)
if missing_cols:
    raise ValueError(f"Missing required columns: {missing_cols}")
df = df.rename(
    columns={
        "Counselor Counsellor/RM": "counselor",
        "Client Name": "client_name",
        "Client Email ID": "client_email",
        "Client Phone Number": "client_phone",
        "Lead / Contact ID": "contact_id",
        "Onboarding Date": "onboarding_date",
        "Refund Request Date from Client": "refund_request_date",
        "Detail Concern": "detail_concern",
        "Ops Status": "ops_status",
        "Refund Category": "refund_category",
        "Refund Sub Category": "refund_sub_category",
        "Reason": "reason",
        "Reason Sub Category": "reason_sub_category",
        "Amount": "amount",
        "GST Amount": "gst_amount",
        "Refund Amount": "refund_amount",
        "Bank proof": "bank_proof",
        "Deactivation Yes/No": "deactivation_flag",
        "Refunded Product": "refunded_product",
        "Date of Request Raised to Finance (Ops)": "finance_request_date",
        "Ops Remarks": "ops_remarks",
        "Refund Date(Finance)": "refund_date",
        "UTR (Finance)": "utr",
        "Amount paid": "amount_paid",
        "Finance Remarks": "finance_remarks",
        "EC Status (Refunded)": "ec_status",
        "Dashboard Deactivation Dated": "dashboard_deactivation_date",
        "Deactivation Email to Client": "deactivation_email_date",
    }
)
text_cols = [
    "counselor",
    "client_name",
    "client_email",
    "ops_status",
    "refund_category",
    "refund_sub_category",
    "reason",
    "reason_sub_category",
    "finance_remarks",
]
for col in text_cols:
    if col in df.columns:
        df[col] = df[col].astype(str).str.strip()
df["client_email"] = df["client_email"].str.lower()
num_cols = ["amount", "gst_amount", "refund_amount", "amount_paid"]
for col in num_cols:
    if col in df.columns:
        df[col] = df[col].astype(str).str.replace(",", "", regex=False)
        df[col] = pd.to_numeric(df[col], errors="coerce")
date_cols = [
    "onboarding_date",
    "refund_request_date",
    "finance_request_date",
    "refund_date",
    "dashboard_deactivation_date",
    "deactivation_email_date",
    "ec_status",
]
for col in date_cols:
    if col in df.columns:
        df[col] = pd.to_datetime(df[col], errors="coerce", dayfirst=True)
if "deactivation_flag" in df.columns:
    df["deactivation_flag"] = (
        df["deactivation_flag"].astype(str).str.strip().str.lower()
    )
    df["deactivation_flag"] = df["deactivation_flag"].map({"yes": True, "no": False})
conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)
contact_ids = df["contact_id"].unique().tolist()
cur.execute(
    """
SELECT 
    contact_id,
    onboarding_id,
    (created_at + interval '5 hours 30 minutes') AS created_at
FROM onboarding
WHERE 1=1 and substatus_id=29 and 
contact_id = ANY(%s)
""",
    (contact_ids,),
)
onboarding_df = pd.DataFrame(
    cur.fetchall(), columns=["contact_id", "onboarding_id", "created_at"]
)
onboarding_df["created_at"] = pd.to_datetime(
    onboarding_df["created_at"], errors="coerce"
)
df = df.merge(onboarding_df, how="left", left_on="contact_id", right_on="contact_id")
reasons_texts = (
    df["reason_sub_category"].dropna().str.strip().str.upper().unique().tolist()
)
cur.execute(
    """
SELECT 
    UPPER(TRIM(mr.code)) AS code,
    mr.reason_id
FROM mst_reason mr
WHERE UPPER(TRIM(mr.code)) = ANY(%s)
""",
    (reasons_texts,),
)
reason_df = pd.DataFrame(cur.fetchall(), columns=["code", "reason_id"])
df["reason_sub_category_clean"] = (
    df["reason_sub_category"].fillna("").str.strip().str.upper()
)
df = df.merge(
    reason_df, how="left", left_on="reason_sub_category_clean", right_on="code"
).drop(columns=["code"])
mask = df["reason_id"].isna()
df.loc[mask, "process_status"] = "FAILED"
df.loc[mask, "remarks"] = "REASON NOT FOUND"
onboarding_ids = df["onboarding_id"].dropna().unique().tolist()
cur.execute(
    """
SELECT  
string_agg(replace(payment_id::text, ',', ''), ',') as payment_ids,
lead_id,
payment_provider ,
max(payment_id) as payment_id,
onboarding_id,
contact_id,
trackrr_customer_id,
sub_product_id from payment
WHERE 1=1 and 
onboarding_id = ANY(%s)
group by onboarding_id,
contact_id,
trackrr_customer_id,
sub_product_id
""",
    (onboarding_ids,),
)
payment_df = pd.DataFrame(
    cur.fetchall(),
    columns=[
        "payment_ids",
        "lead_id",
        "payment_provider_id",
        "payment_id",
        "onboarding_id",
        "contact_id",
        "trackrr_customer_id",
        "sub_product_id",
    ],
)
df = df.merge(payment_df, how="left", on="onboarding_id")
mask = df["payment_id"].isna()
df.loc[mask, "process_status"] = "FAILED"
df.loc[mask, "remarks"] = "VALID PAYMENT NOT FOUND"
valid_df = df[df["process_status"] == "PENDING"].copy()
print("Valid rows for processing:", len(valid_df))
headers = {
    "Authorization": "Bearer YOUR_TOKEN_HERE",
    "Content-Type": "application/json",
}
tech_response = "Process By Tech Team"
for i, row in valid_df.iterrows():
    try:
        conn = psycopg2.connect(**db_credentials)
        cur = conn.cursor(cursor_factory=RealDictCursor)
        meta_info = json.dumps(
            {
                "source": "Bulk Upload",
                "approved_by": "nikita choksi",
                "uploaded_via": "tech team",
            }
        )
        cur.execute(
            """
        INSERT INTO public.refund (
    payment_id,
    onboarding_id,
    contact_id,
    trackrr_customer_id,
    lead_id,
    sub_product_id,
    "type",
    received_amount,
    amount,
    gst_amount,
    refund_amount,
    "comment",
    payment_provider_id,
    payment_method_id,
    payment_utr_number,
    refund_date,
    net_amount,
    status,
    approved_rejected_at,
    approved_rejected_by,
    approved_rejected_comment,
    processed_at,
    processed_by,
    company_id,
    created_at,
    created_by,
    updated_at,
    updated_by,
    send_refunded_email,
    refund_reason_id,
    claim_amount,
    temp_payment_ids,
    tech_response
)
VALUES (
    %s,  -- payment_id
    %s,  -- onboarding_id
    %s,  -- contact_id
    %s,  -- trackrr_customer_id
    %s,  -- lead_id
    %s,  -- sub_product_id
    257,  
    %s,  -- received_amount
    %s,  -- amount
    %s,  -- gst_amount
    %s,  -- refund_amount
    %s,  -- comment
    %s,  -- payment_provider_id
    257,  -- payment_method_id
    %s,  -- payment_utr_number
    %s,  -- refund_date
    %s,  -- net_amount
    'Pending',  -- status (e.g., 'pending')
    now(),  -- approved_rejected_at
    1,  -- approved_rejected_by (e.g., 1)
    NULL,  -- approved_rejected_comment
    now(),  -- processed_at
    1,  -- processed_by
    1,  -- company_id
    now(),  -- created_at
    1,  -- created_by
    now(),  -- updated_at
    1,  -- updated_by
    %s,  -- send_refunded_email
    %s,  -- refund_reason_id
    %s ,  -- claim_amount
    %s,  -- temp_payment_ids
    %s   -- tech_response
)
RETURNING refund_id ;
        """,
            (
                int(row["payment_id"]) if pd.notna(row["payment_id"]) else None,
                int(row["onboarding_id"]) if pd.notna(row["onboarding_id"]) else None,
                int(row["contact_id"]) if pd.notna(row["contact_id"]) else None,
                (
                    int(row["trackrr_customer_id"])
                    if pd.notna(row["trackrr_customer_id"])
                    else None
                ),
                int(row["lead_id"]) if pd.notna(row["lead_id"]) else None,
                int(row["sub_product_id"]) if pd.notna(row["sub_product_id"]) else None,
                int(row["amount_paid"]) if pd.notna(row["amount_paid"]) else 0,
                int(row["amount"]) if pd.notna(row["amount"]) else 0,
                int(row["gst_amount"]) if pd.notna(row["gst_amount"]) else 0,
                int(row["refund_amount"]) if pd.notna(row["refund_amount"]) else 0,
                row["detail_concern"],
                (
                    int(row["payment_provider_id"])
                    if pd.notna(row["payment_provider_id"])
                    else None
                ),
                row["utr"],
                row["refund_date"] if pd.notna(row["refund_date"]) else None,
                int(row["amount_paid"]) if pd.notna(row["amount_paid"]) else 0,
                row["bank_proof"],
                int(row["reason_id"]) if pd.notna(row["reason_id"]) else None,
                int(row["refund_amount"]) if pd.notna(row["refund_amount"]) else 0,
                row["payment_ids"],
                tech_response,
            ),
        )
        result = cur.fetchone()
        refund_id = result["refund_id"] if result else None
        conn.commit()
        print(f"Refund ID: {refund_id}")
        df.at[i, "refund_id"] = refund_id
        df.at[i, "process_status"] = "SUCCESS"
    except Exception as e:
        conn.rollback()
        df.at[i, "process_status"] = "FAILED"
        df.at[i, "remarks"] = str(e)
    finally:
        cur.close()
        conn.close()
timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
output_file = f"PMP_PAYMENT_AUDIT_{timestamp}.csv"
df.to_csv(output_file, index=False)
print("Audit file generated:", output_file)
