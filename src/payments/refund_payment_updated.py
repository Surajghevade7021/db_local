import sys
import os
from datetime import datetime
import json

current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, "..", ".."))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

import pandas as pd
import psycopg2
import requests


from psycopg2.extras import RealDictCursor

from config import db_credentials


def get_file_path():
    path = input("Enter file path: ").strip()
    return path.strip('"').strip("'")


file_path = get_file_path()

print("Start ->>>", datetime.now())
print("Processing File:", file_path)

if file_path.endswith(".csv"):
    df = pd.read_csv(file_path, encoding="latin-1")
elif file_path.endswith(".xlsx"):
    df = pd.read_excel(file_path)
else:
    raise ValueError("Invalid file format")

df.columns = df.columns.str.strip()
df.columns = df.columns.str.replace("\n", " ", regex=True).str.strip()
df.columns = df.columns.str.replace("  ", " ", regex=True)
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
onboarding_df = onboarding_df.sort_values("created_at").drop_duplicates(
    "contact_id", keep="last"
)
df = df.merge(onboarding_df, how="left", on="contact_id")


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
reason_df = reason_df.drop_duplicates(subset=["code"], keep="first")
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
trackrr_customer_id,lead_id,payment_provider,
sub_product_id
""",
    (onboarding_ids,),
)


def clean_payment_ids(x):
    ids = []
    for val in pd.Series(x).dropna().astype(str):
        ids.extend([i.strip() for i in val.split(",") if i.strip()])
    return ", ".join(sorted(list(set(ids)), key=lambda y: int(y) if y.isdigit() else y))


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
payment_df = (
    payment_df.sort_values("payment_id")
    .groupby("onboarding_id", as_index=False)
    .agg(
        {
            "payment_ids": clean_payment_ids,
            "lead_id": "last",
            "payment_provider_id": "last",
            "payment_id": "max",
            "trackrr_customer_id": "last",
            "sub_product_id": "last",
        }
    )
)
onboarding_ids_with_payment = set(payment_df["onboarding_id"].tolist())
mask_no_payment = (
    ~df["onboarding_id"].isin(onboarding_ids_with_payment) | df["onboarding_id"].isna()
)
df.loc[mask_no_payment, "process_status"] = "FAILED"
df.loc[mask_no_payment, "remarks"] = "VALID PAYMENT NOT FOUND"

valid_df = df[df["process_status"] == "PENDING"].copy()
print("Valid rows for processing:", len(valid_df))

valid_df = valid_df.sort_values("refund_date", ascending=True)

csv_agg_funcs = {
    "amount": "sum",
    "gst_amount": "sum",
    "refund_amount": "sum",
    "amount_paid": "sum",
    "onboarding_id": "last",
    "detail_concern": lambda x: ", ".join(x.dropna().astype(str).str.strip().unique()),
    "utr": "last",  # from latest refund_date row
    "refund_date": "last",  # latest
    "bank_proof": "last",  # latest
    "reason_id": "first",
}
csv_agg_funcs = {k: v for k, v in csv_agg_funcs.items() if k in valid_df.columns}
grouped_df = valid_df.groupby("contact_id", as_index=False).agg(csv_agg_funcs)

grouped_df = valid_df.groupby("contact_id", as_index=False).agg(csv_agg_funcs)

# # DEBUG
# print("Raw CSV rows for contact 3717143:")
# print(valid_df[valid_df["contact_id"] == 3717143][["contact_id", "amount", "gst_amount", "refund_amount", "amount_paid", "refund_date"]])
# print("grouped_df rows:", len(grouped_df))
# print("payment_df rows:", len(payment_df))
# print("payment_df onboarding_id duplicates:")
# print(payment_df[payment_df.duplicated("onboarding_id", keep=False)][["onboarding_id","payment_id","sub_product_id"]])
# print("grouped_df amounts before payment merge:")
# print(grouped_df[["contact_id","amount","gst_amount","refund_amount","amount_paid"]])

# grouped_df = grouped_df.merge(payment_df, how="left", on="onboarding_id")

# # DEBUG after merge
# print("grouped_df rows AFTER payment merge:", len(grouped_df))
# print("grouped_df amounts AFTER payment merge:")
# print(grouped_df[["contact_id","amount","gst_amount","refund_amount","amount_paid"]])

# exit()


grouped_df = grouped_df.merge(payment_df, how="left", on="onboarding_id")


grouped_df = grouped_df.sort_values("payment_id").drop_duplicates(
    "contact_id", keep="last"
)


# agg_funcs = {
#     "amount":               "sum",
#     "gst_amount":           "sum",
#     "refund_amount":        "sum",
#     "amount_paid":          "sum",
#     "payment_id":           "max",
#     "onboarding_id":        "last",
#     "lead_id":              "last",
#     "trackrr_customer_id":  "last",
#     "sub_product_id":       "last",
#     "payment_provider_id":  "last",
#     "payment_ids":          clean_payment_ids,
#     "detail_concern":       lambda x: ", ".join(x.dropna().astype(str).str.strip().unique()),
#     "utr":                  "first",
#     "refund_date":          "first",
#     "bank_proof":           "first",
#     "reason_id":            "first",
#     "contact_id":           "first",
# }
# agg_funcs = {k: v for k, v in agg_funcs.items() if k in valid_df.columns}
# valid_df = valid_df.sort_values("payment_id", ascending=True)
# grouped_df = valid_df.groupby("contact_id", as_index=False).agg(agg_funcs)
print(f"Original valid rows : {len(valid_df)}")
print(f"After grouping       : {len(grouped_df)}  (one per contact_id)")
valid_df = grouped_df.copy()
valid_df["process_status"] = "PENDING"
valid_df["remarks"] = ""
valid_df["refund_id"] = None

# timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
# output_file = f"E:\\EcSops\\logs\\REFUND_PAYMENT_AUDIT_{timestamp}.csv"
# valid_df.to_csv(output_file, index=False)
# print("Audit file generated:", output_file)
headers = {
    "Authorization": "Bearer YOUR_TOKEN_HERE",
    "Content-Type": "application/json",
}
tech_response = json.dumps({"status": "Process By Tech Team"})
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
    %s,
    %s,
    %s,
    %s,
    %s,
    %s,
    257,  
    %s,
    %s,
    %s,
    %s,
    %s,
    %s,
    257,
    %s,
    %s,
    %s,
    'Pending',
    now(),
    1,
    NULL,
    now(),
    1,
    1,
    now(),
    1,
    now(),
    1,
    %s,
    %s,
    %s,
    %s,
    %s
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
                False,
                int(row["reason_id"]) if pd.notna(row["reason_id"]) else None,
                int(row["refund_amount"]) if pd.notna(row["refund_amount"]) else 0,
                (
                    [
                        int(x.strip())
                        for x in str(row["payment_ids"]).split(",")
                        if x.strip().isdigit()
                    ]
                    if pd.notna(row["payment_ids"]) and str(row["payment_ids"]).strip()
                    else None
                ),
                tech_response,
            ),
        )
        result = cur.fetchone()
        refund_id = result["refund_id"] if result else None
        conn.commit()
        # exit()
        print(f"Refund ID: {refund_id}")
        valid_df.at[i, "refund_id"] = refund_id
        valid_df.at[i, "process_status"] = "SUCCESS"
    except Exception as e:
        conn.rollback()
        valid_df.at[i, "process_status"] = "FAILED"
        valid_df.at[i, "remarks"] = str(e)
    finally:
        cur.close()
        conn.close()
status_mapping = valid_df.set_index("contact_id")["process_status"].to_dict()
remarks_mapping = valid_df.set_index("contact_id")["remarks"].to_dict()
refund_id_mapping = valid_df.set_index("contact_id")["refund_id"].to_dict()

mask = df["contact_id"].isin(valid_df["contact_id"])
df.loc[mask, "process_status"] = df.loc[mask, "contact_id"].map(status_mapping)
df.loc[mask, "remarks"] = df.loc[mask, "contact_id"].map(remarks_mapping)
df.loc[mask, "refund_id"] = df.loc[mask, "contact_id"].map(refund_id_mapping)

if "payment_ids" in df.columns:
    df["payment_ids"] = df["payment_ids"].astype(str).str.replace(",", " |")

timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
output_file = f"E:\\EcSops\\logs\\REFUND_PAYMENT_AUDIT_{timestamp}.csv"
df.to_csv(output_file, index=False)
print("Audit file generated:", output_file)
