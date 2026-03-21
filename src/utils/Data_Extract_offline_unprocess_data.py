import pandas as pd
import datetime
import psycopg2
from psycopg2.extras import RealDictCursor, Json
from config import db_credentials, port
import json
import requests

file_path = r"E:\Download\PMP Data.csv"
OUTPUT_PATH = r"E:\Download\offline_payment.csv"
SYSTEM_USER_ID = 1

df = pd.read_csv(file_path, encoding="latin-1")
df = df[df['offline_payment_id'].isna()]
print(len(df))
# exit()
print("Total rows:", len(df))

required_cols = {
    'Sales Table Date','Client Name','Email-ID','Team Head','Sales Rep.',
    'Location','Pmt Type','Lead No.','Payment Reference','Price','TDS',
    'Discount','Gift Shares','Net Price','Product','Status','Mode',
    'User Code','Due Date'
}

missing = required_cols - set(df.columns.str.strip())
if missing:
    raise ValueError(f"Missing columns: {missing}")

df = df[list(required_cols)]

if int(port) == 5444:
    print("UAT database")
elif int(port) == 5445:
    print("Production database")
else:
    raise ValueError("Unknown database port")

df["Email-ID"] = df["Email-ID"].astype(str).str.strip().str.lower()
df["User Code"] = df["User Code"].astype(str).str.strip()
df = df[df["User Code"].str.fullmatch(r"\d+")]

df["User Code"] = df["User Code"].astype(int)
df["Lead No."] = pd.to_numeric(df["Lead No."], errors="coerce").astype("Int64")

df["Sales Table Date"] = pd.to_datetime(df["Sales Table Date"], errors="coerce", dayfirst=True)
df["Due Date"] = pd.to_datetime(df["Due Date"], errors="coerce", dayfirst=True)

df["Discount %"] = (df["Discount"] / df["Price"]) * 100
df["provider_reference_id"] = df["Payment Reference"]

PRODUCT_MAP = {
    "premium membership program": 4,
    "pmp": 4
}

PAYMENT_PROVIDER = {
    "NEFT": 111,
    "Razorpay": 166,
    "Razorpay-New": 166
}

df["Product"] = df["Product"].astype(str).str.strip().str.lower()
df["subproduct_id"] = df["Product"].map(PRODUCT_MAP)

if df["subproduct_id"].isna().any():
    raise ValueError("Unmapped PMP product found")

df["payment_method"] = df["Mode"].astype(str).str.strip().map(PAYMENT_PROVIDER)

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)


cur.execute(
    """
    SELECT contact_id, lower(email_address) AS email
    FROM contact
    WHERE lower(email_address) = ANY(%s)
    """,
    (df["Email-ID"].unique().tolist(),)
)

contact_df = pd.DataFrame(cur.fetchall())
if contact_df.empty:
    raise ValueError("No contacts found")

df = df.merge(
    contact_df,
    left_on="Email-ID",
    right_on="email",
    how="inner"
).drop(columns=["email"])

cur.execute(
    """
    SELECT lead_id, contact_id
    FROM lead
    WHERE product_id = 1
      AND 4 = ANY(sub_product_ids)
      AND status_id = 6 and substatus_id=29
      AND is_active
      AND contact_id = ANY(%s)
    """,
    (df["contact_id"].unique().tolist(),)
)

lead_df = pd.DataFrame(cur.fetchall())
if lead_df.empty:
    raise ValueError("No valid PMP leads found")

df = df.merge(lead_df, on="contact_id", how="inner")
print(len(df))

cur.execute(
    """
    SELECT lead_id, trackrr_customer_id, instalment_id,
           tranche_number, instalment_number, onboarding_id  ,payment_id, 
           payable_on::date
    FROM instalment
    WHERE --balance_amount >= 0
      --AND payment_id IS Not NULL AND
       lead_id = ANY(%s)
    """,
    (df["lead_id"].unique().tolist(),)
)

inst_df = pd.DataFrame(cur.fetchall())
inst_df["payable_on"] = pd.to_datetime(inst_df["payable_on"]).dt.date

df["due_date_only"] = df["Due Date"].dt.date

df = df.merge(
    inst_df,
    left_on=["lead_id", "due_date_only"],
    right_on=["lead_id", "payable_on"],
    how="inner"
)

print("Qualified rows:", len(df))

df["offline_payment_id"] = None
df.to_csv(OUTPUT_PATH, index=False)
# exit()