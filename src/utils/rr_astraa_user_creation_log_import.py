import psycopg2
import re
from tqdm import tqdm
from psycopg2.extras import RealDictCursor
from config import db_credentials

TABLE_NAME = "rr_astraa_user_creation_log"
SQL_FILE = r"E:\Download\rr_astraa_user_creation_log_clean.sql"

# ---------- CONNECT ----------
conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)
print("Connected to DB")

# ---------- READ FILE ----------
with open(SQL_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# ---------- EXTRACT COLUMNS ----------
col_match = re.search(r"INSERT INTO .*?\((.*?)\)\s*VALUES", content, re.S | re.I)
columns = [c.strip().strip("`").strip("'") for c in col_match.group(1).split(",")]

col_string = ",".join(columns)
placeholder = ",".join(["%s"] * len(columns))

insert_sql = f"""
INSERT INTO {TABLE_NAME} ({col_string})
VALUES ({placeholder})
ON CONFLICT DO NOTHING
"""

# ---------- STREAM PARSER ----------
def parse_rows(sql_text):
    values_text = sql_text.split("VALUES",1)[1]
    values_text = values_text.rsplit(";",1)[0].strip()

    in_string = False
    escape = False
    paren = 0
    value = ""
    row = []

    for ch in values_text:

        if ch == "\\" and in_string:
            escape = True
            value += ch
            continue

        if ch == "'" and not escape:
            in_string = not in_string
            continue

        escape = False

        if ch == "(" and not in_string:
            paren += 1
            if paren == 1:
                row = []
                value = ""
                continue

        if ch == ")" and not in_string:
            paren -= 1
            if paren == 0:
                row.append(value.strip())
                yield row
                continue

        if ch == "," and not in_string and paren == 1:
            row.append(value.strip())
            value = ""
            continue

        value += ch


# ---------- CLEAN VALUES ----------
def clean(v):

    if v is None:
        return None

    v = v.strip()

    if v.upper() == "NULL":
        return None

    if v == "":
        return None

    # remove quotes
    if v.startswith("'") and v.endswith("'"):
        v = v[1:-1]

    # unescape
    v = v.replace("\\'", "'")
    v = v.replace('\\\\', '\\')

    return v


# ---------- INSERT ROW BY ROW ----------
inserted = 0
skipped = 0
failed = 0

fail_log = open("E:\\Download\\failed_rows.log", "w", encoding="utf-8")

print("Inserting rows one-by-one...")

for raw_row in tqdm(parse_rows(content)):

    cleaned = [clean(v) for v in raw_row]

    try:
        cur.execute(insert_sql, cleaned)
        conn.commit()

        # check if inserted or skipped (duplicate id)
        if cur.rowcount == 1:
            inserted += 1
        else:
            skipped += 1

    except Exception as e:
        conn.rollback()
        failed += 1
        fail_log.write("ROW:\n")
        fail_log.write(str(cleaned) + "\n")
        fail_log.write("ERROR:\n")
        fail_log.write(str(e) + "\n\n")

fail_log.close()
cur.close()
conn.close()

print("\n----- IMPORT REPORT -----")
print("Inserted :", inserted)
print("Skipped (duplicates):", skipped)
print("Failed :", failed)
print("Failed row details saved to failed_rows.log")
