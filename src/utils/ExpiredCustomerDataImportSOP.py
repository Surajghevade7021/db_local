import argparse
import warnings
import os
from datetime import datetime, date

import pandas as pd
import psycopg2

from config import *

warnings.filterwarnings("ignore", category=UserWarning)

# Read CSV
Provided_data=pd.read_excel("E:\\Download\\Expired Client Data - 03-02-2026.xlsx")
# print(Provided_data.head())
# exit()
def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )


def build_query(start_date, end_date, product_id=None):
    date_filter = f"""
        AND l.created_at::date BETWEEN '{start_date}' AND '{end_date}'
    """

    product_filter = ""
    if product_id:
        product_filter = f"AND l.product_id = {int(product_id)}"

    query = f"""
    WITH Expired_Customer AS (
SELECT
	DISTINCT l.contact_id
FROM
	LEAD l
WHERE
	l.substatus_id IN (32, 30, 35) 
	{date_filter}
),
Active_Customer AS (
SELECT
	DISTINCT l.contact_id
FROM
	LEAD l
WHERE
	l.substatus_id IN (29)
)
, temp_Active AS (
SELECT
	*
FROM
	Expired_Customer
WHERE
	contact_id NOT IN (
	SELECT
		contact_id
	FROM
		Active_Customer) )
, 
Ranked_leads AS (
SELECT
	c.contact_id,
	l.lead_id,
	ROW_NUMBER() OVER (
            PARTITION BY c.contact_id
ORDER BY
	l.created_at DESC
        ) AS rn
FROM
	contact c
JOIN temp_Active ec ON
	ec.contact_id = c.contact_id
JOIN LEAD l ON
	l.contact_id = c.contact_id 
)
SELECT --DISTINCT ON (c.contact_id)
--ecl.*,
        c.full_name AS EC_lead_name,
        c.mobile_number AS "EC lead contact",
        c.email_address AS " EC lead Email",
        c.contact_id AS "EC Contact ID",
        l.lead_id AS "EC Lead ID",
        l.created_at::date::text AS "EC Lead Created date" ,
        c.created_at::date AS " EC Contact Created Date",
        ms.name AS " EC Status",
        ms2.name AS "EC Substatus",
        mp.name AS "EC product",
        ms3.name AS " EC Sub-product",
        mu.full_name AS " EC Counsellor Name",
        ml.name AS "EC Counsellor Location"
    FROM  contact c 
   	 JOIN Ranked_leads rl ON rl.contact_id=c.contact_id AND rn=1
    LEFT JOIN lead l ON l.lead_id = rl.lead_id
    LEFT JOIN onboarding o ON o.lead_id = l.lead_id
    LEFT JOIN mst_status ms ON ms.status_id = l.status_id
    LEFT JOIN mst_substatus ms2 ON ms2.substatus_id = l.substatus_id
    LEFT JOIN mst_product mp ON mp.product_id = l.product_id
    LEFT JOIN mst_subproduct ms3 ON ms3.sub_product_id = ANY (l.sub_product_ids)
    LEFT JOIN mst_user mu ON mu.user_id = l.rm_id
    LEFT JOIN mst_location ml ON ml.location_id = mu.location_id 
  --  WHERE {product_filter}
    """

    return query


def run_report(start_date=None, end_date=None, product_id=None, output=None):
    # Default dates: inception → today
    if not start_date:
        start_date = "1900-01-01"
    if not end_date:
        end_date = date.today().strftime("%Y-%m-%d")

    conn = get_connection()

    try:
        query = build_query(start_date, end_date, product_id)
        df = pd.read_sql(query, conn)
        df.columns = df.columns.str.strip().str.lower()
        Provided_data.columns = Provided_data.columns.str.strip().str.lower()
        # print(df.columns)
        # exit()
        df['ec lead email'] = (
            df['ec lead email']
            .astype(str)
            .str.strip()
            .str.lower()
            .replace('nan', pd.NA)
        )

        Provided_data['emailasperleadsquared'] = (
            Provided_data['emailasperleadsquared']
            .astype(str)
            .str.strip()
            .str.lower()
            .replace('nan', pd.NA)
        )

        # 3. Merge (lowercase how, no bullshit)
        df_final = Provided_data.merge(
            df,
            left_on='emailasperleadsquared',
            right_on='ec lead email',
            how='left'
        )

        if "rn" in df_final.columns:
            df_final = df_final.drop(columns=["rn"])

        script_dir = os.path.dirname(os.path.abspath(__file__))

        if output:
            df_final.to_csv(output, index=False)
            print(f"Report exported to {output}")
        else:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_file = f"expired_customers_{timestamp}.csv"
            output_path = os.path.join(script_dir, output_file)
            df_final.to_csv(output_path, index=False)
            print(f"Report exported to {output_path}")

    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Expired Customer Report")

    parser.add_argument(
        "--daterange",
        nargs=2,
        metavar=("START_DATE", "END_DATE"),
        help="Date range: YYYY-MM-DD YYYY-MM-DD"
    )

    parser.add_argument(
        "--product_id",
        type=int,
        help="Product ID (e.g. 1, 2, 3). If not provided, all products included."
    )

    parser.add_argument(
        "--output",
        help="CSV output file path (optional)"
    )

    args = parser.parse_args()

    start_date = end_date = None
    if args.daterange:
        start_date, end_date = args.daterange

    run_report(
        start_date=start_date,
        end_date=end_date,
        product_id=args.product_id,
        output=args.output
    )


if __name__ == "__main__":
    main()
