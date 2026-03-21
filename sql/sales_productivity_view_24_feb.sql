-- public.sales_productivity_vw source

CREATE OR REPLACE VIEW public.sales_productivity_vw
AS WITH follow_up AS (
         WITH latest AS (
                 SELECT t.lead_id,
                    t.follow_up,
                    t.is_completed,
                    t.created_at,
                    t.updated_at,
                    t.completed_on
                   FROM ( SELECT follow_up.follow_up_id,
                            follow_up.activity_id,
                            follow_up.company_id,
                            follow_up.lead_id,
                            follow_up.onboarding_id,
                            follow_up.contact_id,
                            follow_up.rm_id,
                            follow_up.customer_id,
                            follow_up.activity_type_id,
                            follow_up.status_id,
                            follow_up.substatus_id,
                            follow_up.follow_up,
                            follow_up.is_completed,
                            follow_up.created_at,
                            follow_up.created_by,
                            follow_up.updated_at,
                            follow_up.updated_by,
                            follow_up.reference_id,
                            follow_up.source,
                            follow_up.source_info,
                            follow_up.completed_on,
                            row_number() OVER (PARTITION BY follow_up.lead_id ORDER BY follow_up.follow_up DESC) AS rn
                           FROM public.follow_up) t
                  WHERE t.rn = 1
                )
         SELECT latest.lead_id,
            latest.follow_up,
            latest.is_completed,
            latest.created_at,
            latest.updated_at,
            latest.completed_on,
            1 AS follow_ups,
                CASE
                    WHEN latest.is_completed THEN 'completed'::text
                    WHEN NOT latest.is_completed AND latest.follow_up < now() THEN 'overdue'::text
                    ELSE NULL::text
                END AS follow_up_status
           FROM latest
        ), untouched_logic AS (
         SELECT abc.lead_id,
            abc.contact_id,
            1 AS untouched_flag
           FROM lead l
             RIGHT JOIN ( SELECT untouch.lead_id,
                    untouch.contact_id,
                    untouch.last_activity_created_at,
                    untouch.rn
                   FROM ( SELECT unt.lead_id,
                            unt.contact_id,
                            unt.last_activity_created_at,
                            row_number() OVER (PARTITION BY unt.lead_id ORDER BY unt.last_activity_created_at DESC) AS rn
                           FROM ( SELECT l_1.lead_id,
                                    c.contact_id,
                                    aa.created_at AS last_activity_created_at
                                   FROM lead l_1
                                     JOIN ( SELECT a.lead_id,
    max(a.created_at) AS created_at
   FROM activity a
  WHERE a.activity_type_id = 1 AND lower(a.origin::text) = 'outbound'::text AND a.call_duration > 0::double precision OR a.activity_type_id = 4 OR a.activity_type_id = 2 AND (EXISTS ( SELECT 1
     FROM jsonb_array_elements(a.meta_info -> 'msgs'::text) elem(value)
    WHERE (elem.value ->> 'category'::text) = 'Outgoing'::text)) OR a.activity_type_id = 3 AND ((a.meta_info ->> 'status'::text) = 'Pending'::text OR (a.meta_info ->> 'status'::text) = 'Sent'::text)
  GROUP BY a.lead_id) aa ON l_1.lead_id = aa.lead_id
                                     JOIN contact c ON c.contact_id = l_1.contact_id
                                     JOIN contact_mapping cm ON c.contact_id = cm.contact_id AND l_1.rm_id = cm.rm_id
                                  WHERE c.is_active IS TRUE AND l_1.is_active IS TRUE AND cm.type = 'Sales'::mapping_type AND cm.end_date IS NULL AND aa.created_at < (now() - '30 days'::interval)) unt) untouch
                  WHERE untouch.rn = 1) abc ON abc.lead_id = l.lead_id
        ), appointment_book AS (
         WITH follow_ups AS (
                 SELECT fu_1.follow_up_id,
                    fu_1.activity_id,
                    fu_1.company_id,
                    fu_1.lead_id,
                    fu_1.onboarding_id,
                    fu_1.contact_id,
                    fu_1.rm_id,
                    fu_1.customer_id,
                    fu_1.activity_type_id,
                    fu_1.status_id,
                    fu_1.substatus_id,
                    fu_1.follow_up,
                    fu_1.is_completed,
                    fu_1.created_at,
                    fu_1.created_by,
                    fu_1.updated_at,
                    fu_1.updated_by,
                    fu_1.reference_id,
                    fu_1.source,
                    fu_1.source_info,
                    fu_1.completed_on
                   FROM public.follow_up fu_1
                  WHERE fu_1.source = 'whatsapp'::follow_up_source AND fu_1.source_info::text <> '{}'::text
                )
         SELECT DISTINCT ON (c.mobile_number, c.email_address, c.contact_id) c.full_name AS lead_name,
            c.contact_id,
            fu.created_at AS appointment_created_date,
            fu.follow_up AS appointment_booked_date,
            fu.source_info ->> 'utm_medium'::text AS appointment_utm_medium,
            fu.source_info ->> 'utm_source'::text AS appointment_utm_source,
            fu.source_info ->> 'utm_campaign'::text AS appointment_utm_campaign,
            fu.source_info ->> 'utm_content'::text AS appointment_utm_content,
            fu.source_info ->> 'page_url'::text AS appointment_utm_url,
                CASE
                    WHEN fu.is_completed THEN 1
                    ELSE 0
                END AS is_appointment_completed,
            fu.completed_on AS appointment_completed_date,
            il.created_at AS lead_created_date,
            il.utm_medium AS initial_lead_utm_medium,
            il.utm_source AS initial_lead_utm_source,
            il.utm_campaign AS initial_lead_utm_campaign,
            il.utm_content AS initial_utm_content,
            il.page_url AS initial_lead_utm_url,
            rl.updated_at AS repeat_lead_created_date,
            rl.utm_medium AS repeat_lead_utm_medium,
            rl.utm_source AS repeat_lead_utm_source,
            rl.utm_campaign AS repeat_lead_utm_campaign,
            rl.utm_content AS repeat_lead_utm_content,
            rl.page_url AS repeat_lead_utm_url,
            to_char(sfd.payment_date, 'DD Mon YY'::text) AS payment_date_ab,
            to_char(sl.created_at, 'DD Mon YY'::text) AS subscription_start_date_ab,
            mu2.full_name AS converted_by_counsellor_name,
            mu2.email_address AS converted_by_counsellor_email,
            1 AS appointment_booking_flag,
            sum(
                CASE
                    WHEN fu.follow_up >= COALESCE(fu.completed_on, fu.updated_at) AND fu.is_completed = true THEN 1
                    ELSE 0
                END) AS completed_ontime,
            sum(
                CASE
                    WHEN fu.follow_up < COALESCE(fu.completed_on, fu.updated_at, now()) AND fu.is_completed = false THEN 1
                    ELSE 0
                END) AS overdue_appointment,
            sum(
                CASE
                    WHEN fu.is_completed = false THEN 1
                    ELSE 0
                END) AS active_appointment,
            l.lead_id,
                CASE
                    WHEN l.substatus_id = ANY (ARRAY[3, 6, 7, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 54, 55, 57, 60]) THEN 1
                    ELSE 0
                END AS workable_sl,
                CASE
                    WHEN l.substatus_id = ANY (ARRAY[9, 10, 11, 15, 56, 58, 59, 61, 64, 65]) THEN 1
                    ELSE 0
                END AS non_workable_sl
           FROM follow_ups fu
             LEFT JOIN lead l ON fu.contact_id = l.contact_id
             LEFT JOIN contact c ON c.contact_id = fu.contact_id
             LEFT JOIN mst_user mu ON mu.user_id = fu.rm_id
             LEFT JOIN mst_location ml ON ml.location_id = mu.location_id
             LEFT JOIN ( SELECT DISTINCT ON (ll.lead_id) ll.log_id,
                    ll.log_timestamp,
                    ll.operation_type,
                    ll.lead_id,
                    ll.lead_number,
                    ll.company_id,
                    ll.contact_id,
                    ll.lead_raw_id,
                    ll.rm_id,
                    ll.lead_source_id,
                    ll.product_id,
                    ll.prospect_sub_product_ids,
                    ll.additional_info,
                    ll.status_id,
                    ll.substatus_id,
                    ll.repeat_lead_raw_id,
                    ll.repeat_lead_raw_date,
                    ll.device,
                    ll.referral_code,
                    ll.utm_campaign,
                    ll.utm_medium,
                    ll.utm_content,
                    ll.api_url,
                    ll.page_name,
                    ll.page_url,
                    ll.page_id,
                    ll.ip_address,
                    ll.meta_info,
                    ll.created_at,
                    ll.created_by,
                    ll.updated_at,
                    ll.updated_by,
                    ll.trackrr_customer_id,
                    ll.trackrr_sales_source_id,
                    ll.initial_lead_id,
                    ll.initial_lead_details,
                    ll.utm_source,
                    ll.sub_product_ids,
                    ll.is_active
                   FROM lead_log ll
                  WHERE (ll.lead_id IN ( SELECT follow_ups.lead_id
                           FROM follow_ups))
                  ORDER BY ll.lead_id, ll.log_id) il ON il.lead_id = fu.lead_id
             LEFT JOIN ( SELECT DISTINCT ON (ll.lead_id) ll.log_id,
                    ll.log_timestamp,
                    ll.operation_type,
                    ll.lead_id,
                    ll.lead_number,
                    ll.company_id,
                    ll.contact_id,
                    ll.lead_raw_id,
                    ll.rm_id,
                    ll.lead_source_id,
                    ll.product_id,
                    ll.prospect_sub_product_ids,
                    ll.additional_info,
                    ll.status_id,
                    ll.substatus_id,
                    ll.repeat_lead_raw_id,
                    ll.repeat_lead_raw_date,
                    ll.device,
                    ll.referral_code,
                    ll.utm_campaign,
                    ll.utm_medium,
                    ll.utm_content,
                    ll.api_url,
                    ll.page_name,
                    ll.page_url,
                    ll.page_id,
                    ll.ip_address,
                    ll.meta_info,
                    ll.created_at,
                    ll.created_by,
                    ll.updated_at,
                    ll.updated_by,
                    ll.trackrr_customer_id,
                    ll.trackrr_sales_source_id,
                    ll.initial_lead_id,
                    ll.initial_lead_details,
                    ll.utm_source,
                    ll.sub_product_ids,
                    ll.is_active
                   FROM lead_log ll
                  WHERE (ll.lead_id IN ( SELECT follow_ups.lead_id
                           FROM follow_ups)) AND ll.substatus_id = 3
                  ORDER BY ll.lead_id, ll.log_id DESC) rl ON rl.lead_id = fu.lead_id
             LEFT JOIN ( SELECT DISTINCT ON (sfd_1.lead_id) sfd_1.lead_id,
                    sfd_1.payment_date
                   FROM sales_flat_data sfd_1
                  WHERE (sfd_1.lead_id IN ( SELECT follow_ups.lead_id
                           FROM follow_ups))
                  ORDER BY sfd_1.lead_id, sfd_1.payment_date) sfd ON sfd.lead_id = fu.lead_id
             LEFT JOIN ( SELECT DISTINCT ON (sl_1.lead_id) sl_1.lead_id,
                    sl_1.rm_id,
                    sl_1.created_at
                   FROM status_log sl_1
                  WHERE (sl_1.lead_id IN ( SELECT follow_ups.lead_id
                           FROM follow_ups)) AND sl_1.substatus_id = 29
                  ORDER BY sl_1.lead_id, sl_1.created_at) sl ON sl.lead_id = fu.lead_id
             LEFT JOIN mst_user mu2 ON mu2.user_id = sl.rm_id
          GROUP BY c.full_name, c.contact_id, ml.name, mu.user_id, mu.email_address, fu.created_at, fu.follow_up, fu.source_info, fu.is_completed, fu.completed_on, il.created_at, il.utm_medium, il.utm_source, il.utm_campaign, il.utm_content, il.page_url, rl.updated_at, rl.utm_medium, rl.utm_source, rl.utm_campaign, rl.utm_content, rl.page_url, sfd.payment_date, sl.created_at, mu2.full_name, mu2.email_address, l.lead_id, l.status_id, l.substatus_id
          ORDER BY c.mobile_number, c.email_address, c.contact_id, fu.created_at DESC
        ), repeat_lead_logic AS (
         SELECT preparing.lead_id,
            preparing.created_at AS repeat_lead_date
           FROM ( SELECT DISTINCT ON (ll.lead_id) ll.lead_id,
                    ll.created_at
                   FROM status_log ll
                  WHERE ll.substatus_id = 3
                  ORDER BY ll.lead_id, ll.status_log_id DESC) preparing
        ), converted_leads AS (
         WITH paymenttable AS (
                 SELECT p.payment_id,
                    0 AS offline_payment_id,
                    p.onboarding_id,
                    p.sub_product_id,
                    p.lead_id,
                    p.contact_id,
                    'online'::text AS payment_type,
                    p.provider_reference_id,
                    p.payment_date
                   FROM payment p
                UNION
                 SELECT 0 AS payment_id,
                    op.offline_payment_id,
                    op.onboarding_id,
                    op.sub_product_id,
                    op.lead_id,
                    op.contact_id,
                    'offline-pending'::text AS payment_type,
                    op.payment_utr_number AS provider_reference_id,
                    op.payment_date
                   FROM offline_payment op
                  WHERE op.status = 'Pending'::offline_payment_status
                )
         SELECT DISTINCT ON (pt.lead_id) pt.lead_id,
            pt.payment_date,
            sp.name AS product_name
           FROM paymenttable pt
             LEFT JOIN mst_subproduct sp ON pt.sub_product_id = sp.sub_product_id
        )
 SELECT base.lead_id,
    base.report_date,
    base.refresh_date,
    base.new_lead_count_date,
    COALESCE(base.captain_counsellor, people_date.captain_counsellor) AS captain_counsellor,
    COALESCE(base.counsellor, people_date.counsellor) AS counsellor,
    base.counsellor_id,
    COALESCE(base.location, people_date.location) AS location,
    base.call_duration,
    base."Called",
    base."Had a Phone Conversation",
    base."Detailed Conversation",
    base."Talktime",
    base."Notes - Not Answered",
    base."Notes - Detail conversation-Sales Pitch",
    base."Notes - Detail Conversation",
    base."Notes - Had a Phone Conversation",
    base."Call - Not Answered",
    base."Call - Detail conversation-Sales Pitch",
    base."Call - Detail Conversation",
    base."Call - Had a Phone Conversation",
    base.group_name,
    base.short_name,
    base.detailed_conversation_flag,
    base."Total Calls",
    base."INTERESTED",
    base.warm,
    base.hot,
    base.cold,
    base.work_to_non_work_i,
    base."NEW LEAD",
    base.new_lead,
    base.existing_customer,
    base.untagged,
    base.repeat_lead,
    base."CONTACTED",
    base.work_to_non_work_c,
    base.pitched,
    base.not_pitched,
    base.forwarded,
    base.language_barrier,
    base.not_reachable,
    base.pre_sales_qualified,
    base.dnd,
    base.invalid,
    base."NOT INTERESTED",
    base.not_interested,
    base.customer_declined,
    base.no_progress,
    base."ONBOARDING",
    base.onboarding_closed,
    base.in_process,
    base.mobile_otp_verified,
    base.email_otp_verified,
    base.kra_verified,
    base.ckyc_verified,
    base.pan_verified,
    base.risk_profile,
    base.portfolio_selection,
    base.suitability_assessment,
    base.agreement_signed,
    base.payment_pending,
    base.payment_received,
    base.subscription_started,
    base.payment_adjusted,
    base.self_kyc_verified,
    base."SUBSCRIPTION",
    base.active,
    base.deactivated_s,
    base.expired,
    base.extended,
    base.refunded,
    base.refund_processing,
    base.refund_requested,
    base.cancelled,
    base.downgraded,
    base.upgraded,
    base.refund_rejected,
    base."COLLECTIONS",
    base.assigned,
    base.unreachable,
    base.neutral_response,
    base.positive_response,
    base.contacted,
    base.ticket_raised,
    base.payment_link_sent,
    base.payment_collected,
    base.transferred,
    base.transfer_requested,
    base.deactivation_request_rejected,
    base.deactivation_requested,
    base.closed,
    base.log_id,
    base.deactivated_c,
    base.grand_total,
    base.lead_status,
    base.lead_substatus,
    base.follow_up_status,
    base.follow_ups,
    to_timestamp(base.login_time, 'DD-MM-YYYY HH24:MI:SS'::text) AS login_time,
    to_timestamp(base.logout_time, 'DD-MM-YYYY HH24:MI:SS'::text) AS logout_time,
    base.converted,
    base.conversion_count,
    base.arpa_amount,
    base.arft_amount,
    base.emandate_count,
    base.cash_flow_amount,
    base.cash_flow_count,
    base.repeat_lead_date,
    base.activity_count_flag,
    base.payment_date,
    base.product_name,
    base."Flag",
    base.workable_untouched,
    base.non_workable_untouched,
    COALESCE(base.lead_name, lnn.full_name) AS lead_name,
    base.lead_mobile,
    base.lead_email,
    base.product,
    base.sub_product,
    base.utm_medium,
    base.utm_source,
    base.utm_campaign,
    base.utm_content,
    base.utm_url,
    base.initially_taken_by,
    base.initially_taken_by_location,
    base.status_id_sl,
    base.substatus_id_sl,
    base.created_at_sl,
    base.touched,
    base.workable,
    base.non_workable,
    base.touched_sl,
    base.workable_sl,
    base.non_workable_sl,
    base.not_pitched_sl,
    base.converted_sl,
    COALESCE(base.contact_id, con.contact_id) AS contact_id,
    base.untouched_flag,
    base.appointment_created_date,
    base.appointment_booked_date,
    base.appointment_utm_medium,
    base.appointment_utm_source,
    base.appointment_utm_campaign,
    base.appointment_utm_content,
    base.appointment_utm_url,
    base.is_appointment_completed,
    base.appointment_completed_date,
    base.lead_created_date,
    base.initial_lead_utm_medium,
    base.initial_lead_utm_source,
    base.initial_lead_utm_campaign,
    base.initial_utm_content,
    base.initial_lead_utm_url,
    base.repeat_lead_created_date,
    base.repeat_lead_utm_medium,
    base.repeat_lead_utm_source,
    base.repeat_lead_utm_campaign,
    base.repeat_lead_utm_content,
    base.repeat_lead_utm_url,
    base.payment_date_ab,
    base.subscription_start_date_ab,
    base.converted_by_counsellor_name,
    base.converted_by_counsellor_email,
    base.completed_ontime,
    base.overdue_appointment,
    base.active_appointment,
    base.appointment_booking_flag,
    base.comment,
    base.additional_comments,
    base.completed_on,
    people_date.product AS user_product
   FROM ( SELECT t2.lead_id,
            t2.report_date,
            t2.report_date AS refresh_date,
            NULL::timestamp with time zone AS new_lead_count_date,
            NULL::character varying AS captain_counsellor,
            t2.counsellor,
            t2.counsellor_id,
            t2.location,
            t2.call_duration,
            t2."Called",
            t2."Had a Phone Conversation",
            t2."Detailed Conversation",
            t2."Talktime",
            t2."Notes - Not Answered",
            t2."Notes - Detail conversation-Sales Pitch",
            t2."Notes - Detail Conversation",
            t2."Notes - Had a Phone Conversation",
            t2."Call - Not Answered",
            t2."Call - Detail conversation-Sales Pitch",
            t2."Call - Detail Conversation",
            t2."Call - Had a Phone Conversation",
            t2.group_name,
            t2.short_name,
                CASE
                    WHEN t2.call_duration >= 600::double precision THEN 1
                    ELSE 0
                END AS detailed_conversation_flag,
            t2."Called" + t2."Had a Phone Conversation" + t2."Detailed Conversation" + t2."Notes - Not Answered" + t2."Notes - Detail conversation-Sales Pitch" + t2."Notes - Not Answered" + t2."Notes - Had a Phone Conversation" + t2."Call - Not Answered" + t2."Call - Detail conversation-Sales Pitch" + t2."Call - Detail Conversation" + t2."Call - Had a Phone Conversation" AS "Total Calls",
            NULL::bigint AS "INTERESTED",
            NULL::bigint AS warm,
            NULL::bigint AS hot,
            NULL::bigint AS cold,
            NULL::bigint AS work_to_non_work_i,
            NULL::bigint AS "NEW LEAD",
            NULL::bigint AS new_lead,
            NULL::bigint AS existing_customer,
            NULL::bigint AS untagged,
            NULL::bigint AS repeat_lead,
            NULL::bigint AS "CONTACTED",
            NULL::bigint AS work_to_non_work_c,
            NULL::bigint AS pitched,
            NULL::bigint AS not_pitched,
            NULL::bigint AS forwarded,
            NULL::bigint AS language_barrier,
            NULL::bigint AS not_reachable,
            NULL::bigint AS pre_sales_qualified,
            NULL::bigint AS dnd,
            NULL::bigint AS invalid,
            NULL::bigint AS "NOT INTERESTED",
            NULL::bigint AS not_interested,
            NULL::bigint AS customer_declined,
            NULL::bigint AS no_progress,
            NULL::bigint AS "ONBOARDING",
            NULL::bigint AS onboarding_closed,
            NULL::bigint AS in_process,
            NULL::bigint AS mobile_otp_verified,
            NULL::bigint AS email_otp_verified,
            NULL::bigint AS kra_verified,
            NULL::bigint AS ckyc_verified,
            NULL::bigint AS pan_verified,
            NULL::bigint AS risk_profile,
            NULL::bigint AS portfolio_selection,
            NULL::bigint AS suitability_assessment,
            NULL::bigint AS agreement_signed,
            NULL::bigint AS payment_pending,
            NULL::bigint AS payment_received,
            NULL::bigint AS subscription_started,
            NULL::bigint AS payment_adjusted,
            NULL::bigint AS self_kyc_verified,
            NULL::bigint AS "SUBSCRIPTION",
            NULL::bigint AS active,
            NULL::bigint AS deactivated_s,
            NULL::bigint AS expired,
            NULL::bigint AS extended,
            NULL::bigint AS refunded,
            NULL::bigint AS refund_processing,
            NULL::bigint AS refund_requested,
            NULL::bigint AS cancelled,
            NULL::bigint AS downgraded,
            NULL::bigint AS upgraded,
            NULL::bigint AS refund_rejected,
            NULL::bigint AS "COLLECTIONS",
            NULL::bigint AS assigned,
            NULL::bigint AS unreachable,
            NULL::bigint AS neutral_response,
            NULL::bigint AS positive_response,
            NULL::bigint AS contacted,
            NULL::bigint AS ticket_raised,
            NULL::bigint AS payment_link_sent,
            NULL::bigint AS payment_collected,
            NULL::bigint AS transferred,
            NULL::bigint AS transfer_requested,
            NULL::bigint AS deactivation_request_rejected,
            NULL::bigint AS deactivation_requested,
            NULL::bigint AS closed,
            NULL::bigint AS deactivated_c,
            NULL::bigint AS grand_total,
            NULL::character varying AS lead_status,
            NULL::character varying AS lead_substatus,
            NULL::text AS follow_up_status,
            NULL::integer AS follow_ups,
            NULL::text AS login_time,
            NULL::text AS logout_time,
            NULL::integer AS converted,
            NULL::integer AS conversion_count,
            NULL::integer AS arpa_amount,
            NULL::integer AS arft_amount,
            NULL::integer AS emandate_count,
            NULL::integer AS cash_flow_amount,
            NULL::integer AS cash_flow_count,
            NULL::timestamp with time zone AS repeat_lead_date,
            t2.activity_count_flag,
            NULL::timestamp without time zone AS payment_date,
            NULL::character varying AS product_name,
            'Sales Calling'::text AS "Flag",
            NULL::integer AS workable_untouched,
            NULL::integer AS non_workable_untouched,
            NULL::character varying AS lead_name,
            NULL::character varying AS lead_mobile,
            NULL::character varying AS lead_email,
            NULL::character varying AS product,
            NULL::character varying AS sub_product,
            NULL::character varying AS utm_medium,
            NULL::character varying AS utm_source,
            NULL::character varying AS utm_campaign,
            NULL::character varying AS utm_content,
            NULL::character varying AS utm_url,
            NULL::character varying AS initially_taken_by,
            NULL::character varying AS initially_taken_by_location,
            NULL::smallint AS status_id_sl,
            NULL::smallint AS substatus_id_sl,
            NULL::timestamp with time zone AS created_at_sl,
            NULL::integer AS log_id,
            NULL::integer AS touched,
            NULL::integer AS workable,
            NULL::integer AS non_workable,
            NULL::integer AS touched_sl,
            NULL::integer AS workable_sl,
            NULL::integer AS non_workable_sl,
            NULL::integer AS not_pitched_sl,
            NULL::integer AS converted_sl,
            NULL::integer AS contact_id,
            NULL::integer AS untouched_flag,
            NULL::timestamp with time zone AS appointment_created_date,
            NULL::timestamp with time zone AS appointment_booked_date,
            NULL::text AS appointment_utm_medium,
            NULL::text AS appointment_utm_source,
            NULL::text AS appointment_utm_campaign,
            NULL::text AS appointment_utm_content,
            NULL::text AS appointment_utm_url,
            NULL::integer AS is_appointment_completed,
            NULL::timestamp with time zone AS appointment_completed_date,
            NULL::timestamp with time zone AS lead_created_date,
            NULL::character varying AS initial_lead_utm_medium,
            NULL::character varying AS initial_lead_utm_source,
            NULL::character varying AS initial_lead_utm_campaign,
            NULL::character varying AS initial_utm_content,
            NULL::text AS initial_lead_utm_url,
            NULL::timestamp with time zone AS repeat_lead_created_date,
            NULL::character varying AS repeat_lead_utm_medium,
            NULL::character varying AS repeat_lead_utm_source,
            NULL::character varying AS repeat_lead_utm_campaign,
            NULL::character varying AS repeat_lead_utm_content,
            NULL::text AS repeat_lead_utm_url,
            NULL::text AS payment_date_ab,
            NULL::text AS subscription_start_date_ab,
            NULL::character varying AS converted_by_counsellor_name,
            NULL::character varying AS converted_by_counsellor_email,
            NULL::bigint AS completed_ontime,
            NULL::bigint AS overdue_appointment,
            NULL::bigint AS active_appointment,
            NULL::integer AS appointment_booking_flag,
            NULL::character varying AS comment,
            NULL::character varying AS additional_comments,
            cs.completed_on
           FROM ( WITH active_users AS (
                         SELECT mu.user_id,
                            mu.full_name AS counsellor,
                            ml.name AS location,
                            md.group_name,
                            md.short_name
                           FROM mst_user mu
                             JOIN mst_department md ON md.department_id = mu.department_id
                             LEFT JOIN mst_location ml ON ml.location_id = mu.location_id
                          WHERE mu.is_active
                        ), user_calls AS (
                         SELECT au.counsellor,
                            au.user_id AS counsellor_id,
                            au.location,
                            cl.lead_id,
                            au.group_name,
                            au.short_name,
                            NULL::double precision AS call_duration,
                            0 AS activity_type,
                            cl.call_duration::text AS call_duration_or_comment,
                            COALESCE(cl.call_duration::integer, 0)::bigint AS call_duration_int,
                            cl.created_at,
                                CASE
                                    WHEN cl.call_duration < 5 AND ((cl.status_details::text = ANY (ARRAY['NoAnswer'::character varying::text, 'NoResponse'::character varying::text])) OR cl.status_details::text = 'NormalCallClearing'::text AND cl.call_status::text = 'not_answered'::text OR cl.status_details::text = 'NormalUnspecified'::text AND cl.call_status::text = 'not_answered'::text) THEN 1
                                    ELSE NULL::integer
                                END AS activity_count_flag
                           FROM active_users au
                             JOIN call_log cl ON cl.created_by = au.user_id
                          WHERE cl.lead_id IS NOT NULL
                        ), user_activities AS (
                         SELECT au.counsellor,
                            au.user_id AS counsellor_id,
                            au.location,
                            a.lead_id,
                            au.group_name,
                            au.short_name,
                            a.call_duration,
                            a.activity_type_id AS activity_type,
                            mc.name AS call_duration_or_comment,
                            COALESCE(a.call_duration, 0::double precision)::bigint AS call_duration_int,
                            a.created_at,
                            1 AS activity_count_flag
                           FROM active_users au
                             JOIN activity a ON a.created_by = au.user_id AND a.comment_ids && ARRAY[33::smallint, 36::smallint, 61::smallint, 62::smallint]
                             JOIN mst_comment mc ON (mc.comment_id = ANY (a.comment_ids)) AND (mc.comment_id = ANY (ARRAY[33, 36, 61, 62]))
                          WHERE a.lead_id IS NOT NULL
                        ), combined_data AS (
                         SELECT user_calls.counsellor,
                            user_calls.counsellor_id,
                            user_calls.location,
                            user_calls.lead_id,
                            user_calls.group_name,
                            user_calls.short_name,
                            user_calls.call_duration,
                            user_calls.activity_type,
                            user_calls.call_duration_or_comment,
                            user_calls.call_duration_int,
                            user_calls.created_at,
                            user_calls.activity_count_flag
                           FROM user_calls
                        UNION ALL
                         SELECT user_activities.counsellor,
                            user_activities.counsellor_id,
                            user_activities.location,
                            user_activities.lead_id,
                            user_activities.group_name,
                            user_activities.short_name,
                            user_activities.call_duration,
                            user_activities.activity_type,
                            user_activities.call_duration_or_comment,
                            user_activities.call_duration_int,
                            user_activities.created_at,
                            user_activities.activity_count_flag
                           FROM user_activities
                        )
                 SELECT t.counsellor,
                    t.counsellor_id,
                    t.call_duration,
                    t.created_at AS report_date,
                    t.lead_id,
                    t.group_name,
                    t.short_name,
                    t.location,
                    t.activity_count_flag,
                    sum(
                        CASE
                            WHEN t.activity_type = 0 AND t.call_duration_int = 0 THEN 1
                            ELSE 0
                        END) AS "Called",
                    sum(
                        CASE
                            WHEN t.activity_type = 0 AND t.call_duration_int > 0 AND t.call_duration_int < 600 THEN 1
                            ELSE 0
                        END) AS "Had a Phone Conversation",
                    sum(
                        CASE
                            WHEN t.activity_type = 0 AND t.call_duration_int > 600 THEN 1
                            ELSE 0
                        END) AS "Detailed Conversation",
                    to_char((COALESCE(sum(
                        CASE
                            WHEN t.activity_type = 0 THEN t.call_duration_int
                            ELSE 0::bigint
                        END), 0::numeric) || ' second'::text)::interval, 'HH24:MI:SS'::text) AS "Talktime",
                    sum(
                        CASE
                            WHEN t.activity_type = 7 AND t.call_duration_or_comment = 'Not Answered'::text THEN 1
                            ELSE 0
                        END) AS "Notes - Not Answered",
                    sum(
                        CASE
                            WHEN t.activity_type = 7 AND t.call_duration_or_comment = 'Detail conversation-Sales Pitch'::text THEN 1
                            ELSE 0
                        END) AS "Notes - Detail conversation-Sales Pitch",
                    sum(
                        CASE
                            WHEN t.activity_type = 7 AND t.call_duration_or_comment = 'Detail Conversation'::text THEN 1
                            ELSE 0
                        END) AS "Notes - Detail Conversation",
                    sum(
                        CASE
                            WHEN t.activity_type = 7 AND t.call_duration_or_comment = 'Had a Phone Conversation'::text THEN 1
                            ELSE 0
                        END) AS "Notes - Had a Phone Conversation",
                    sum(
                        CASE
                            WHEN t.activity_type = 1 AND t.call_duration_or_comment = 'Not Answered'::text THEN 1
                            ELSE 0
                        END) AS "Call - Not Answered",
                    sum(
                        CASE
                            WHEN t.activity_type = 1 AND t.call_duration_or_comment = 'Detail conversation-Sales Pitch'::text THEN 1
                            ELSE 0
                        END) AS "Call - Detail conversation-Sales Pitch",
                    sum(
                        CASE
                            WHEN t.activity_type = 1 AND t.call_duration_or_comment = 'Detail Conversation'::text THEN 1
                            ELSE 0
                        END) AS "Call - Detail Conversation",
                    sum(
                        CASE
                            WHEN t.activity_type = 1 AND t.call_duration_or_comment = 'Had a Phone Conversation'::text THEN 1
                            ELSE 0
                        END) AS "Call - Had a Phone Conversation"
                   FROM combined_data t
                  GROUP BY t.counsellor, t.counsellor_id, t.location, t.lead_id, t.call_duration, t.created_at, t.group_name, t.short_name, t.activity_count_flag) t2
             LEFT JOIN ( SELECT DISTINCT ON (fr.lead_id) fr.assigned_to,
                    fr.completed_on,
                    fr.lead_id
                   FROM feedback_response fr
                  WHERE fr.type::text = 'FEEDBACK'::text AND fr.assigned_to IS NOT NULL) cs ON t2.counsellor_id = cs.assigned_to AND t2.lead_id = cs.lead_id
        UNION ALL
         SELECT funnel_base.lead_id,
            funnel_base.created_at AS report_date,
            funnel_base.created_at AS refresh_date,
            funnel_base.updated_at AS new_lead_count_date,
            funnel_base.captain_counsellor,
            funnel_base.counsellor,
            funnel_base.counsellor_id,
            funnel_base.location,
            NULL::double precision AS call_duration,
            NULL::bigint AS "Called",
            NULL::bigint AS "Had a Phone Conversation",
            NULL::bigint AS "Detailed Conversation",
            NULL::text AS "Talktime",
            NULL::bigint AS "Notes - Not Answered",
            NULL::bigint AS "Notes - Detail conversation-Sales Pitch",
            NULL::bigint AS "Notes - Detail Conversation",
            NULL::bigint AS "Notes - Had a Phone Conversation",
            NULL::bigint AS "Call - Not Answered",
            NULL::bigint AS "Call - Detail conversation-Sales Pitch",
            NULL::bigint AS "Call - Detail Conversation",
            NULL::bigint AS "Call - Had a Phone Conversation",
            NULL::character varying AS group_name,
            NULL::character varying AS short_name,
            NULL::integer AS detailed_conversation_flag,
            NULL::bigint AS "Total Calls",
            funnel_base."INTERESTED",
            funnel_base.warm,
            funnel_base.hot,
            funnel_base.cold,
            funnel_base.work_to_non_work_i,
            funnel_base."NEW LEAD",
            funnel_base.new_lead,
            funnel_base.existing_customer,
            funnel_base.untagged,
            funnel_base.repeat_lead,
            funnel_base."CONTACTED",
            funnel_base.work_to_non_work_c,
            funnel_base.pitched,
            funnel_base.not_pitched,
            funnel_base.forwarded,
            funnel_base.language_barrier,
            funnel_base.not_reachable,
            funnel_base.pre_sales_qualified,
            funnel_base.dnd,
            funnel_base.invalid,
            funnel_base."NOT INTERESTED",
            funnel_base.not_interested,
            funnel_base.customer_declined,
            funnel_base.no_progress,
            funnel_base."ONBOARDING",
            funnel_base.onboarding_closed,
            funnel_base.in_process,
            funnel_base.mobile_otp_verified,
            funnel_base.email_otp_verified,
            funnel_base.kra_verified,
            funnel_base.ckyc_verified,
            funnel_base.pan_verified,
            funnel_base.risk_profile,
            funnel_base.portfolio_selection,
            funnel_base.suitability_assessment,
            funnel_base.agreement_signed,
            funnel_base.payment_pending,
            funnel_base.payment_received,
            funnel_base.subscription_started,
            funnel_base.payment_adjusted,
            funnel_base.self_kyc_verified,
            funnel_base."SUBSCRIPTION",
            funnel_base.active,
            funnel_base.deactivated_s,
            funnel_base.expired,
            funnel_base.extended,
            funnel_base.refunded,
            funnel_base.refund_processing,
            funnel_base.refund_requested,
            funnel_base.cancelled,
            funnel_base.downgraded,
            funnel_base.upgraded,
            funnel_base.refund_rejected,
            funnel_base."COLLECTIONS",
            funnel_base.assigned,
            funnel_base.unreachable,
            funnel_base.neutral_response,
            funnel_base.positive_response,
            funnel_base.contacted,
            funnel_base.ticket_raised,
            funnel_base.payment_link_sent,
            funnel_base.payment_collected,
            funnel_base.transferred,
            funnel_base.transfer_requested,
            funnel_base.deactivation_request_rejected,
            funnel_base.deactivation_requested,
            funnel_base.closed,
            funnel_base.deactivated_c,
            funnel_base.grand_total,
            funnel_base.status_id::character varying AS lead_status,
            funnel_base.substatus_id::character varying AS lead_substatus,
            funnel_base.follow_up_status,
            funnel_base.follow_ups,
            NULL::text AS login_time,
            NULL::text AS logout_time,
            NULL::integer AS converted,
            NULL::integer AS conversion_count,
            NULL::integer AS arpa_amount,
            NULL::integer AS arft_amount,
            NULL::integer AS emandate_count,
            NULL::integer AS cash_flow_amount,
            NULL::integer AS cash_flow_count,
            funnel_base.repeat_lead_date,
            NULL::integer AS activity_count_flag,
            funnel_base.payment_date,
            funnel_base.product_name,
            'Funnel Management'::text AS "Flag",
            funnel_base.workable_untouched,
            funnel_base.non_workable_untouched,
            funnel_base.lead_name,
            NULL::character varying AS lead_mobile,
            NULL::character varying AS lead_email,
            NULL::character varying AS product,
            NULL::character varying AS sub_product,
            NULL::character varying AS utm_medium,
            NULL::character varying AS utm_source,
            NULL::character varying AS utm_campaign,
            NULL::character varying AS utm_content,
            NULL::character varying AS utm_url,
            NULL::character varying AS initially_taken_by,
            NULL::character varying AS initially_taken_by_location,
            NULL::smallint AS status_id_sl,
            NULL::smallint AS substatus_id_sl,
            NULL::timestamp with time zone AS created_at_sl,
            NULL::integer AS log_id,
            NULL::integer AS touched,
            NULL::integer AS workable,
            NULL::integer AS non_workable,
            NULL::integer AS touched_sl,
            funnel_base.workable_sl,
            funnel_base.non_workable_sl,
            NULL::integer AS not_pitched_sl,
            NULL::integer AS converted_sl,
            funnel_base.contact_id,
            funnel_base.untouched_flag,
            funnel_base.appointment_created_date,
            funnel_base.appointment_booked_date,
            funnel_base.appointment_utm_medium,
            funnel_base.appointment_utm_source,
            funnel_base.appointment_utm_campaign,
            funnel_base.appointment_utm_content,
            funnel_base.appointment_utm_url,
            funnel_base.is_appointment_completed,
            funnel_base.appointment_completed_date,
            funnel_base.lead_created_date,
            funnel_base.initial_lead_utm_medium,
            funnel_base.initial_lead_utm_source,
            funnel_base.initial_lead_utm_campaign,
            funnel_base.initial_utm_content,
            funnel_base.initial_lead_utm_url,
            funnel_base.repeat_lead_created_date,
            funnel_base.repeat_lead_utm_medium,
            funnel_base.repeat_lead_utm_source,
            funnel_base.repeat_lead_utm_campaign,
            funnel_base.repeat_lead_utm_content,
            funnel_base.repeat_lead_utm_url,
            funnel_base.payment_date_ab,
            funnel_base.subscription_start_date_ab,
            funnel_base.converted_by_counsellor_name,
            funnel_base.converted_by_counsellor_email,
            funnel_base.completed_ontime,
            funnel_base.overdue_appointment,
            funnel_base.active_appointment,
            funnel_base.appointment_booking_flag,
            NULL::character varying AS comment,
            NULL::character varying AS additional_comments,
            NULL::timestamp without time zone AS completed_on
           FROM ( SELECT mu.full_name AS captain_counsellor,
                    ul.contact_id,
                    ab.lead_name,
                    ul.untouched_flag,
                    u.full_name AS counsellor,
                    u.user_id AS counsellor_id,
                    ml.name AS location,
                    l.lead_id,
                    l.created_at,
                    l.updated_at,
                    l.status_id,
                    l.substatus_id,
                    fu.follow_up_status,
                    fu.follow_ups,
                    rll.repeat_lead_date,
                    cl.payment_date,
                    cl.product_name,
                    ab.appointment_created_date,
                    ab.appointment_booked_date,
                    ab.appointment_utm_medium,
                    ab.appointment_utm_source,
                    ab.appointment_utm_campaign,
                    ab.appointment_utm_content,
                    ab.appointment_utm_url,
                    ab.is_appointment_completed,
                    ab.appointment_completed_date,
                    ab.lead_created_date,
                    ab.initial_lead_utm_medium,
                    ab.initial_lead_utm_source,
                    ab.initial_lead_utm_campaign,
                    ab.initial_utm_content,
                    ab.initial_lead_utm_url,
                    ab.repeat_lead_created_date,
                    ab.repeat_lead_utm_medium,
                    ab.repeat_lead_utm_source,
                    ab.repeat_lead_utm_campaign,
                    ab.repeat_lead_utm_content,
                    ab.repeat_lead_utm_url,
                    ab.payment_date_ab,
                    ab.subscription_start_date_ab,
                    ab.converted_by_counsellor_name,
                    ab.converted_by_counsellor_email,
                    ab.completed_ontime,
                    ab.overdue_appointment,
                    ab.active_appointment,
                    ab.workable_sl,
                    ab.non_workable_sl,
                    ab.appointment_booking_flag,
                        CASE
                            WHEN l.substatus_id = ANY (ARRAY[2, 3, 5, 6, 57, 13, 16, 18, 19, 21, 24, 25, 60]) THEN 1
                            ELSE 0
                        END AS workable_untouched,
                        CASE
                            WHEN l.substatus_id = ANY (ARRAY[14, 26, 27, 28, 55, 32, 35, 52, 53]) THEN 1
                            ELSE 0
                        END AS non_workable_untouched,
                    count(
                        CASE
                            WHEN l.status_id = 4 THEN 1
                            ELSE NULL::integer
                        END) AS "INTERESTED",
                    count(
                        CASE
                            WHEN l.substatus_id = 14 AND l.status_id = 4 THEN 1
                            ELSE NULL::integer
                        END) AS warm,
                    count(
                        CASE
                            WHEN l.substatus_id = 13 AND l.status_id = 4 THEN 1
                            ELSE NULL::integer
                        END) AS hot,
                    count(
                        CASE
                            WHEN l.substatus_id = 15 AND l.status_id = 4 THEN 1
                            ELSE NULL::integer
                        END) AS cold,
                    count(
                        CASE
                            WHEN l.substatus_id = 64 AND l.status_id = 4 THEN 1
                            ELSE NULL::integer
                        END) AS work_to_non_work_i,
                    count(
                        CASE
                            WHEN l.status_id = 1 THEN 1
                            ELSE NULL::integer
                        END) AS "NEW LEAD",
                    count(
                        CASE
                            WHEN l.substatus_id = 2 AND l.status_id = 1 THEN 1
                            ELSE NULL::integer
                        END) AS new_lead,
                    count(
                        CASE
                            WHEN l.substatus_id = 62 AND l.status_id = 1 THEN 1
                            ELSE NULL::integer
                        END) AS existing_customer,
                    count(
                        CASE
                            WHEN l.substatus_id = 1 AND l.status_id = 1 THEN 1
                            ELSE NULL::integer
                        END) AS untagged,
                    count(
                        CASE
                            WHEN l.substatus_id = 3 AND l.status_id = 1 THEN 1
                            ELSE NULL::integer
                        END) AS repeat_lead,
                    count(
                        CASE
                            WHEN (l.substatus_id = ANY (ARRAY[5, 6, 7, 57, 58, 59, 65])) AND l.is_active = true THEN 1
                            WHEN (l.substatus_id = ANY (ARRAY[9, 10])) AND COALESCE(l.updated_at, l.created_at)::date >= (CURRENT_DATE - 60) AND l.is_active = true THEN 1
                            ELSE NULL::integer
                        END) AS "CONTACTED",
                    count(
                        CASE
                            WHEN l.substatus_id = 65 AND l.status_id = 2 THEN 1
                            ELSE NULL::integer
                        END) AS work_to_non_work_c,
                    count(
                        CASE
                            WHEN l.substatus_id = 6 AND l.status_id = 2 THEN 1
                            ELSE NULL::integer
                        END) AS pitched,
                    count(
                        CASE
                            WHEN l.substatus_id = 5 AND l.status_id = 2 THEN 1
                            ELSE NULL::integer
                        END) AS not_pitched,
                    count(
                        CASE
                            WHEN l.substatus_id = 7 AND l.status_id = 2 THEN 1
                            ELSE NULL::integer
                        END) AS forwarded,
                    count(
                        CASE
                            WHEN l.substatus_id = 9 AND l.status_id = 2 AND COALESCE(l.updated_at, l.created_at)::date >= (CURRENT_DATE - 60) THEN 1
                            ELSE NULL::integer
                        END) AS language_barrier,
                    count(
                        CASE
                            WHEN l.substatus_id = 10 AND l.status_id = 2 AND COALESCE(l.updated_at, l.created_at)::date >= (CURRENT_DATE - 60) THEN 1
                            ELSE NULL::integer
                        END) AS not_reachable,
                    count(
                        CASE
                            WHEN l.substatus_id = 57 AND l.status_id = 2 THEN 1
                            ELSE NULL::integer
                        END) AS pre_sales_qualified,
                    count(
                        CASE
                            WHEN l.substatus_id = 59 AND l.status_id = 2 THEN 1
                            ELSE NULL::integer
                        END) AS dnd,
                    count(
                        CASE
                            WHEN l.substatus_id = 58 AND l.status_id = 2 THEN 1
                            ELSE NULL::integer
                        END) AS invalid,
                    count(
                        CASE
                            WHEN (l.substatus_id = ANY (ARRAY[56, 61])) AND l.is_active = true THEN 1
                            WHEN l.substatus_id = 11 AND COALESCE(l.updated_at, l.created_at)::date >= (CURRENT_DATE - 60) AND l.is_active = true THEN 1
                            ELSE NULL::integer
                        END) AS "NOT INTERESTED",
                    count(
                        CASE
                            WHEN l.substatus_id = 11 AND l.status_id = 3 AND COALESCE(l.updated_at, l.created_at)::date >= (CURRENT_DATE - 60) THEN 1
                            ELSE NULL::integer
                        END) AS not_interested,
                    count(
                        CASE
                            WHEN l.substatus_id = 56 AND l.status_id = 3 THEN 1
                            ELSE NULL::integer
                        END) AS customer_declined,
                    count(
                        CASE
                            WHEN l.substatus_id = 61 AND l.status_id = 3 THEN 1
                            ELSE NULL::integer
                        END) AS no_progress,
                    count(
                        CASE
                            WHEN l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS "ONBOARDING",
                    count(
                        CASE
                            WHEN l.substatus_id = 55 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS onboarding_closed,
                    count(
                        CASE
                            WHEN l.substatus_id = 16 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS in_process,
                    count(
                        CASE
                            WHEN l.substatus_id = 18 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS mobile_otp_verified,
                    count(
                        CASE
                            WHEN l.substatus_id = 17 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS email_otp_verified,
                    count(
                        CASE
                            WHEN l.substatus_id = 21 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS kra_verified,
                    count(
                        CASE
                            WHEN l.substatus_id = 20 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS ckyc_verified,
                    count(
                        CASE
                            WHEN l.substatus_id = 19 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS pan_verified,
                    count(
                        CASE
                            WHEN l.substatus_id = 22 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS risk_profile,
                    count(
                        CASE
                            WHEN l.substatus_id = 23 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS portfolio_selection,
                    count(
                        CASE
                            WHEN l.substatus_id = 24 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS suitability_assessment,
                    count(
                        CASE
                            WHEN l.substatus_id = 25 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS agreement_signed,
                    count(
                        CASE
                            WHEN l.substatus_id = 26 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS payment_pending,
                    count(
                        CASE
                            WHEN l.substatus_id = 27 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS payment_received,
                    count(
                        CASE
                            WHEN l.substatus_id = 28 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS subscription_started,
                    count(
                        CASE
                            WHEN l.substatus_id = 54 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS payment_adjusted,
                    count(
                        CASE
                            WHEN l.substatus_id = 60 AND l.status_id = 5 THEN 1
                            ELSE NULL::integer
                        END) AS self_kyc_verified,
                    count(
                        CASE
                            WHEN l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS "SUBSCRIPTION",
                    count(
                        CASE
                            WHEN l.substatus_id = 29 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS active,
                    count(
                        CASE
                            WHEN l.substatus_id = 30 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS deactivated_s,
                    count(
                        CASE
                            WHEN l.substatus_id = 32 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS expired,
                    count(
                        CASE
                            WHEN l.substatus_id = 31 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS extended,
                    count(
                        CASE
                            WHEN l.substatus_id = 35 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS refunded,
                    count(
                        CASE
                            WHEN l.substatus_id = 34 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS refund_processing,
                    count(
                        CASE
                            WHEN l.substatus_id = 33 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS refund_requested,
                    count(
                        CASE
                            WHEN l.substatus_id = 36 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS cancelled,
                    count(
                        CASE
                            WHEN l.substatus_id = 53 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS downgraded,
                    count(
                        CASE
                            WHEN l.substatus_id = 52 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS upgraded,
                    count(
                        CASE
                            WHEN l.substatus_id = 71 AND l.status_id = 6 THEN 1
                            ELSE NULL::integer
                        END) AS refund_rejected,
                    count(
                        CASE
                            WHEN l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS "COLLECTIONS",
                    count(
                        CASE
                            WHEN l.substatus_id = 37 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS assigned,
                    count(
                        CASE
                            WHEN l.substatus_id = 38 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS unreachable,
                    count(
                        CASE
                            WHEN l.substatus_id = 40 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS neutral_response,
                    count(
                        CASE
                            WHEN l.substatus_id = 41 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS positive_response,
                    count(
                        CASE
                            WHEN l.substatus_id = 39 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS contacted,
                    count(
                        CASE
                            WHEN l.substatus_id = 42 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS ticket_raised,
                    count(
                        CASE
                            WHEN l.substatus_id = 43 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS payment_link_sent,
                    count(
                        CASE
                            WHEN l.substatus_id = 44 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS payment_collected,
                    count(
                        CASE
                            WHEN l.substatus_id = 46 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS transferred,
                    count(
                        CASE
                            WHEN l.substatus_id = 45 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS transfer_requested,
                    count(
                        CASE
                            WHEN l.substatus_id = 48 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS deactivation_request_rejected,
                    count(
                        CASE
                            WHEN l.substatus_id = 47 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS deactivation_requested,
                    count(
                        CASE
                            WHEN l.substatus_id = 50 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS closed,
                    count(
                        CASE
                            WHEN l.substatus_id = 49 AND l.status_id = 7 THEN 1
                            ELSE NULL::integer
                        END) AS deactivated_c,
                    count(
                        CASE
                            WHEN (l.substatus_id <> ALL (ARRAY[9, 10, 11])) AND l.is_active = true THEN 1
                            WHEN (l.substatus_id = ANY (ARRAY[9, 10, 11])) AND COALESCE(l.updated_at, l.created_at)::date > (CURRENT_DATE - 60) AND l.is_active = true THEN 1
                            ELSE NULL::integer
                        END) AS grand_total
                   FROM ( SELECT cm_1.mapping_id,
                            cm_1.contact_id,
                            cm_1.rm_id,
                            cm_1.type,
                            cm_1.is_transferred,
                            cm_1.reason_id,
                            cm_1.from_date,
                            cm_1.end_date,
                            cm_1.company_id,
                            cm_1.created_at,
                            cm_1.created_by,
                            cm_1.updated_at,
                            cm_1.updated_by,
                            cm_1.lead_id
                           FROM contact_mapping cm_1
                          WHERE cm_1.end_date IS NULL AND cm_1.type = 'Sales'::mapping_type) cm
                     LEFT JOIN lead l ON l.contact_id = cm.contact_id AND l.rm_id = cm.rm_id
                     LEFT JOIN contact c ON l.contact_id = c.contact_id
                     LEFT JOIN mst_user u ON l.rm_id = u.user_id
                     LEFT JOIN mst_status ms ON l.status_id = ms.status_id
                     LEFT JOIN mst_substatus s ON l.substatus_id = s.substatus_id
                     LEFT JOIN mst_location ml ON u.location_id = ml.location_id
                     LEFT JOIN mst_user mu ON u.reporting_manager_id = mu.user_id
                     LEFT JOIN follow_up fu ON l.lead_id = fu.lead_id
                     LEFT JOIN repeat_lead_logic rll ON l.lead_id = rll.lead_id
                     LEFT JOIN converted_leads cl ON l.lead_id = cl.lead_id
                     LEFT JOIN untouched_logic ul ON l.lead_id = ul.lead_id
                     LEFT JOIN appointment_book ab ON l.lead_id = ab.lead_id
                  GROUP BY u.full_name, u.user_id, mu.full_name, ml.name, l.lead_id, ab.lead_name, l.created_at, l.updated_at, l.status_id, l.substatus_id, fu.follow_up_status, fu.follow_ups, rll.repeat_lead_date, cl.payment_date, cl.product_name, ul.contact_id, ul.untouched_flag, ab.appointment_created_date, ab.appointment_booked_date, ab.appointment_utm_medium, ab.appointment_utm_source, ab.appointment_utm_campaign, ab.appointment_utm_content, ab.appointment_utm_url, ab.is_appointment_completed, ab.appointment_completed_date, ab.lead_created_date, ab.initial_lead_utm_medium, ab.initial_lead_utm_source, ab.initial_lead_utm_campaign, ab.initial_utm_content, ab.initial_lead_utm_url, ab.repeat_lead_created_date, ab.repeat_lead_utm_medium, ab.repeat_lead_utm_source, ab.repeat_lead_utm_campaign, ab.repeat_lead_utm_content, ab.repeat_lead_utm_url, ab.payment_date_ab, ab.subscription_start_date_ab, ab.converted_by_counsellor_name, ab.converted_by_counsellor_email, ab.completed_ontime, ab.overdue_appointment, ab.active_appointment, ab.workable_sl, ab.non_workable_sl, ab.appointment_booking_flag) funnel_base
        UNION ALL
         SELECT NULL::integer AS lead_id,
            login_log.login_date AS report_date,
            login_log.login_date AS refresh_date,
            NULL::timestamp with time zone AS new_lead_count_date,
            NULL::character varying AS captain_counsellor,
            login_log.rm_name AS counsellor,
            login_log.user_id AS counsellor_id,
            login_log.location,
            NULL::double precision AS call_duration,
            NULL::bigint AS "Called",
            NULL::bigint AS "Had a Phone Conversation",
            NULL::bigint AS "Detailed Conversation",
            NULL::text AS "Talktime",
            NULL::bigint AS "Notes - Not Answered",
            NULL::bigint AS "Notes - Detail conversation-Sales Pitch",
            NULL::bigint AS "Notes - Detail Conversation",
            NULL::bigint AS "Notes - Had a Phone Conversation",
            NULL::bigint AS "Call - Not Answered",
            NULL::bigint AS "Call - Detail conversation-Sales Pitch",
            NULL::bigint AS "Call - Detail Conversation",
            NULL::bigint AS "Call - Had a Phone Conversation",
            NULL::character varying AS group_name,
            NULL::character varying AS short_name,
            NULL::integer AS detailed_conversation_flag,
            NULL::bigint AS "Total Calls",
            NULL::bigint AS "INTERESTED",
            NULL::bigint AS warm,
            NULL::bigint AS hot,
            NULL::bigint AS cold,
            NULL::bigint AS work_to_non_work_i,
            NULL::bigint AS "NEW LEAD",
            NULL::bigint AS new_lead,
            NULL::bigint AS existing_customer,
            NULL::bigint AS untagged,
            NULL::bigint AS repeat_lead,
            NULL::bigint AS "CONTACTED",
            NULL::bigint AS work_to_non_work_c,
            NULL::bigint AS pitched,
            NULL::bigint AS not_pitched,
            NULL::bigint AS forwarded,
            NULL::bigint AS language_barrier,
            NULL::bigint AS not_reachable,
            NULL::bigint AS pre_sales_qualified,
            NULL::bigint AS dnd,
            NULL::bigint AS invalid,
            NULL::bigint AS "NOT INTERESTED",
            NULL::bigint AS not_interested,
            NULL::bigint AS customer_declined,
            NULL::bigint AS no_progress,
            NULL::bigint AS "ONBOARDING",
            NULL::bigint AS onboarding_closed,
            NULL::bigint AS in_process,
            NULL::bigint AS mobile_otp_verified,
            NULL::bigint AS email_otp_verified,
            NULL::bigint AS kra_verified,
            NULL::bigint AS ckyc_verified,
            NULL::bigint AS pan_verified,
            NULL::bigint AS risk_profile,
            NULL::bigint AS portfolio_selection,
            NULL::bigint AS suitability_assessment,
            NULL::bigint AS agreement_signed,
            NULL::bigint AS payment_pending,
            NULL::bigint AS payment_received,
            NULL::bigint AS subscription_started,
            NULL::bigint AS payment_adjusted,
            NULL::bigint AS self_kyc_verified,
            NULL::bigint AS "SUBSCRIPTION",
            NULL::bigint AS active,
            NULL::bigint AS deactivated_s,
            NULL::bigint AS expired,
            NULL::bigint AS extended,
            NULL::bigint AS refunded,
            NULL::bigint AS refund_processing,
            NULL::bigint AS refund_requested,
            NULL::bigint AS cancelled,
            NULL::bigint AS downgraded,
            NULL::bigint AS upgraded,
            NULL::bigint AS refund_rejected,
            NULL::bigint AS "COLLECTIONS",
            NULL::bigint AS assigned,
            NULL::bigint AS unreachable,
            NULL::bigint AS neutral_response,
            NULL::bigint AS positive_response,
            NULL::bigint AS contacted,
            NULL::bigint AS ticket_raised,
            NULL::bigint AS payment_link_sent,
            NULL::bigint AS payment_collected,
            NULL::bigint AS transferred,
            NULL::bigint AS transfer_requested,
            NULL::bigint AS deactivation_request_rejected,
            NULL::bigint AS deactivation_requested,
            NULL::bigint AS closed,
            NULL::bigint AS deactivated_c,
            NULL::bigint AS grand_total,
            NULL::character varying AS lead_status,
            NULL::character varying AS lead_substatus,
            NULL::text AS follow_up_status,
            NULL::integer AS follow_ups,
            login_log.login_time,
            login_log.logout_time,
            NULL::integer AS converted,
            NULL::integer AS conversion_count,
            NULL::integer AS arpa_amount,
            NULL::integer AS arft_amount,
            NULL::integer AS emandate_count,
            NULL::integer AS cash_flow_amount,
            NULL::integer AS cash_flow_count,
            NULL::timestamp with time zone AS repeat_lead_date,
            NULL::integer AS activity_count_flag,
            NULL::timestamp without time zone AS payment_date,
            NULL::character varying AS product_name,
            'Login Log'::text AS "Flag",
            NULL::integer AS workable_untouched,
            NULL::integer AS non_workable_untouched,
            NULL::character varying AS lead_name,
            NULL::character varying AS lead_mobile,
            NULL::character varying AS lead_email,
            NULL::character varying AS product,
            NULL::character varying AS sub_product,
            NULL::character varying AS utm_medium,
            NULL::character varying AS utm_source,
            NULL::character varying AS utm_campaign,
            NULL::character varying AS utm_content,
            NULL::character varying AS utm_url,
            NULL::character varying AS initially_taken_by,
            NULL::character varying AS initially_taken_by_location,
            NULL::smallint AS status_id_sl,
            NULL::smallint AS substatus_id_sl,
            NULL::timestamp with time zone AS created_at_sl,
            NULL::integer AS log_id,
            NULL::integer AS touched,
            NULL::integer AS workable,
            NULL::integer AS non_workable,
            NULL::integer AS touched_sl,
            NULL::integer AS workable_sl,
            NULL::integer AS non_workable_sl,
            NULL::integer AS not_pitched_sl,
            NULL::integer AS converted_sl,
            NULL::integer AS contact_id,
            NULL::integer AS untouched_flag,
            NULL::timestamp with time zone AS appointment_created_date,
            NULL::timestamp with time zone AS appointment_booked_date,
            NULL::text AS appointment_utm_medium,
            NULL::text AS appointment_utm_source,
            NULL::text AS appointment_utm_campaign,
            NULL::text AS appointment_utm_content,
            NULL::text AS appointment_utm_url,
            NULL::integer AS is_appointment_completed,
            NULL::timestamp with time zone AS appointment_completed_date,
            NULL::timestamp with time zone AS lead_created_date,
            NULL::character varying AS initial_lead_utm_medium,
            NULL::character varying AS initial_lead_utm_source,
            NULL::character varying AS initial_lead_utm_campaign,
            NULL::character varying AS initial_utm_content,
            NULL::text AS initial_lead_utm_url,
            NULL::timestamp with time zone AS repeat_lead_created_date,
            NULL::character varying AS repeat_lead_utm_medium,
            NULL::character varying AS repeat_lead_utm_source,
            NULL::character varying AS repeat_lead_utm_campaign,
            NULL::character varying AS repeat_lead_utm_content,
            NULL::text AS repeat_lead_utm_url,
            NULL::text AS payment_date_ab,
            NULL::text AS subscription_start_date_ab,
            NULL::character varying AS converted_by_counsellor_name,
            NULL::character varying AS converted_by_counsellor_email,
            NULL::bigint AS completed_ontime,
            NULL::bigint AS overdue_appointment,
            NULL::bigint AS active_appointment,
            NULL::integer AS appointment_booking_flag,
            NULL::character varying AS comment,
            NULL::character varying AS additional_comments,
            NULL::timestamp without time zone AS completed_on
           FROM ( SELECT (ull.log_time AT TIME ZONE 'Asia/Kolkata'::text)::date AS login_date,
                    ull.user_id,
                    mu.full_name AS rm_name,
                    ml.name AS location,
                    min(to_char((ull.log_time AT TIME ZONE 'Asia/Kolkata'::text), 'dd-MM-yyyy HH24:MI:SS'::text)) AS login_time,
                    max(to_char((ull.log_time AT TIME ZONE 'Asia/Kolkata'::text), 'dd-MM-yyyy HH24:MI:SS'::text)) AS logout_time
                   FROM user_login_log ull
                     JOIN mst_user mu ON ull.user_id = mu.user_id AND mu.sip_number IS NOT NULL
                     LEFT JOIN mst_location ml ON mu.location_id = ml.location_id
                  GROUP BY ((ull.log_time AT TIME ZONE 'Asia/Kolkata'::text)::date), ull.user_id, ml.name, mu.full_name
                  ORDER BY ((ull.log_time AT TIME ZONE 'Asia/Kolkata'::text)::date) DESC, mu.full_name) login_log
        UNION ALL
         SELECT NULL::integer AS lead_id,
            target.start_date AS report_date,
            target.created_at AS refresh_date,
            NULL::timestamp with time zone AS new_lead_count_date,
            NULL::character varying AS captain_counsellor,
            NULL::character varying AS counsellor,
            target.rm_id AS counsellor_id,
            NULL::character varying AS location,
            NULL::double precision AS call_duration,
            NULL::bigint AS "Called",
            NULL::bigint AS "Had a Phone Conversation",
            NULL::bigint AS "Detailed Conversation",
            NULL::text AS "Talktime",
            NULL::bigint AS "Notes - Not Answered",
            NULL::bigint AS "Notes - Detail conversation-Sales Pitch",
            NULL::bigint AS "Notes - Detail Conversation",
            NULL::bigint AS "Notes - Had a Phone Conversation",
            NULL::bigint AS "Call - Not Answered",
            NULL::bigint AS "Call - Detail conversation-Sales Pitch",
            NULL::bigint AS "Call - Detail Conversation",
            NULL::bigint AS "Call - Had a Phone Conversation",
            NULL::character varying AS group_name,
            NULL::character varying AS short_name,
            NULL::integer AS detailed_conversation_flag,
            NULL::bigint AS "Total Calls",
            NULL::bigint AS "INTERESTED",
            NULL::bigint AS warm,
            NULL::bigint AS hot,
            NULL::bigint AS cold,
            NULL::bigint AS work_to_non_work_i,
            NULL::bigint AS "NEW LEAD",
            NULL::bigint AS new_lead,
            NULL::bigint AS existing_customer,
            NULL::bigint AS untagged,
            NULL::bigint AS repeat_lead,
            NULL::bigint AS "CONTACTED",
            NULL::bigint AS work_to_non_work_c,
            NULL::bigint AS pitched,
            NULL::bigint AS not_pitched,
            NULL::bigint AS forwarded,
            NULL::bigint AS language_barrier,
            NULL::bigint AS not_reachable,
            NULL::bigint AS pre_sales_qualified,
            NULL::bigint AS dnd,
            NULL::bigint AS invalid,
            NULL::bigint AS "NOT INTERESTED",
            NULL::bigint AS not_interested,
            NULL::bigint AS customer_declined,
            NULL::bigint AS no_progress,
            NULL::bigint AS "ONBOARDING",
            NULL::bigint AS onboarding_closed,
            NULL::bigint AS in_process,
            NULL::bigint AS mobile_otp_verified,
            NULL::bigint AS email_otp_verified,
            NULL::bigint AS kra_verified,
            NULL::bigint AS ckyc_verified,
            NULL::bigint AS pan_verified,
            NULL::bigint AS risk_profile,
            NULL::bigint AS portfolio_selection,
            NULL::bigint AS suitability_assessment,
            NULL::bigint AS agreement_signed,
            NULL::bigint AS payment_pending,
            NULL::bigint AS payment_received,
            NULL::bigint AS subscription_started,
            NULL::bigint AS payment_adjusted,
            NULL::bigint AS self_kyc_verified,
            NULL::bigint AS "SUBSCRIPTION",
            NULL::bigint AS active,
            NULL::bigint AS deactivated_s,
            NULL::bigint AS expired,
            NULL::bigint AS extended,
            NULL::bigint AS refunded,
            NULL::bigint AS refund_processing,
            NULL::bigint AS refund_requested,
            NULL::bigint AS cancelled,
            NULL::bigint AS downgraded,
            NULL::bigint AS upgraded,
            NULL::bigint AS refund_rejected,
            NULL::bigint AS "COLLECTIONS",
            NULL::bigint AS assigned,
            NULL::bigint AS unreachable,
            NULL::bigint AS neutral_response,
            NULL::bigint AS positive_response,
            NULL::bigint AS contacted,
            NULL::bigint AS ticket_raised,
            NULL::bigint AS payment_link_sent,
            NULL::bigint AS payment_collected,
            NULL::bigint AS transferred,
            NULL::bigint AS transfer_requested,
            NULL::bigint AS deactivation_request_rejected,
            NULL::bigint AS deactivation_requested,
            NULL::bigint AS closed,
            NULL::bigint AS deactivated_c,
            NULL::bigint AS grand_total,
            NULL::character varying AS lead_status,
            NULL::character varying AS lead_substatus,
            NULL::text AS follow_up_status,
            NULL::integer AS follow_ups,
            NULL::text AS login_time,
            NULL::text AS logout_time,
            NULL::integer AS converted,
            NULL::integer AS conversion_count,
            NULL::integer AS arpa_amount,
            NULL::integer AS arft_amount,
            NULL::integer AS emandate_count,
            NULL::integer AS cash_flow_amount,
            NULL::integer AS cash_flow_count,
            NULL::timestamp with time zone AS repeat_lead_date,
            NULL::integer AS activity_count_flag,
            NULL::timestamp without time zone AS payment_date,
            NULL::character varying AS product_name,
            'Target'::text AS "Flag",
            NULL::integer AS workable_untouched,
            NULL::integer AS non_workable_untouched,
            NULL::character varying AS lead_name,
            NULL::character varying AS lead_mobile,
            NULL::character varying AS lead_email,
            NULL::character varying AS product,
            NULL::character varying AS sub_product,
            NULL::character varying AS utm_medium,
            NULL::character varying AS utm_source,
            NULL::character varying AS utm_campaign,
            NULL::character varying AS utm_content,
            NULL::character varying AS utm_url,
            NULL::character varying AS initially_taken_by,
            NULL::character varying AS initially_taken_by_location,
            NULL::smallint AS status_id_sl,
            NULL::smallint AS substatus_id_sl,
            NULL::timestamp with time zone AS created_at_sl,
            NULL::integer AS log_id,
            NULL::integer AS touched,
            NULL::integer AS workable,
            NULL::integer AS non_workable,
            NULL::integer AS touched_sl,
            NULL::integer AS workable_sl,
            NULL::integer AS non_workable_sl,
            NULL::integer AS not_pitched_sl,
            NULL::integer AS converted_sl,
            NULL::integer AS contact_id,
            NULL::integer AS untouched_flag,
            NULL::timestamp with time zone AS appointment_created_date,
            NULL::timestamp with time zone AS appointment_booked_date,
            NULL::text AS appointment_utm_medium,
            NULL::text AS appointment_utm_source,
            NULL::text AS appointment_utm_campaign,
            NULL::text AS appointment_utm_content,
            NULL::text AS appointment_utm_url,
            NULL::integer AS is_appointment_completed,
            NULL::timestamp with time zone AS appointment_completed_date,
            NULL::timestamp with time zone AS lead_created_date,
            NULL::character varying AS initial_lead_utm_medium,
            NULL::character varying AS initial_lead_utm_source,
            NULL::character varying AS initial_lead_utm_campaign,
            NULL::character varying AS initial_utm_content,
            NULL::text AS initial_lead_utm_url,
            NULL::timestamp with time zone AS repeat_lead_created_date,
            NULL::character varying AS repeat_lead_utm_medium,
            NULL::character varying AS repeat_lead_utm_source,
            NULL::character varying AS repeat_lead_utm_campaign,
            NULL::character varying AS repeat_lead_utm_content,
            NULL::text AS repeat_lead_utm_url,
            NULL::text AS payment_date_ab,
            NULL::text AS subscription_start_date_ab,
            NULL::character varying AS converted_by_counsellor_name,
            NULL::character varying AS converted_by_counsellor_email,
            NULL::bigint AS completed_ontime,
            NULL::bigint AS overdue_appointment,
            NULL::bigint AS active_appointment,
            NULL::integer AS appointment_booking_flag,
            NULL::character varying AS comment,
            NULL::character varying AS additional_comments,
            NULL::timestamp without time zone AS completed_on
           FROM ( SELECT target_management.rm_id,
                    target_management.created_at,
                    target_management.start_date,
                    target_management.conversion_count,
                    target_management.arpa_amount,
                    target_management.arft_amount,
                    target_management.emandate_count,
                    target_management.cash_flow_amount,
                    target_management.cash_flow_count
                   FROM target_management) target
        UNION ALL
         SELECT lqr.lead_id,
            lqr.lead_created_date AS report_date,
            lqr.lead_created_date AS refresh_date,
            lqr.updated_at_s AS new_lead_count_date,
            NULL::character varying AS captain_counsellor,
            lqr.counsellor,
            lqr.counsellor_id,
            lqr.location,
            NULL::double precision AS call_duration,
            NULL::bigint AS "Called",
            NULL::bigint AS "Had a Phone Conversation",
            NULL::bigint AS "Detailed Conversation",
            NULL::text AS "Talktime",
            NULL::bigint AS "Notes - Not Answered",
            NULL::bigint AS "Notes - Detail conversation-Sales Pitch",
            NULL::bigint AS "Notes - Detail Conversation",
            NULL::bigint AS "Notes - Had a Phone Conversation",
            NULL::bigint AS "Call - Not Answered",
            NULL::bigint AS "Call - Detail conversation-Sales Pitch",
            NULL::bigint AS "Call - Detail Conversation",
            NULL::bigint AS "Call - Had a Phone Conversation",
            NULL::character varying AS group_name,
            NULL::character varying AS short_name,
            NULL::integer AS detailed_conversation_flag,
            NULL::bigint AS "Total Calls",
            NULL::bigint AS "INTERESTED",
            NULL::bigint AS warm,
            NULL::bigint AS hot,
            NULL::bigint AS cold,
            NULL::bigint AS work_to_non_work_i,
            NULL::bigint AS "NEW LEAD",
            NULL::bigint AS new_lead,
            NULL::bigint AS existing_customer,
            NULL::bigint AS untagged,
            NULL::bigint AS repeat_lead,
            NULL::bigint AS "CONTACTED",
            NULL::bigint AS work_to_non_work_c,
            NULL::bigint AS pitched,
            lqr.not_pitched::bigint AS not_pitched,
            NULL::bigint AS forwarded,
            NULL::bigint AS language_barrier,
            NULL::bigint AS not_reachable,
            NULL::bigint AS pre_sales_qualified,
            NULL::bigint AS dnd,
            NULL::bigint AS invalid,
            NULL::bigint AS "NOT INTERESTED",
            NULL::bigint AS not_interested,
            NULL::bigint AS customer_declined,
            NULL::bigint AS no_progress,
            NULL::bigint AS "ONBOARDING",
            NULL::bigint AS onboarding_closed,
            NULL::bigint AS in_process,
            NULL::bigint AS mobile_otp_verified,
            NULL::bigint AS email_otp_verified,
            NULL::bigint AS kra_verified,
            NULL::bigint AS ckyc_verified,
            NULL::bigint AS pan_verified,
            NULL::bigint AS risk_profile,
            NULL::bigint AS portfolio_selection,
            NULL::bigint AS suitability_assessment,
            NULL::bigint AS agreement_signed,
            NULL::bigint AS payment_pending,
            NULL::bigint AS payment_received,
            NULL::bigint AS subscription_started,
            NULL::bigint AS payment_adjusted,
            NULL::bigint AS self_kyc_verified,
            NULL::bigint AS "SUBSCRIPTION",
            NULL::bigint AS active,
            NULL::bigint AS deactivated_s,
            NULL::bigint AS expired,
            NULL::bigint AS extended,
            NULL::bigint AS refunded,
            NULL::bigint AS refund_processing,
            NULL::bigint AS refund_requested,
            NULL::bigint AS cancelled,
            NULL::bigint AS downgraded,
            NULL::bigint AS upgraded,
            NULL::bigint AS refund_rejected,
            NULL::bigint AS "COLLECTIONS",
            NULL::bigint AS assigned,
            NULL::bigint AS unreachable,
            NULL::bigint AS neutral_response,
            NULL::bigint AS positive_response,
            NULL::bigint AS contacted,
            NULL::bigint AS ticket_raised,
            NULL::bigint AS payment_link_sent,
            NULL::bigint AS payment_collected,
            NULL::bigint AS transferred,
            NULL::bigint AS transfer_requested,
            NULL::bigint AS deactivation_request_rejected,
            NULL::bigint AS deactivation_requested,
            NULL::bigint AS closed,
            NULL::bigint AS deactivated_c,
            NULL::bigint AS grand_total,
            lqr.lead_status,
            lqr.lead_substatus,
            NULL::text AS follow_up_status,
            NULL::integer AS follow_ups,
            NULL::text AS login_time,
            NULL::text AS logout_time,
            lqr.converted,
            NULL::integer AS conversion_count,
            NULL::integer AS arpa_amount,
            NULL::integer AS arft_amount,
            NULL::integer AS emandate_count,
            NULL::integer AS cash_flow_amount,
            NULL::integer AS cash_flow_count,
            NULL::timestamp with time zone AS repeat_lead_date,
            NULL::integer AS activity_count_flag,
            NULL::timestamp with time zone AS payment_date,
            NULL::character varying AS product_name,
            'LQR'::text AS "Flag",
            NULL::integer AS workable_untouched,
            NULL::integer AS non_workable_untouched,
            lqr.lead_name,
            lqr.lead_mobile,
            lqr.lead_email,
            lqr.product,
            lqr.sub_product,
            lqr.utm_medium,
            lqr.utm_source,
            lqr.utm_campaign,
            lqr.utm_content,
            lqr.utm_url,
            lqr.initially_taken_by,
            lqr.initially_taken_by_location,
            lqr.status_id_sl,
            lqr.substatus_id_sl,
            lqr.created_at_sl,
            lqr.log_id,
            lqr.touched,
            lqr.workable,
            lqr.non_workable,
            lqr.touched_sl,
            lqr.workable_sl,
            lqr.non_workable_sl,
            lqr.not_pitched_sl,
            lqr.converted_sl,
            NULL::integer AS contact_id,
            NULL::integer AS untouched_flag,
            NULL::timestamp with time zone AS appointment_created_date,
            NULL::timestamp with time zone AS appointment_booked_date,
            NULL::text AS appointment_utm_medium,
            NULL::text AS appointment_utm_source,
            NULL::text AS appointment_utm_campaign,
            NULL::text AS appointment_utm_content,
            NULL::text AS appointment_utm_url,
            NULL::integer AS is_appointment_completed,
            NULL::timestamp with time zone AS appointment_completed_date,
            NULL::timestamp with time zone AS lead_created_date,
            NULL::character varying AS initial_lead_utm_medium,
            NULL::character varying AS initial_lead_utm_source,
            NULL::character varying AS initial_lead_utm_campaign,
            NULL::character varying AS initial_utm_content,
            NULL::text AS initial_lead_utm_url,
            NULL::timestamp with time zone AS repeat_lead_created_date,
            NULL::character varying AS repeat_lead_utm_medium,
            NULL::character varying AS repeat_lead_utm_source,
            NULL::character varying AS repeat_lead_utm_campaign,
            NULL::character varying AS repeat_lead_utm_content,
            NULL::text AS repeat_lead_utm_url,
            NULL::text AS payment_date_ab,
            NULL::text AS subscription_start_date_ab,
            NULL::character varying AS converted_by_counsellor_name,
            NULL::character varying AS converted_by_counsellor_email,
            NULL::bigint AS completed_ontime,
            NULL::bigint AS overdue_appointment,
            NULL::bigint AS active_appointment,
            NULL::integer AS appointment_booking_flag,
            NULL::character varying AS comment,
            NULL::character varying AS additional_comments,
            NULL::timestamp without time zone AS completed_on
           FROM ( WITH new_leads AS (
                         SELECT lll.lead_id,
                            sl.created_at,
                            lll.contact_id,
                            lll.utm_source,
                            lll.utm_medium,
                            lll.utm_campaign,
                            lll.utm_content,
                            lll.page_url,
                            sl.rm_id,
                            sl.status_id AS status_id_sl,
                            sl.substatus_id AS substatus_id_sl,
                            sl.created_at AS created_at_sl,
                            sl.updated_at AS updated_at_s,
                            lll.lead_raw_id
                           FROM lead lll
                             LEFT JOIN status_log sl ON lll.lead_id = sl.lead_id AND (sl.substatus_id = ANY (ARRAY[1, 2, 3]))
                        ), initial_taken_by AS (
                         SELECT DISTINCT ON (pcm.lead_id) pcm.lead_id,
                            pcm.is_taken,
                            pcm.rm_id,
                            pcm.location_id
                           FROM pool_contact_mapping pcm
                             JOIN new_leads nl_1 ON nl_1.lead_id = pcm.lead_id
                          ORDER BY pcm.lead_id, pcm.pool_mapping_id
                        ), till_date_lead AS (
                         SELECT t_1.lead_id,
                            t_1.rm_id,
                            t_1.status_id,
                            t_1.created_at,
                            t_1.log_timestamp,
                            t_1.log_id,
                            t_1.substatus_id,
                            t_1.product_id,
                            t_1.sub_product_ids
                           FROM lead_log t_1
                        ), initial_lead_utm AS (
                         SELECT l.lead_id,
                            l.created_at,
                                CASE
                                    WHEN lr.lead_raw_id IS NOT NULL THEN lr.utm_source
                                    ELSE l.utm_source
                                END AS utm_source,
                                CASE
                                    WHEN lr.lead_raw_id IS NOT NULL THEN lr.utm_campaign
                                    ELSE l.utm_campaign
                                END AS utm_campaign,
                                CASE
                                    WHEN lr.lead_raw_id IS NOT NULL THEN lr.utm_medium
                                    ELSE l.utm_medium
                                END AS utm_medium,
                                CASE
                                    WHEN lr.lead_raw_id IS NOT NULL THEN lr.utm_content
                                    ELSE l.utm_content
                                END AS utm_content,
                                CASE
                                    WHEN lr.lead_raw_id IS NOT NULL THEN lr.page_url::text
                                    ELSE l.page_url
                                END AS page_url
                           FROM lead l
                             LEFT JOIN lead_raw lr ON lr.lead_raw_id = l.lead_raw_id
                        )
                 SELECT nl.created_at AS lead_created_date,
                    nl.lead_id,
                    c.full_name AS lead_name,
                    c.mobile_number AS lead_mobile,
                    c.email_address AS lead_email,
                    ms3.code AS product,
                    ms4.code AS sub_product,
                    nl.utm_medium,
                    nl.utm_source,
                    nl.utm_campaign,
                    nl.utm_content,
                    nl.page_url AS utm_url,
                    COALESCE(ml.name, ml2.name) AS location,
                    mu.user_id AS counsellor_id,
                    mu.full_name AS counsellor,
                    mu2.full_name AS initially_taken_by,
                    ml2.name AS initially_taken_by_location,
                    ms.name AS lead_status,
                    ms2.name AS lead_substatus,
                    nl.status_id_sl,
                    nl.substatus_id_sl,
                    t.log_timestamp AS created_at_sl,
                    t.log_id,
                    nl.updated_at_s,
                        CASE
                            WHEN t.substatus_id <> ALL (ARRAY[1, 2, 3]) THEN 1
                            ELSE 0
                        END AS touched,
                        CASE
                            WHEN t.substatus_id = ANY (ARRAY[6, 7, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 54, 55, 57, 60]) THEN 1
                            ELSE 0
                        END AS workable,
                        CASE
                            WHEN t.substatus_id = ANY (ARRAY[9, 10, 11, 15, 56, 58, 59, 61, 64, 65]) THEN 1
                            ELSE 0
                        END AS non_workable,
                        CASE
                            WHEN t.substatus_id = 5 THEN 1
                            ELSE 0
                        END AS not_pitched,
                        CASE
                            WHEN t.substatus_id = ANY (ARRAY[29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 52, 53, 71]) THEN 1
                            ELSE 0
                        END AS converted,
                        CASE
                            WHEN nl.substatus_id_sl <> ALL (ARRAY[1, 2, 3]) THEN 1
                            ELSE 0
                        END AS touched_sl,
                        CASE
                            WHEN nl.substatus_id_sl = ANY (ARRAY[6, 7, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 54, 55, 57, 60]) THEN 1
                            ELSE 0
                        END AS workable_sl,
                        CASE
                            WHEN nl.substatus_id_sl = ANY (ARRAY[9, 10, 11, 15, 56, 58, 59, 61, 64, 65]) THEN 1
                            ELSE 0
                        END AS non_workable_sl,
                        CASE
                            WHEN nl.substatus_id_sl = 5 THEN 1
                            ELSE 0
                        END AS not_pitched_sl,
                        CASE
                            WHEN nl.substatus_id_sl = ANY (ARRAY[29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 52, 53, 71]) THEN 1
                            ELSE 0
                        END AS converted_sl,
                    'LQR'::text AS flag
                   FROM new_leads nl
                     LEFT JOIN contact c ON c.contact_id = nl.contact_id
                     LEFT JOIN initial_lead_utm ilu ON ilu.lead_id = nl.lead_id
                     LEFT JOIN till_date_lead t ON t.lead_id = nl.lead_id
                     LEFT JOIN mst_user mu ON mu.user_id = t.rm_id
                     LEFT JOIN mst_location ml ON ml.location_id = mu.location_id
                     LEFT JOIN initial_taken_by pcml ON pcml.lead_id = nl.lead_id
                     LEFT JOIN mst_user mu2 ON mu2.user_id = pcml.rm_id
                     LEFT JOIN mst_location ml2 ON ml2.location_id = pcml.location_id
                     LEFT JOIN mst_status ms ON ms.status_id = t.status_id
                     LEFT JOIN mst_substatus ms2 ON ms2.substatus_id = t.substatus_id
                     LEFT JOIN mst_product ms3 ON ms3.product_id = t.product_id
                     LEFT JOIN mst_subproduct ms4 ON ms4.sub_product_id = t.sub_product_ids[array_length(t.sub_product_ids, 1)]) lqr
        UNION ALL
        ( WITH reasons AS (
                 SELECT sl.created_at,
                    sl.updated_at,
                    sl.lead_id,
                    sl.contact_id,
                    mc.name AS comment,
                    t.additional_comments,
                    mu.full_name AS counsellor,
                    mu.user_id AS counsellor_id,
                    ml.name AS location
                   FROM ( SELECT sl_1.status_log_id,
                            sl_1.company_id,
                            sl_1.lead_id,
                            sl_1.contact_id,
                            sl_1.customer_id,
                            sl_1.sub_product_id,
                            sl_1.status_id,
                            sl_1.substatus_id,
                            sl_1.reason_id,
                            sl_1.rm_id,
                            sl_1.location_id,
                            sl_1.department_id,
                            sl_1.reporting_manager_id,
                            sl_1.team_id,
                            sl_1.is_credit_sharing,
                            sl_1.reference_table,
                            sl_1.reference_id,
                            sl_1.additional_info,
                            sl_1.created_at,
                            sl_1.created_by,
                            sl_1.updated_at,
                            sl_1.updated_by,
                            sl_1.onboarding_id
                           FROM status_log sl_1
                          WHERE sl_1.substatus_id = ANY (ARRAY[10, 11, 15, 56, 58, 59, 61, 64, 65])) sl
                     LEFT JOIN ( SELECT sl_1.activity_id,
                            sl_1.comment_ids,
                            sl_1.additional_comments,
                            sl_1.lead_id,
                            sl_1.status_id,
                            sl_1.substatus_id,
                            sl_1.contact_id,
                            sl_1.created_by AS rm_id,
                            sl_1.created_at
                           FROM activity sl_1
                          WHERE (sl_1.substatus_id = ANY (ARRAY[10, 11, 15, 56, 58, 59, 61, 64, 65])) AND sl_1.created_by <> 1 AND (sl_1.activity_type_id = ANY (ARRAY[1, 7]))) t ON t.lead_id = sl.lead_id AND t.created_at >= date_trunc('day'::text, sl.created_at) AND t.created_at < (date_trunc('day'::text, sl.created_at) + '1 day'::interval) AND sl.rm_id = t.rm_id AND t.status_id = sl.status_id AND t.substatus_id = sl.substatus_id
                     LEFT JOIN mst_comment mc ON mc.comment_id = ANY (t.comment_ids)
                     LEFT JOIN mst_user mu ON mu.user_id = sl.rm_id
                     LEFT JOIN mst_location ml ON ml.location_id = mu.location_id
                )
         SELECT reasons.lead_id,
            reasons.created_at AS report_date,
            reasons.created_at AS refresh_date,
            reasons.updated_at AS new_lead_count_date,
            NULL::character varying AS captain_counsellor,
            reasons.counsellor,
            reasons.counsellor_id,
            reasons.location,
            NULL::double precision AS call_duration,
            NULL::bigint AS "Called",
            NULL::bigint AS "Had a Phone Conversation",
            NULL::bigint AS "Detailed Conversation",
            NULL::text AS "Talktime",
            NULL::bigint AS "Notes - Not Answered",
            NULL::bigint AS "Notes - Detail conversation-Sales Pitch",
            NULL::bigint AS "Notes - Detail Conversation",
            NULL::bigint AS "Notes - Had a Phone Conversation",
            NULL::bigint AS "Call - Not Answered",
            NULL::bigint AS "Call - Detail conversation-Sales Pitch",
            NULL::bigint AS "Call - Detail Conversation",
            NULL::bigint AS "Call - Had a Phone Conversation",
            NULL::character varying AS group_name,
            NULL::character varying AS short_name,
            NULL::integer AS detailed_conversation_flag,
            NULL::bigint AS "Total Calls",
            NULL::bigint AS "INTERESTED",
            NULL::bigint AS warm,
            NULL::bigint AS hot,
            NULL::bigint AS cold,
            NULL::bigint AS work_to_non_work_i,
            NULL::bigint AS "NEW LEAD",
            NULL::bigint AS new_lead,
            NULL::bigint AS existing_customer,
            NULL::bigint AS untagged,
            NULL::bigint AS repeat_lead,
            NULL::bigint AS "CONTACTED",
            NULL::bigint AS work_to_non_work_c,
            NULL::bigint AS pitched,
            NULL::bigint AS not_pitched,
            NULL::bigint AS forwarded,
            NULL::bigint AS language_barrier,
            NULL::bigint AS not_reachable,
            NULL::bigint AS pre_sales_qualified,
            NULL::bigint AS dnd,
            NULL::bigint AS invalid,
            NULL::bigint AS "NOT INTERESTED",
            NULL::bigint AS not_interested,
            NULL::bigint AS customer_declined,
            NULL::bigint AS no_progress,
            NULL::bigint AS "ONBOARDING",
            NULL::bigint AS onboarding_closed,
            NULL::bigint AS in_process,
            NULL::bigint AS mobile_otp_verified,
            NULL::bigint AS email_otp_verified,
            NULL::bigint AS kra_verified,
            NULL::bigint AS ckyc_verified,
            NULL::bigint AS pan_verified,
            NULL::bigint AS risk_profile,
            NULL::bigint AS portfolio_selection,
            NULL::bigint AS suitability_assessment,
            NULL::bigint AS agreement_signed,
            NULL::bigint AS payment_pending,
            NULL::bigint AS payment_received,
            NULL::bigint AS subscription_started,
            NULL::bigint AS payment_adjusted,
            NULL::bigint AS self_kyc_verified,
            NULL::bigint AS "SUBSCRIPTION",
            NULL::bigint AS active,
            NULL::bigint AS deactivated_s,
            NULL::bigint AS expired,
            NULL::bigint AS extended,
            NULL::bigint AS refunded,
            NULL::bigint AS refund_processing,
            NULL::bigint AS refund_requested,
            NULL::bigint AS cancelled,
            NULL::bigint AS downgraded,
            NULL::bigint AS upgraded,
            NULL::bigint AS refund_rejected,
            NULL::bigint AS "COLLECTIONS",
            NULL::bigint AS assigned,
            NULL::bigint AS unreachable,
            NULL::bigint AS neutral_response,
            NULL::bigint AS positive_response,
            NULL::bigint AS contacted,
            NULL::bigint AS ticket_raised,
            NULL::bigint AS payment_link_sent,
            NULL::bigint AS payment_collected,
            NULL::bigint AS transferred,
            NULL::bigint AS transfer_requested,
            NULL::bigint AS deactivation_request_rejected,
            NULL::bigint AS deactivation_requested,
            NULL::bigint AS closed,
            NULL::bigint AS deactivated_c,
            NULL::bigint AS grand_total,
            NULL::character varying AS lead_status,
            NULL::character varying AS lead_substatus,
            NULL::text AS follow_up_status,
            NULL::integer AS follow_ups,
            NULL::text AS login_time,
            NULL::text AS logout_time,
            NULL::integer AS converted,
            NULL::integer AS conversion_count,
            NULL::integer AS arpa_amount,
            NULL::integer AS arft_amount,
            NULL::integer AS emandate_count,
            NULL::integer AS cash_flow_amount,
            NULL::integer AS cash_flow_count,
            NULL::timestamp with time zone AS repeat_lead_date,
            NULL::integer AS activity_count_flag,
            NULL::timestamp without time zone AS payment_date,
            NULL::character varying AS product_name,
            'Reasons'::text AS "Flag",
            NULL::integer AS workable_untouched,
            NULL::integer AS non_workable_untouched,
            NULL::character varying AS lead_name,
            NULL::character varying AS lead_mobile,
            NULL::character varying AS lead_email,
            NULL::character varying AS product,
            NULL::character varying AS sub_product,
            NULL::character varying AS utm_medium,
            NULL::character varying AS utm_source,
            NULL::character varying AS utm_campaign,
            NULL::character varying AS utm_content,
            NULL::character varying AS utm_url,
            NULL::character varying AS initially_taken_by,
            NULL::character varying AS initially_taken_by_location,
            NULL::smallint AS status_id_sl,
            NULL::smallint AS substatus_id_sl,
            NULL::timestamp with time zone AS created_at_sl,
            NULL::integer AS log_id,
            NULL::integer AS touched,
            NULL::integer AS workable,
            NULL::integer AS non_workable,
            NULL::integer AS touched_sl,
            NULL::integer AS workable_sl,
            NULL::integer AS non_workable_sl,
            NULL::integer AS not_pitched_sl,
            NULL::integer AS converted_sl,
            NULL::integer AS contact_id,
            NULL::integer AS untouched_flag,
            NULL::timestamp with time zone AS appointment_created_date,
            NULL::timestamp with time zone AS appointment_booked_date,
            NULL::text AS appointment_utm_medium,
            NULL::text AS appointment_utm_source,
            NULL::text AS appointment_utm_campaign,
            NULL::text AS appointment_utm_content,
            NULL::text AS appointment_utm_url,
            NULL::integer AS is_appointment_completed,
            NULL::timestamp with time zone AS appointment_completed_date,
            NULL::timestamp with time zone AS lead_created_date,
            NULL::character varying AS initial_lead_utm_medium,
            NULL::character varying AS initial_lead_utm_source,
            NULL::character varying AS initial_lead_utm_campaign,
            NULL::character varying AS initial_utm_content,
            NULL::text AS initial_lead_utm_url,
            NULL::timestamp with time zone AS repeat_lead_created_date,
            NULL::character varying AS repeat_lead_utm_medium,
            NULL::character varying AS repeat_lead_utm_source,
            NULL::character varying AS repeat_lead_utm_campaign,
            NULL::character varying AS repeat_lead_utm_content,
            NULL::text AS repeat_lead_utm_url,
            NULL::text AS payment_date_ab,
            NULL::text AS subscription_start_date_ab,
            NULL::character varying AS converted_by_counsellor_name,
            NULL::character varying AS converted_by_counsellor_email,
            NULL::bigint AS completed_ontime,
            NULL::bigint AS overdue_appointment,
            NULL::bigint AS active_appointment,
            NULL::integer AS appointment_booking_flag,
            reasons.comment,
            reasons.additional_comments,
            NULL::timestamp without time zone AS completed_on
           FROM reasons)) base
     LEFT JOIN ( SELECT a."RM_Id" AS counsellor_id,
            a."Rm_Name" AS counsellor,
            a."Rm_center" AS location,
            b.user_id,
            a.product,
            b.full_name AS captain_counsellor
           FROM "Counsellor Details" a
             LEFT JOIN mst_user b ON a."reporting manager Id" = b.user_id) people_date ON base.counsellor_id = people_date.counsellor_id
     LEFT JOIN ( SELECT lead.lead_id,
            lead.contact_id
           FROM lead) con ON base.lead_id = con.lead_id
     LEFT JOIN ( SELECT contact.contact_id,
            contact.full_name
           FROM contact) lnn ON con.contact_id = lnn.contact_id;