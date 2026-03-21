with Total_Time_Spent as (with user_point_cte as (
select
	distinct on
	(contact_id) a.meta_info ->'payload'->>'User_Points' as user_point,
	*
from
	activity a
where
	a.meta_info ->'payload'->>'User_Points' is not null
	or a.meta_info ->'payload'->>'User_Points' != ''
order by
	contact_id,
	activity_id desc)
select
	COALESCE(to_char(l.created_at, 'YYYY-mm-dd'), 'N/A')  as "lead Created Date",
	c.contact_id,
	c.full_name as "Lead Name",
	c.mobile_number as "Lead Number",
	c.email_address as "Lead Email",
	mp.name as "Product",
	ms3."name" as "Sub-Product",
	ms."name" as "Lead Status",
	ms2.name as "Lead Substatus",
	mu.full_name as "Counsellor Name",
	mu.email_address as "Counsellor Email",
	mu2.full_name AS "Pulled By",
	--    a.meta_info
	sum(case when a.meta_info->'payload'->>'Event_Name' = 'Login' then 1 else 0 end) as "number of login",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' = 'Trends that matter'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Latest Trends'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE 
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' = 'Trends that matter'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Latest Trends'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE 
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "Latest Trends",
	--    sum(case when a.meta_info -> 'payload' ->> 'Content_Category' = 'Trends that matter' and a.meta_info -> 'payload' ->> 'Content_Sub_Category' = 'Latest Trends' then 1 else 0 end) as "Latest Trends",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' = 'Trends that matter'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Weekly roundup'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' = 'Trends that matter'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Weekly roundup'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "Weekly roundup",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' = 'Insightful Shorts'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' = 'Insightful Shorts'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "Insightful Shorts",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' = 'All About Investing'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Success Stories'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' = 'All About Investing'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Success Stories'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "success stories",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' = 'All About Investing'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Learn From Legends'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' = 'All About Investing'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Learn From Legends'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "learn from legends",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' = 'All About Investing'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Invest Like a Pro'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' = 'All About Investing'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Invest Like a Pro'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "investing like pro",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' = 'All About Investing'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Investing Fundas'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' = 'All About Investing'
       AND a.meta_info->'payload'->>'Content_Sub_Category' = 'Investing Fundas'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "investing fundas",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' IN ('Mission Vision','Mission & Vision')
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' IN ('Mission Vision','Mission & Vision')
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "Mission vison",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' = 'Success Stories'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' = 'Success Stories'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "Success Stories (Testimonial)",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Content_Category' = 'ThreeCFrame'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Content_Category' = 'ThreeCFrame'
       AND a.meta_info->'payload'->>'Event_Name' = 'Content Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "3C framework",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Course_Name' = ' Investing Basics Course'
       AND a.meta_info->'payload'->>'Event_Name' = 'Course Video Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Course_Name' = ' Investing Basics Course'
       AND a.meta_info->'payload'->>'Event_Name' = 'Course Video Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "Investing Basics Course",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN TRIM(a.meta_info->'payload'->>'Course_Name') = 'Fundamental Analysis Course'
       AND a.meta_info->'payload'->>'Event_Name' = 'Course Video Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN TRIM(a.meta_info->'payload'->>'Course_Name') = 'Fundamental Analysis Course'
       AND a.meta_info->'payload'->>'Event_Name' = 'Course Video Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "Fundamental Analysis Course",
	TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN TRIM(a.meta_info->'payload'->>'Course_Name') = 'India Story Course'
       AND a.meta_info->'payload'->>'Event_Name' = 'Course Video Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN TRIM(a.meta_info->'payload'->>'Course_Name') = 'India Story Course'
       AND a.meta_info->'payload'->>'Event_Name' = 'Course Video Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "India Story Course",
TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN TRIM(a.meta_info->'payload'->>'Course_Name') = 'How to Analyse and Invest in CPVC Pipes?'
       AND a.meta_info->'payload'->>'Event_Name' = 'Course Video Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN TRIM(a.meta_info->'payload'->>'Course_Name') = 'How to Analyse and Invest in CPVC Pipes?'
       AND a.meta_info->'payload'->>'Event_Name' = 'Course Video Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "How to Analyse and Invest in CPVC Pipes",
   TO_CHAR(
  TIME '00:00:00' + SUM(
    CASE
      WHEN a.meta_info->'payload'->>'Event_Name' = 'Podcast Abandoned'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'User_Watched_Time','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'User_Watched_Time')::interval
          ELSE interval '0 seconds'
        END
      WHEN a.meta_info->'payload'->>'Event_Name' = 'Podcast Completed'
      THEN
        CASE
          WHEN NULLIF(a.meta_info->'payload'->>'Actual_Content_Video_Length','') ~ '^\d{2}:\d{2}:\d{2}$'
          THEN (a.meta_info->'payload'->>'Actual_Content_Video_Length')::interval
          ELSE interval '0 seconds'
        END
      ELSE interval '0 seconds'
    END
  ),
  'HH24:MI:SS'
) AS "Total Podcast watch time",
TO_CHAR(
    COALESCE(
        SUM(
            CASE
                WHEN a.meta_info -> 'payload' ->> 'Event_Name' = 'Workshop Abandoned'
                THEN
                    CASE
                        WHEN (a.meta_info -> 'payload' ->> 'User_Watched_Time') ~ '^\d+$'
                            THEN (a.meta_info -> 'payload' ->> 'User_Watched_Time')::int * interval '1 second'
                        WHEN (a.meta_info -> 'payload' ->> 'User_Watched_Time') ~ '^\d{2}:\d{2}:\d{2}$'
                            THEN (a.meta_info -> 'payload' ->> 'User_Watched_Time')::interval
                        ELSE interval '0 seconds'
                    END
                WHEN a.meta_info -> 'payload' ->> 'Event_Name' = 'Workshop Completed'
                THEN
                    CASE
                        WHEN (a.meta_info -> 'payload' ->> 'Actual_Content_Video_Length') ~ '^\d+$'
                            THEN (a.meta_info -> 'payload' ->> 'Actual_Content_Video_Length')::int * interval '1 second'
                        WHEN (a.meta_info -> 'payload' ->> 'Actual_Content_Video_Length') ~ '^\d{2}:\d{2}:\d{2}$'
                            THEN (a.meta_info -> 'payload' ->> 'Actual_Content_Video_Length')::interval
                        ELSE interval '0 seconds'
                    END
                ELSE interval '0 seconds'
            END
        ),
        interval '0 seconds'
    ),
    'HH24:MI:SS'
) AS "Total Workshop watch time",
	sum(case when trim(a.meta_info->'payload'->>'Event_Name') = 'Quiz Started' and trim(a.meta_info->'payload'->>'Course_Name') = 'Investing Basics Course' then 1 else 0 end) as "Quiz Started-Investing Basics Course",
	sum(case when trim(a.meta_info->'payload'->>'Event_Name') = 'Quiz Started' and trim(a.meta_info->'payload'->>'Course_Name') = 'Fundamental Analysis Course' then 1 else 0 end) as "Quiz Started-Fundamental Analysis Course",
	sum(case when trim(a.meta_info->'payload'->>'Event_Name') = 'Quiz Started' and trim(a.meta_info->'payload'->>'Course_Name') = 'India Story Course' then 1 else 0 end) as "Quiz Started-India Story Course",
	sum(case when trim(a.meta_info->'payload'->>'Event_Name') = 'Quiz Completed' and trim(a.meta_info->'payload'->>'Course_Name') = 'Investing Basics Course' then 1 else 0 end) as "Quiz Completed-Investing Basics Course",
	sum(case when trim(a.meta_info->'payload'->>'Event_Name') = 'Quiz Completed' and trim(a.meta_info->'payload'->>'Course_Name') = 'Fundamental Analysis Course' then 1 else 0 end) as "Quiz Completed-Fundamental Analysis Course",
	sum(case when trim(a.meta_info->'payload'->>'Event_Name') = 'Quiz Completed' and trim(a.meta_info->'payload'->>'Course_Name') = 'India Story Course' then 1 else 0 end) as "Quiz Completed-India Story Course",
	tc.user_point as "User_Point",
	sum(case when trim(a.meta_info->'payload'->>'Event_Name') = 'Course Purchased' then 1 else 0 end) as "Course Purchased",
	string_agg((case
		when trim(a.meta_info->'payload'->>'Event_Name') = 'Course Purchased' then trim(a.meta_info->'payload'->>'Course_Name')
	end),
	',') as course_name,
	sum(case when trim(a.meta_info->'payload'->>'Event_Name') = 'Workshop Purchased' then 1 else 0 end) as "Workshop Purchased",
	string_agg((case
		when trim(a.meta_info->'payload'->>'Event_Name') = 'Workshop Purchased' then trim(a.meta_info->'payload'->>'Workshop_Name')
	end),
	',') as "Workshop_Name"
	--	cc.course_name as "Course Name"
	--    sum(case when )
from
	"lead" l
left join mst_status ms on
	l.status_id = ms.status_id
left join mst_substatus ms2 on
	ms2.substatus_id = l.substatus_id
left join mst_product mp on
	l.product_id = mp.product_id
left join mst_subproduct ms3 on
	ms3.sub_product_id = any(l.sub_product_ids)
left join contact c on
	c.contact_id = l.contact_id
left join mst_user mu on
	mu.user_id = l.rm_id
left join activity a on
	l.contact_id = a.contact_id
left join user_point_cte tc on
	tc.contact_id = a.contact_id
LEFT JOIN (
SELECT
	DISTINCT ON
	(lead_id)*
FROM
	pool_contact_mapping pcm
WHERE
	pcm.is_taken = TRUE
	AND pcm.is_mapped = FALSE AND is_active =true
ORDER BY
	lead_id,
	pool_mapping_id DESC ) pcm ON pcm.lead_id=l.lead_id
LEFT JOIN mst_user mu2 ON mu2.user_id=pcm.rm_id
WHERE a.created_at::date = current_date-1 
group by
	to_char(l.created_at ,
	'YYYY-mm-dd'),
	c.contact_id,
	c.full_name ,
	c.mobile_number ,
	c.email_address,
	mp.name ,
	ms3."name" ,
	ms."name",
	ms2.name ,
	mu.full_name ,
	mu.email_address,
	tc.user_point,mu2.full_name )
select
	*,
	(tts."Latest Trends"::interval + tts."Weekly roundup"::interval + tts."Insightful Shorts"::interval + tts."success stories"::interval + tts."learn from legends"::interval + tts."investing like pro"::interval + tts."investing fundas"::interval + tts."Mission vison"::interval + tts."3C framework"::interval+tts."Success Stories (Testimonial)"::interval+tts."Investing Basics Course"::interval+tts."Fundamental Analysis Course"::interval+tts."India Story Course"::interval + tts."How to Analyse and Invest in CPVC Pipes"::interval + tts."Total Podcast watch time"::interval+ tts."Total Workshop watch time"::interval) as "Total Time Spent"  --
from
	Total_Time_Spent tts;