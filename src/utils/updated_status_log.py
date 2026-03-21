import psycopg2
import pandas as pd
from config import db_credentials

# ---------- READ CSV ----------
data = pd.read_csv(r"C:\Users\suraj.ghevade_equent\status_log backup 202603021600.csv")

# ---------- CLEAN COLUMN NAMES ----------
data.columns = data.columns.str.strip().str.lower().str.replace(" ", "_")
print("CSV Columns Found:", data.columns.tolist())

# ---------- CONNECT ----------
conn = psycopg2.connect(**db_credentials)
cursor = conn.cursor()

# ---------- QUERY ----------
update_query = """
UPDATE status_log sl
SET
    status_id = %s,
    substatus_id = %s
WHERE
    sl.status_log_id = %s
    AND sl.created_at = %s
    AND sl.lead_id = %s;
"""

# ---------- PROCESS ----------
success = 0
not_matched = 0
failed = 0

for index, row in data.iterrows():
    try:
        status_log_id = int(row["status_log_id"])
        status_id = int(row["status_id"])
        substatus_id = int(row["substatus_id"])

        # ⭐ DATE ONLY (IMPORTANT CHANGE)
        created_at = pd.to_datetime(row["created_at"])

        lead_id = int(row["lead_id"])

        cursor.execute(update_query, (
            status_id,
            substatus_id,
            status_log_id,
            created_at,
            lead_id
        ))

        if cursor.rowcount == 0:
            not_matched += 1
            print(f"SKIPPED: {status_log_id}")
        else:
            success += 1
            print(f"UPDATED: {status_log_id}")

    except Exception as e:
        conn.rollback()
        failed += 1
        print(f"FAILED ID {row.get('status_log_id')} -> {e}")

# ---------- COMMIT ONCE ----------
conn.commit()

# ---------- REPORT ----------
print("\n=========== FINAL REPORT ===========")
print("Updated Rows  :", success)
print("Not Matched   :", not_matched)
print("Failed Rows   :", failed)

cursor.close()
conn.close()