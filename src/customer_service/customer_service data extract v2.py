import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
from config import *

conn=psycopg2.connect(**db_credentials)
cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

color_fetch_query = """
        
    select fr. *, row_number() over (partition by fr.onboarding_id order by feedback_response_id desc) 
    from feedback_response fr 
    inner join onboarding o on o.onboarding_id = fr.onboarding_id
    where 1=1 
    and o.subscription_start_date::date between '2025-01-01' and '2025-01-31'
--    and fr.created_at::date <= '2025-12-31'
    and substatus_id in (29,31)
    and color is not null
    """

cur.execute(color_fetch_query)
contact_data = cur.fetchall()
df2=pd.DataFrame(contact_data)
print(df2.head())
print(df2.shape)
exit()
df3 = (
    df2
    .sort_values("created_at", ascending=False)
    .drop_duplicates(subset=["color"], keep="first")
)
df_remaining = df2.merge(
    df3[["lead_id", "onboarding_id"]],
    on=["lead_id", "onboarding_id"],
    how="left",
    indicator=True
).query('_merge == "left_only"').drop(columns="_merge")

assigned_rows = []
rm_list=[1495, 2279, 2278, 470, 2277, 433, 432, 2686, 2275, 2528, 122, 2274, 2273, 2146, 444, 2280]

# colors = df_remaining["color"].unique()
# colors='ORANGE'
data=pd.pivot_table(data=df2,values='color',aggfunc='count')
print(data)
exit()
for color in colors:
    color_leads = df_remaining[df_remaining["color"] == color].sort_values("created_at")
    
    for idx, (_, row) in enumerate(color_leads.iterrows()):
        rm = rm_list[idx % len(rm_list)]
        row["assigned_to"] = rm
        assigned_rows.append(row)

df_remaining_assigned = pd.DataFrame(assigned_rows)
final_df = pd.concat([df3, df_remaining_assigned], ignore_index=True)

final_df = final_df.sort_values(["color", "created_at"], ascending=[True, False])

final_df.to_csv(r"E:\Download\customer_service_task.csv")
# print(final_df.head(20))