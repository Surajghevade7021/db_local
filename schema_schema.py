import sys
sys.path.insert(0, r'e:\EcSops')
from config import db_credentials
import psycopg2
conn=psycopg2.connect(**db_credentials)
cur=conn.cursor()
cur.execute("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'follow_up'")
for row in cur.fetchall(): print(row)
