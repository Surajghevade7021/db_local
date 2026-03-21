import psycopg2
from config import db_credentials
import sys

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor()
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name = 'payment' AND column_name LIKE '%amount%';")
print([r[0] for r in cur.fetchall()])
cur.close()
conn.close()
