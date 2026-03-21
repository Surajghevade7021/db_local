import psycopg2
from config import db_credentials

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor()
cur.execute("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'refund';")
for row in cur.fetchall():
    print(f"{row[0]}: {row[1]}")
cur.close()
conn.close()
