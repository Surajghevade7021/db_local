import os
from dotenv import load_dotenv
import sys
import warnings 
warnings.filterwarnings('ignore')

current_dir=os.path.dirname(__file__)
project_root=os.path.abspath(os.path.join(current_dir))
if project_root not in sys.path:
    sys.path.insert(0,project_root)
env_path=os.path.join(project_root,".env")
load_dotenv(env_path)


# # production Credentials
DB_HOST= os.getenv('prod_host')
DB_PORT= os.getenv('prod_port')
DB_NAME= os.getenv('prod_database')
DB_USER= os.getenv('prod_user')
DB_PASSWORD= os.getenv('prod_password')


# UAT Credentials
# DB_HOST= os.getenv('UAT_host')
# DB_PORT= os.getenv('UAT_Port')
# DB_NAME= os.getenv('UAt_Database')
# DB_USER= os.getenv('UAT_user')
# DB_PASSWORD= os.getenv('UAT_Password')



db_credentials = {
    "host": DB_HOST,
    "port": DB_PORT,
    "database": DB_NAME,
    "user": DB_USER,
    "password": DB_PASSWORD  
} 
