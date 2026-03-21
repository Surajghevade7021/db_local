import sys
import os


current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, "..", ".."))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

import psycopg2
from psycopg2.extras import RealDictCursor
from config import db_credentials
from datetime import datetime
import csv
import logging

CSV_FILE = input("Enter CSV file path: ").strip()
COMPANY_ID = 1

# ── Logging setup ────────────────────────────────────────────────
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
audit_dir = r'E:\\EcSops\\logs'
os.makedirs(audit_dir, exist_ok=True)
log_filename = f"transfer_log_{timestamp}.log"
log_path = os.path.join(audit_dir, log_filename)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_path),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

logger.info(f"Start --> {datetime.now()}")
SYSTEM_USER_ID = 1

# ── Read CSV ─────────────────────────────────────────────────────
with open(CSV_FILE, newline='', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    rows = [r for r in reader]

logger.info(f"Total rows in CSV: {len(rows)}")

conn = psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=RealDictCursor)

# ── Session ID ───────────────────────────────────────────────────
cur.execute("SELECT MAX(session_id) FROM contact_transfer_backup")
session_id = str((cur.fetchone()['max'] or 0) + 1)

# ── Audit file setup ─────────────────────────────────────────────
audit_filename = f"audit_{timestamp}.csv"
audit_path = os.path.join(audit_dir, audit_filename)

AUDIT_COLS = [
    "full_name", "transfer_to_email",
    "lead_id", "contact_id",
    "old_rm_id", "new_rm_id",
    "status_id", "substatus_id",
    "new_mapping_id", "session_id",
    "remarks", "transfer_status",
]

audit_file = open(audit_path, "w", newline='', encoding='utf-8')
audit_writer = csv.DictWriter(audit_file, fieldnames=AUDIT_COLS)
audit_writer.writeheader()


def write_audit(row, lead_info, resolved, remarks, status):
    audit_writer.writerow({
        "full_name": row.get("full_name", "").strip(),
        "transfer_to_email": row.get("Transfer to Email id", "").strip(),
        "lead_id": lead_info.get("lead_id", ""),
        "contact_id": lead_info.get("contact_id", ""),
        "old_rm_id": resolved.get("old_rm_id", ""),
        "new_rm_id": resolved.get("new_rm_id", ""),
        "status_id": lead_info.get("status_id", ""),
        "substatus_id": lead_info.get("substatus_id", ""),
        "new_mapping_id": lead_info.get("new_mapping_id", ""),
        "session_id": session_id,
        "remarks": " | ".join(remarks) if remarks else "OK",
        "transfer_status": status,
    })
    audit_file.flush()


# ── Helpers ─────────────────────────────────────────────────────
def get_user_id(full_name):
    cur.execute(
        "SELECT user_id FROM mst_user WHERE   lower(full_name) = lower(%s)  order by user_id asc LIMIT 1 offset 2",
        (full_name.strip(),)
    )
    row = cur.fetchone()
    return row['user_id'] if row else None


def get_user_id_by_email(email):
    cur.execute(
        "SELECT user_id FROM mst_user WHERE email_address = %s LIMIT 1",
        (email.strip(),)
    )
    row = cur.fetchone()
    return row['user_id'] if row else None


def get_leads_for_rm(rm_id):
    cur.execute("""
        SELECT l.lead_id,
               l.contact_id,
               l.status_id,
               l.substatus_id,
               l.rm_id
        FROM lead l
        WHERE l.is_active = TRUE
          AND l.rm_id = %s
          AND product_id in (1,2)
          AND NOT (23 = ANY(l.sub_product_ids))
          AND l.status_id < 5
        ORDER BY l.lead_id
       
    """, (rm_id, ))
    return cur.fetchall()


# ── Validate all rows first ─────────────────────────────────────
logger.info("\nValidating rows...")

valid_transfers = []
skipped = 0
old_rm_leads_cache = {}

for i, row in enumerate(rows, start=2):

    old_owner_name = row.get('full_name', '').strip()
    new_owner_email = row.get('Transfer to Email id', '').strip()

    errors = []
    resolved = {}

    old_rm_id = get_user_id(old_owner_name)
    if old_rm_id:
        resolved['old_rm_id'] = old_rm_id
    else:
        errors.append(f"old_rm_not_found: '{old_owner_name}'")

    new_rm_id = get_user_id_by_email(new_owner_email) if new_owner_email else None
    if new_rm_id:
        resolved['new_rm_id'] = new_rm_id
    else:
        errors.append(f"new_rm_not_found_by_email: '{new_owner_email}'")

    lead_count_raw = row.get('lead Count', '').strip()

    try:
        lead_limit = int(lead_count_raw)
        if lead_limit <= 0:
            raise ValueError
    except ValueError:
        errors.append(f"invalid_lead_count: '{lead_count_raw}'")
        lead_limit = None

    leads = []

    if not errors:
        if old_rm_id not in old_rm_leads_cache:
            old_rm_leads_cache[old_rm_id] = get_leads_for_rm(old_rm_id)
            
        available_leads = old_rm_leads_cache[old_rm_id]

        if not available_leads:
            errors.append(f"no_active_leads_found_or_exhausted for rm_id={old_rm_id}")
        else:
            leads = available_leads[:lead_limit]
            old_rm_leads_cache[old_rm_id] = available_leads[lead_limit:]

    if errors:
        skipped += 1
        logger.info(f"  [SKIP] Row {i} ({old_owner_name}): {' | '.join(errors)}")
        write_audit(row, {}, resolved, errors, "failed")

    else:
        valid_transfers.append({
            'csv_row': i,
            'raw_row': row,
            'old_owner_name': old_owner_name,
            'old_rm_id': old_rm_id,
            'new_rm_id': new_rm_id,
            'leads': leads,
            'resolved': resolved
        })

        logger.info(f"  [OK] Row {i} ({old_owner_name}) -> {new_owner_email} | Leads found: {len(leads)}")


total_leads = sum(len(t['leads']) for t in valid_transfers)

logger.info(f"\nValid CSV rows : {len(valid_transfers)}")
logger.info(f"Skipped rows   : {skipped}")
logger.info(f"Total leads    : {total_leads}")
logger.info(f"Audit file     : {audit_path}")

if not valid_transfers:
    logger.info("Nothing to process. Exiting.")
    audit_file.close()
    cur.close()
    conn.close()
    sys.exit(0)

confirm = input("\nType YES to continue execution: ")

if confirm != "YES":
    logger.info("Execution cancelled.")

    for t in valid_transfers:
        for lead in t['leads']:
            write_audit(t['raw_row'], lead, t['resolved'], ["execution_cancelled"], "failed")

    audit_file.close()
    cur.close()
    conn.close()
    sys.exit(0)


logger.info("\nProcessing...")

total_count = 0

for t in valid_transfers:

    old_rm_id = t['old_rm_id']
    new_rm_id = t['new_rm_id']
    resolved = t['resolved']

    logger.info(f"\n[{t['old_owner_name']}] -> new_rm_id={new_rm_id} | {len(t['leads'])} leads")

    for lead in t['leads']:

        lead_id = lead['lead_id']
        contact_id = lead['contact_id']
        status_id = lead['status_id']
        substatus_id = lead['substatus_id']

        lead_info = {
            'lead_id': lead_id,
            'contact_id': contact_id,
            'status_id': status_id,
            'substatus_id': substatus_id
        }

        try:

            # close old mapping
            cur.execute("""
                SELECT mapping_id
                FROM contact_mapping
                WHERE contact_id = %s
                  AND rm_id = %s
                  AND type = 'Sales'
                  AND end_date IS NULL
                ORDER BY mapping_id DESC
                LIMIT 1
            """, (contact_id, old_rm_id))

            mapping = cur.fetchone()

            if mapping:
                cur.execute("""
                    UPDATE contact_mapping
                    SET end_date = NOW(),
                        is_transferred = TRUE,
                        updated_at = NOW(),
                        updated_by = %s
                    WHERE mapping_id = %s
                """, (SYSTEM_USER_ID, mapping['mapping_id']))

            # check if a new mapping already exists for this contact with the new RM
            cur.execute("""
                SELECT mapping_id
                FROM contact_mapping
                WHERE contact_id = %s
                  AND rm_id = %s
                  AND type = 'Sales'
                  AND end_date IS NULL
                ORDER BY mapping_id DESC
                LIMIT 1
            """, (contact_id, new_rm_id))
            
            existing_new_mapping = cur.fetchone()

            if existing_new_mapping:
                new_mapping_id = existing_new_mapping['mapping_id']
            else:

                cur.execute("""
                    INSERT INTO contact_mapping
                        (contact_id, lead_id, rm_id, type, from_date,
                         company_id, created_at, created_by, updated_at, updated_by)
                    VALUES (%s, %s, %s, 'Sales', NOW(), %s, NOW(), %s, NOW(), %s)
                    RETURNING mapping_id
                """, (contact_id, lead_id, new_rm_id, COMPANY_ID, SYSTEM_USER_ID, SYSTEM_USER_ID))
                new_mapping_id = cur.fetchone()['mapping_id']
                
            lead_info['new_mapping_id'] = new_mapping_id


            cur.execute("""
                UPDATE lead
                SET rm_id = %s
                WHERE lead_id = %s
            """, (new_rm_id, lead_id))


            cur.execute("""
                INSERT INTO contact_transfer_backup
                    (lead_id, rm_id, old_rm_id, status_id, substatus_id,
                     mapping_id, created_at, session_id)
                VALUES (%s, %s, %s, %s, %s, %s, NOW(), %s)
            """, (lead_id, new_rm_id, old_rm_id, status_id, substatus_id, new_mapping_id, session_id))

            conn.commit()

            total_count += 1
            write_audit(t['raw_row'], lead_info, resolved, [], "success")

            logger.info(f"   [{total_count}] Lead {lead_id} transferred")

        except Exception as e:

            conn.rollback()

            err = f"db_error: {str(e)}"
            logger.error(f"   [ERROR] lead_id={lead_id}: {err}")

            write_audit(t['raw_row'], lead_info, resolved, [err], "failed")


# ── Cleanup ───────────────────────────────────────────────────
audit_file.close()
cur.close()
conn.close()

logger.info("\n" + "=" * 55)
logger.info(f"Transferred : {total_count}")
logger.info(f"Skipped rows: {skipped}")
logger.info(f"Audit file  : {audit_path}")
logger.info(f"End --> {datetime.now()}")