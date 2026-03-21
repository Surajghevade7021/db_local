import pandas as pd
from datetime import date
from dateutil.relativedelta import relativedelta
import psycopg2
from psycopg2.extras import RealDictCursor
from config import *

conn=psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
rm_list=[1495, 2279, 2278, 470, 2277, 433, 432, 2686, 2275, 2528, 122, 2274, 2273, 2146, 444, 2280]
DF  = pd.DataFrame()

start = date(2020, 12, 1)
end   = date(2025, 12, 31)
# print()
current = start.replace(day=1)
# print(db_credentials)
i=1
while current <= end:
    month_start = current
    month_end = (current + relativedelta(months=1)) - relativedelta(days=1)

    print(i)
    color_fetch_query = f"""
            WITH base_leads AS (
    SELECT l.lead_id
    FROM onboarding o
    JOIN lead l ON o.lead_id = l.lead_id
    WHERE o.subscription_start_date::date BETWEEN '{month_start}' and '{month_end}'
      AND o.sub_product_id IN (1,2,3)
      AND l.substatus_id IN (29,31)
      AND product_id = 1
),
latest_feedback AS (
    SELECT *
    FROM (
        SELECT
            fr.*,
            ROW_NUMBER() OVER (
                PARTITION BY fr.lead_id
                ORDER BY fr.feedback_response_id DESC
            ) AS rn
        FROM feedback_response fr
        WHERE fr.lead_id IN (SELECT lead_id FROM base_leads)
          AND fr.color IS NOT NULL
    ) t
    WHERE rn = 1
),
latest_cc AS (
    SELECT *
    FROM (
        SELECT
            cc.*,
            ROW_NUMBER() OVER (
                PARTITION BY cc.lead_id
                ORDER BY cc.feedback_response_id DESC
            ) AS rn
        FROM feedback_response cc
        WHERE cc.lead_id IN (SELECT lead_id FROM base_leads)
    ) t
    WHERE rn = 1
)select
	coalesce(cc.lead_id,fr.lead_id) lead_id,
	coalesce(fr.color, cc.color, 'ORANGE') as color,
	c.full_name as "Customer Name",
	c.email_address as "Customer Email",
	c.mobile_number as "Customer Mobile",
	cc.onboarding_id,
	cc.lead_id,
	cc.contact_id,
	-- fr.color,
	cc.assigned_to as "previous assignee",
	mu.full_name as "previous assignee Name",
	ms.name as "Subproduct",
	o.subscription_start_date as "Subscription start date",
	o.created_at as "Onboarding date",
	cc.created_at
from
	latest_cc cc
LEFT JOIN latest_feedback fr ON cc.lead_id = fr.lead_id
LEFT JOIN contact c ON cc.contact_id = c.contact_id
LEFT JOIN mst_user mu ON mu.user_id = cc.assigned_to
JOIN onboarding o ON o.onboarding_id = cc.onboarding_id
JOIN mst_subproduct ms ON ms.sub_product_id = o.sub_product_id
    """

    cur.execute(color_fetch_query)
    contact_data = cur.fetchall()
    df2=pd.DataFrame(contact_data)
    if len(df2)>0:
        df2['color'].fillna('ORANGE', axis=0,inplace=True)
        print(df2.shape[0])
        print(df2.head(5))
        df3 = (
            df2[df2["previous assignee"].isin(rm_list)]
            .sort_values("created_at", ascending=False)
            .drop_duplicates(subset=["color"], keep="first")
        )
        df3["new_assigned_to"] = df3["previous assignee"]
        # print(df3.head())
        df_remaining = df2.merge(
            df3[["lead_id", "onboarding_id"]],
            on=["lead_id", "onboarding_id"],
            how="left",
            indicator=True
        ).query('_merge == "left_only"').drop(columns="_merge")

        new_assigned_rows = []

        colors = df_remaining["color"].unique()
        # print(df_remaining.groupby('color').size())
        for color in colors:
            color_leads = df_remaining[df_remaining["color"] == color].sort_values("created_at")
            
            for idx, (_, row) in enumerate(color_leads.iterrows()):
                rm = rm_list[idx % len(rm_list)]
                row["new_assigned_to"] = rm
                new_assigned_rows.append(row)

        df_remaining_assigned = pd.DataFrame(new_assigned_rows)
        final_df = pd.concat([df3, df_remaining_assigned], ignore_index=True)
        
        

        final_df = final_df.sort_values(["color", "created_at"], ascending=[True, False])
        DF = pd.concat([DF, final_df], ignore_index=True, axis=0)
    
    current = current + relativedelta(months=1)
    print(current)
    i=i+1
user_fetch_query="""select user_id,mu.full_name  from mst_user mu where mu.user_id in (1495, 2279, 2278, 470, 2277, 433, 432, 2686, 2275, 2528, 122, 2274, 2273, 2146, 444, 2280)"""
cur.execute(user_fetch_query)
user_data = cur.fetchall()
user_data=pd.DataFrame(user_data)
DF=DF.merge(user_data,left_on='new_assigned_to',right_on='user_id',how='left' )
DF.drop(['user_id','created_at'],axis=1,inplace=True)
# print(user_data)
DF.to_csv(r"E:\Download\customer_service_task_1.csv")
