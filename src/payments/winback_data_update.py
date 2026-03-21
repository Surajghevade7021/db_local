import pandas as pd
import datetime
import psycopg2
from psycopg2.extras import RealDictCursor, Json
from config import db_credentials, port
import json
import requests
import numpy as np
import time


file_path = r"E:\Download\Payments update in EC.xlsx"
timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
OUTPUT_PATH=f"E:\\Download\\offline_payment{timestamp}.csv"

SYSTEM_USER_ID = 1

df = pd.read_excel(file_path, sheet_name='Data Update in EC Winback')

df = df.rename(columns={
    "Status.1": "Status_Meta_info",
    "Email-ID.1": "temp_email",
    "Tranche no.1": "Tranche no_1",
    "Tranche Due Date.1": "Tranche Due Date_1",
    "Tranche no.2": "Tranche no_2",
    "Tranche Due Date.2": "Tranche Due Date_2",
    "Tranche no.3": "Tranche no_3",
    "Tranche Due Date.3": "Tranche Due Date_3",
    "Tranche no.4": "Tranche no_4",
    "Tranche Due Date.4": "Tranche Due Date_4",
})

print("Total rows:", len(df))
required_cols = {
    'Sales Table Date','Client Name','Email-ID','Team Head','Sales Rep.',
    'Location','Pmt Type','Lead No.','Payment Reference','Price','TDS',
    'Discount','Gift Shares','Net Price','Product','Status','Mode',
    "Tranche no","Tranche Due Date","Tranche no_1","Tranche Due Date_1","Tranche no_2","Tranche Due Date_2","Tranche no_3","Tranche Due Date_3","Tranche no_4","Tranche Due Date_4"

}

missing = required_cols - set(df.columns.str.strip())
if missing:
    raise ValueError(f"Missing columns: {missing}")

df=df[list(required_cols)]

if int(port) == 5444:
    print("UAT database")
elif int(port) == 5445:
    print("Production database")
else:
    raise ValueError("Unknown database port")

date_cols = [
    "Tranche Due Date",
    "Tranche Due Date_1",
    "Tranche Due Date_2",
    "Tranche Due Date_3",
    "Tranche Due Date_4"
]

for col in date_cols:
    if col in df.columns:
        df[col] = pd.to_datetime(df[col], errors="coerce", dayfirst=True)


df["Email-ID"] = df["Email-ID"].astype(str).str.strip().str.lower()
# df["User Code"] = df["User Code"].astype(str).str.strip()
# df = df[df["User Code"].str.fullmatch(r"\d+")]

# df["User Code"] = df["User Code"].astype(int)
df["Lead No."] = pd.to_numeric(df["Lead No."], errors="coerce").astype("Int64")

df["Sales Table Date"] = pd.to_datetime(df["Sales Table Date"], errors="coerce", dayfirst=True)
df["Tranche Due Date"] = pd.to_datetime(df["Tranche Due Date"], errors="coerce", dayfirst=True) 
df["Tranche Due Date_1"] = pd.to_datetime(df["Tranche Due Date_1"], errors="coerce", dayfirst=True).dt.date
df["Tranche Due Date_2"] = pd.to_datetime(df["Tranche Due Date_2"], errors="coerce", dayfirst=True).dt.date
df["Tranche Due Date_3"] = pd.to_datetime(df["Tranche Due Date_3"], errors="coerce", dayfirst=True).dt.date
df["Tranche Due Date_4"] = pd.to_datetime(df["Tranche Due Date_4"], errors="coerce", dayfirst=True).dt.date

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
    how="left"
).drop(columns=["email"])

# print(len(df))
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

df = df.merge(lead_df, on="contact_id", how="left")

cur.execute(
    """
    SELECT lead_id, trackrr_customer_id, instalment_id,
           tranche_number, instalment_number, onboarding_id,
           payable_on::date
    FROM instalment
    WHERE --balance_amount > 0
      --AND payment_id IS NULL AND
       lead_id = ANY(%s)
    """,
    (df["lead_id"].unique().tolist(),)
)

inst_df = pd.DataFrame(cur.fetchall())
inst_df["payable_on"] = pd.to_datetime(inst_df["payable_on"]).dt.date
# print(len(inst_df))
df["due_date_only"] = df["Tranche Due Date"].dt.date
temp_df=df.copy()
df = df.merge(
    inst_df,
    left_on=["lead_id", "due_date_only"],
    right_on=["lead_id", "payable_on"],
    how="left"
)

df2 = temp_df.merge(
    inst_df,
    left_on=["lead_id", "Tranche Due Date_1"],
    right_on=["lead_id", "payable_on"],
    how="inner"
)
df3 = temp_df.merge(
    inst_df,
    left_on=["lead_id", "Tranche Due Date_2"],
    right_on=["lead_id", "payable_on"],
    how="inner"
)
df4 = temp_df.merge(
    inst_df,
    left_on=["lead_id", "Tranche Due Date_3"],
    right_on=["lead_id", "payable_on"],
    how="inner"
)
df5 = temp_df.merge(
    inst_df,
    left_on=["lead_id", "Tranche Due Date_4"],
    right_on=["lead_id", "payable_on"],
    how="inner"
)

for name, d in zip(['df2','df3','df4','df5'], [df2, df3, df4, df5]):
    print(name)
    print("Missing:", set(df.columns) - set(d.columns))
    print("Extra:", set(d.columns) - set(df.columns))
    print()


# exit()
temp_df=df.copy()
df = df[df['instalment_id'].notna()]
print("Qualified rows:", len(df))
print("Qualified rows:", len(df2))
print("Qualified rows:", len(df3))
print("Qualified rows:", len(df4))
print("Qualified rows:", len(df5))

df["offline_payment_id"] = None
df = pd.concat([df, df2, df3, df4, df5], ignore_index=True)

conditions = [
    df['instalment_id'].notna(),
    df['lead_id'].notna(),
    df['contact_id'].notna()
]

choices = [
    'Instalment Found',
    'Lead Found',
    'Contact Found'
]

df['stage'] = np.select(conditions, choices, default='No Match')
lead_instalments = (
    df[df['instalment_id'].notna()]
      .groupby(['lead_id', 'Sales Table Date'])['instalment_id']
      .apply(lambda x: {int(i) for i in x})
      .reset_index(name='instalment_ids')
)

# df_final = (
#     df.dropna(subset=['instalment_id'])
#       .drop_duplicates(subset=['lead_id',"Sales Table Date"])
#       .merge(lead_instalments, on='lead_id', how='left')
# )
df_final = (
    df.dropna(subset=['instalment_id'])
      .drop_duplicates(subset=['lead_id', 'Sales Table Date'])
      .merge(
          lead_instalments,
          on=['lead_id', 'Sales Table Date'],
          how='left'
      )
)


df_final.to_csv(OUTPUT_PATH, index=False)
df=df_final.copy()
# exit()
try:
    for i, row in df.iterrows():

        cur.execute(
            """
            INSERT INTO offline_payment (
                onboarding_id, contact_id, trackrr_customer_id, lead_id,
                amount, sub_product_id, payment_method, payment_utr_number,
                payment_date, net_amount, status, company_id,
                created_by, updated_at, instalment_id,
                meta_info, discount_amount, discount_percentage
            )
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                    'Pending',1,%s,%s,%s,%s,%s,%s)
            RETURNING offline_payment_id
            """,
            (
                int(row["onboarding_id"]),
                int(row["contact_id"]),
                int(row["trackrr_customer_id"]) if pd.notna(row["trackrr_customer_id"]) else None,
                int(row["lead_id"]),
                int(row["Price"]),
                int(row["subproduct_id"]),
                int(row["payment_method"]) if pd.notna(row["payment_method"]) else None,
                row["provider_reference_id"],
                row["Sales Table Date"],
                int(row["Net Price"]),
                SYSTEM_USER_ID,
                datetime.datetime.now(),
                # [int(row["instalment_id"])],
                list(row["instalment_ids"]),
                Json({
                    "source": "Bulk Upload",
                    "approved_by": "nikita choksi",
                    "uploaded_via": "tech team"
                }),
                int(row["Discount"]),
                int(row["Discount %"])
            )
        )
        print(row["instalment_ids"])
        offline_payment_id = cur.fetchone()["offline_payment_id"]
        df.at[i, "offline_payment_id"] = offline_payment_id

        conn.commit()
        time.sleep(0.3) 
        url = f"https://api-backend-equeconnect.equentis.com/offline-payment/request/{offline_payment_id}"
        headers = {
            "Authorization": "Bearer eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MTYwLCJpYXQiOjE3NzAxMTQ4MDMsImV4cCI6MTc3MDIwMTIwM30.CANJH3olQ84jYfffLl2tZNWmUpohYboM-f9T8odw6cRW2R3c1Qyr7eEUrbAOxYnSWTFucMi_yN52RfA7ZGWYKg",
            "Content-Type": "application/json"
        }
        requests.patch(url, json={"status": "Approved"}, headers=headers)
        # exit()
except Exception as e:
    conn.rollback()
    raise e

finally:
    cur.close()
    conn.close()

df.to_csv(OUTPUT_PATH, index=False)
print("Completed. CSV exported:", OUTPUT_PATH)
