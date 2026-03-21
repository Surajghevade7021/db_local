-- public.payments_table source

CREATE OR REPLACE VIEW public.payments_table
AS WITH paymenttable AS (
         SELECT p_1.payment_id,
            p_1.onboarding_id,
            p_1.sub_product_id,
            p_1.lead_id,
            p_1.contact_id,
                CASE
                    WHEN op_1.payment_id IS NOT NULL THEN 'Offline'::text
                    ELSE 'Online'::text
                END AS payment_type,
            p_1.payment_provider AS payment_provider_id,
            p_1.payment_method,
            p_1.provider_reference_id,
            p_1.payment_date,
            p_1.created_by
           FROM payment p_1
             LEFT JOIN offline_payment op_1 ON p_1.payment_id = op_1.payment_id
        ), lead_payments AS (
         SELECT ll.lead_id,
            max(
                CASE
                    WHEN ll.substatus_id = 3 THEN 1
                    ELSE 0
                END) AS is_repeat,
            max(
                CASE
                    WHEN ll.substatus_id = ANY (ARRAY[1, 2]) THEN 1
                    ELSE 0
                END) AS is_new
           FROM lead_log ll
             JOIN paymenttable p_1 ON p_1.lead_id = ll.lead_id
          GROUP BY ll.lead_id
        ), lead_type AS (
         SELECT l_1.lead_id,
            l_1.utm_source,
            l_1.lead_source_id,
            l_1.created_at,
                CASE
                    WHEN lp.is_repeat = 1 THEN 'repeat_lead'::text
                    WHEN lp.is_new = 1 AND lp.is_repeat = 0 THEN 'New_lead'::text
                    ELSE 'NA'::text
                END AS lead_type
           FROM lead l_1
             JOIN lead_payments lp ON lp.lead_id = l_1.lead_id
        ), senario_temp AS (
         SELECT p_1.payment_id,
            p_1.onboarding_id,
            p_1.sub_product_id,
            p_1.lead_id,
            p_1.contact_id,
            p_1.payment_type,
            p_1.provider_reference_id,
            p_1.payment_provider_id,
            p_1.payment_method,
            p_1.payment_date,
            o_1.status_id,
            o_1.substatus_id,
            i_1.instalment_id,
            i_1.instalment_number,
            row_number() OVER (PARTITION BY i_1.contact_id ORDER BY p_1.payment_date) AS installment_rank,
            o_1.subscription_expiry_date AS expiry_date
           FROM paymenttable p_1
             LEFT JOIN ( SELECT DISTINCT ON (t.payment_id) t.instalment_id,
                    t.onboarding_id,
                    t.contact_id,
                    t.trackrr_customer_id,
                    t.lead_id,
                    t.sub_product_id,
                    t.tranche_number,
                    t.payable_on,
                    t.amount,
                    t.gst_percentage,
                    t.gst_amount,
                    t.total_amount,
                    t.service_type,
                    t.is_active,
                    t.payment_id,
                    t.company_id,
                    t.created_at,
                    t.created_by,
                    t.updated_at,
                    t.updated_by,
                    t.instalment_number,
                    t.emandate_discount_amount,
                    t.balance_amount,
                    t.is_refund_requested,
                    t.description,
                    t.trackrr_sales_source_id,
                    t.service_period_start_date,
                    t.service_period_end_date,
                    t.is_token_fees,
                    t.payment_id_t
                   FROM ( SELECT i_1_1.instalment_id,
                            i_1_1.onboarding_id,
                            i_1_1.contact_id,
                            i_1_1.trackrr_customer_id,
                            i_1_1.lead_id,
                            i_1_1.sub_product_id,
                            i_1_1.tranche_number,
                            i_1_1.payable_on,
                            i_1_1.amount,
                            i_1_1.gst_percentage,
                            i_1_1.gst_amount,
                            i_1_1.total_amount,
                            i_1_1.service_type,
                            i_1_1.is_active,
                            unnest(i_1_1.payment_id) AS payment_id,
                            i_1_1.company_id,
                            i_1_1.created_at,
                            i_1_1.created_by,
                            i_1_1.updated_at,
                            i_1_1.updated_by,
                            i_1_1.instalment_number,
                            i_1_1.emandate_discount_amount,
                            i_1_1.balance_amount,
                            i_1_1.is_refund_requested,
                            i_1_1.description,
                            i_1_1.trackrr_sales_source_id,
                            i_1_1.service_period_start_date,
                            i_1_1.service_period_end_date,
                            i_1_1.is_token_fees,
                            pid.pid AS payment_id_t
                           FROM instalment i_1_1
                             CROSS JOIN LATERAL unnest(i_1_1.payment_id) pid(pid)
                          WHERE i_1_1.payment_id IS NOT NULL) t
                  ORDER BY t.payment_id, t.created_at) i_1 ON p_1.payment_id = i_1.payment_id_t AND p_1.sub_product_id = i_1.sub_product_id
             LEFT JOIN onboarding o_1 ON o_1.onboarding_id = p_1.onboarding_id
          WHERE i_1.payment_id IS NOT NULL
        ), senario_main AS (
         SELECT senario_temp.sub_product_id,
            senario_temp.instalment_number,
            senario_temp.payment_date,
            senario_temp.payment_id,
            senario_temp.installment_rank,
            lag(senario_temp.expiry_date) OVER (PARTITION BY senario_temp.contact_id ORDER BY senario_temp.installment_rank) AS previous_expiry_date,
            lag(senario_temp.status_id) OVER (PARTITION BY senario_temp.contact_id ORDER BY senario_temp.installment_rank) AS previous_substatus_id,
            lag(senario_temp.sub_product_id) OVER (PARTITION BY senario_temp.contact_id ORDER BY senario_temp.installment_rank) AS previous_sub_product_id,
            lag(senario_temp.instalment_number) OVER (PARTITION BY senario_temp.contact_id ORDER BY senario_temp.installment_rank) AS previous_instalment_number
           FROM senario_temp
        ), senario AS (
         SELECT senario_main.payment_id,
                CASE
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.installment_rank = 1 AND senario_main.instalment_number = 0 THEN 'New Retail'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND (senario_main.previous_sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) THEN 'New Retail'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.instalment_number = 0 AND senario_main.previous_sub_product_id = senario_main.sub_product_id AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Retail Renewal'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.instalment_number >= 1 AND senario_main.sub_product_id = senario_main.previous_sub_product_id THEN 'Partpayment'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3, 4, 5, 11, 8])) AND senario_main.instalment_number >= 1 THEN 'Partpayment'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.instalment_number = 0 AND senario_main.sub_product_id <> senario_main.previous_sub_product_id AND senario_main.previous_sub_product_id IS NOT NULL AND senario_main.previous_instalment_number = 0 AND senario_main.previous_instalment_number IS NOT NULL AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'New Retail'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'New Retail'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_substatus_id = 35 AND senario_main.previous_instalment_number = 0 THEN 'New Retail'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) AND senario_main.installment_rank = 1 AND senario_main.instalment_number = 0 THEN 'New Multiplyrr'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_sub_product_id <> senario_main.sub_product_id THEN 'New Multiplyrr'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) AND senario_main.previous_sub_product_id = senario_main.sub_product_id AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Renewal Multiplyrr'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) AND senario_main.previous_sub_product_id = senario_main.sub_product_id AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'New Multiplyrr'::text
                    WHEN senario_main.sub_product_id = 4 AND senario_main.installment_rank = 1 AND senario_main.instalment_number = 0 THEN 'New Retail PMP'::text
                    WHEN senario_main.sub_product_id = 4 AND senario_main.instalment_number = 0 AND (senario_main.previous_sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29, 5, 8])) THEN 'New Retail PMP'::text
                    WHEN senario_main.sub_product_id = 4 AND senario_main.instalment_number = 1 AND senario_main.sub_product_id = senario_main.previous_sub_product_id THEN 'Partpayment'::text
                    WHEN senario_main.sub_product_id = 4 AND (senario_main.previous_sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'New Retail PMP'::text
                    WHEN senario_main.sub_product_id = 4 AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_substatus_id = 35 AND (senario_main.previous_sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.previous_instalment_number = 0 THEN 'New Retail PMP'::text
                    WHEN senario_main.sub_product_id = 4 AND (senario_main.previous_sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Existing Upgrade'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.installment_rank = 1 AND senario_main.instalment_number = 0 THEN 'New Dhanwaan'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND (senario_main.previous_sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29, 1, 2, 3, 4])) THEN 'New Dhanwaan'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.instalment_number = 0 AND senario_main.previous_sub_product_id = senario_main.sub_product_id AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Renewal Dhanwaan'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.instalment_number >= 1 AND senario_main.sub_product_id = senario_main.previous_sub_product_id THEN 'Partpayment'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'New Dhanwaan'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_substatus_id = 35 AND senario_main.previous_instalment_number = 0 THEN 'New Dhanwaan'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.instalment_number = 0 AND senario_main.sub_product_id <> senario_main.previous_sub_product_id AND senario_main.previous_sub_product_id IS NOT NULL AND senario_main.instalment_number = 0 AND senario_main.previous_instalment_number = 0 AND senario_main.previous_instalment_number IS NOT NULL AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'New Dhanwaan'::text
                    WHEN senario_main.sub_product_id = 11 AND senario_main.installment_rank = 1 AND senario_main.instalment_number = 0 THEN 'New Dhanwaan PMP'::text
                    WHEN senario_main.sub_product_id = 11 AND senario_main.instalment_number = 0 AND senario_main.previous_expiry_date >= senario_main.payment_date::date AND (senario_main.previous_sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29, 1, 2, 3, 4])) THEN 'New Dhanwaan PMP'::text
                    WHEN senario_main.sub_product_id = 11 AND (senario_main.previous_sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'New Dhanwaan PMP'::text
                    WHEN senario_main.sub_product_id = 11 AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_substatus_id = 35 AND (senario_main.previous_sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.previous_instalment_number = 0 THEN 'New Dhanwaan PMP'::text
                    WHEN senario_main.sub_product_id = 11 AND (senario_main.previous_sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Existing Upgrade'::text
                    WHEN senario_main.sub_product_id = 11 AND senario_main.instalment_number = 1 AND senario_main.sub_product_id = senario_main.previous_sub_product_id THEN 'Partpayment'::text
                    ELSE 'Unknown Status'::text
                END AS status,
                CASE
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.installment_rank = 1 AND senario_main.instalment_number = 0 THEN 'New Retail'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.instalment_number = 0 AND senario_main.previous_sub_product_id = senario_main.sub_product_id AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Before Expiry'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.instalment_number = 1 AND senario_main.sub_product_id = senario_main.previous_sub_product_id THEN 'Retail Renewal Tranche 2'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.instalment_number >= 1 THEN 'Retail Renewal Tranche 2'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND (senario_main.previous_sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) THEN 'Existing upgrade to Retail'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'Expired to customer'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_substatus_id = 35 AND senario_main.previous_instalment_number = 0 THEN 'Refund to customer'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.instalment_number = 0 AND senario_main.sub_product_id <> senario_main.previous_sub_product_id AND senario_main.previous_sub_product_id IS NOT NULL AND senario_main.previous_instalment_number = 0 AND senario_main.previous_instalment_number IS NOT NULL AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Deactivated to customer'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) AND senario_main.installment_rank = 1 AND senario_main.instalment_number = 0 THEN 'New Multiplyrr'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_sub_product_id <> senario_main.sub_product_id THEN 'New Multiplyrr'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) AND senario_main.previous_sub_product_id = senario_main.sub_product_id AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Before Expiry'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29])) AND senario_main.previous_sub_product_id = senario_main.sub_product_id AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'Expired to customer'::text
                    WHEN senario_main.sub_product_id = 4 AND senario_main.installment_rank = 1 AND senario_main.instalment_number = 0 THEN 'New Retail PMP'::text
                    WHEN senario_main.sub_product_id = 4 AND senario_main.instalment_number = 0 AND (senario_main.previous_sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29, 5, 8])) THEN 'New Retail PMP'::text
                    WHEN senario_main.sub_product_id = 4 AND senario_main.instalment_number = 1 AND senario_main.sub_product_id = senario_main.previous_sub_product_id THEN 'Retail PMP Partpayment'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[4])) AND senario_main.instalment_number >= 1 THEN 'Retail PMP Partpayment'::text
                    WHEN senario_main.sub_product_id = 4 AND (senario_main.previous_sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'Expired to customer'::text
                    WHEN senario_main.sub_product_id = 4 AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_substatus_id = 35 AND (senario_main.previous_sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.previous_instalment_number = 0 THEN 'Refund to customer'::text
                    WHEN senario_main.sub_product_id = 4 AND (senario_main.previous_sub_product_id = ANY (ARRAY[1, 2, 3])) AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Existing Upgrade To Retail PMP'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.instalment_number = 0 AND senario_main.installment_rank = 1 THEN 'New Dhanwaan'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND (senario_main.previous_sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29, 1, 2, 3, 4])) THEN 'New Dhanwaan'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.instalment_number = 0 AND senario_main.previous_sub_product_id = senario_main.sub_product_id AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Before Expiry'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.instalment_number = 1 AND senario_main.sub_product_id = senario_main.previous_sub_product_id THEN 'Dhanwaan Renewal Tranche 2'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.instalment_number >= 1 THEN 'Dhanwaan Renewal Tranche 2'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'Expired to customer'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_substatus_id = 35 AND senario_main.previous_instalment_number = 0 THEN 'Refund to customer'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.instalment_number = 0 AND senario_main.sub_product_id <> senario_main.previous_sub_product_id AND senario_main.previous_sub_product_id IS NOT NULL AND senario_main.previous_instalment_number = 0 AND senario_main.previous_instalment_number IS NOT NULL AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Deactivated to customer'::text
                    WHEN senario_main.sub_product_id = 11 AND senario_main.installment_rank = 1 AND senario_main.instalment_number = 0 THEN 'New Dhanwaan PMP'::text
                    WHEN senario_main.sub_product_id = 11 AND senario_main.instalment_number = 0 AND senario_main.previous_expiry_date >= senario_main.payment_date::date AND (senario_main.previous_sub_product_id = ANY (ARRAY[23, 24, 25, 26, 27, 28, 30, 29, 1, 2, 3, 4])) THEN 'New Dhanwaan PMP (Existing Upgrade)'::text
                    WHEN senario_main.sub_product_id = 11 AND (senario_main.previous_sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.previous_expiry_date < senario_main.payment_date::date THEN 'Expired to customer'::text
                    WHEN senario_main.sub_product_id = 11 AND senario_main.installment_rank > 1 AND senario_main.instalment_number = 0 AND senario_main.previous_substatus_id = 35 AND (senario_main.previous_sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.previous_instalment_number = 0 THEN 'Refund to customer'::text
                    WHEN senario_main.sub_product_id = 11 AND (senario_main.previous_sub_product_id = ANY (ARRAY[5, 8])) AND senario_main.previous_expiry_date >= senario_main.payment_date::date THEN 'Existing Upgrade To Dhanwaan PMP'::text
                    WHEN senario_main.sub_product_id = 11 AND senario_main.instalment_number = 1 AND senario_main.sub_product_id = senario_main.previous_sub_product_id THEN 'Dhanwaan PMP Partpayment'::text
                    WHEN (senario_main.sub_product_id = ANY (ARRAY[11])) AND senario_main.instalment_number >= 1 THEN 'Dhanwaan PMP Partpayment'::text
                    ELSE 'Unknown Scenario'::text
                END AS scenario
           FROM senario_main
        ), age AS (
         SELECT DISTINCT ON (od.onboarding_id) od.onboarding_id,
            od.date_of_birth::date AS date_of_birth,
            date_part('year'::text, age(CURRENT_DATE::timestamp with time zone, od.date_of_birth::timestamp with time zone)) AS "Age"
           FROM onboarding_detail od
             LEFT JOIN paymenttable p_1 ON p_1.onboarding_id = od.onboarding_id
          WHERE od.date_of_birth IS NOT NULL AND p_1.onboarding_id IS NOT NULL
          ORDER BY od.onboarding_id, od.onboarding_detail_id
        ), gender AS (
         SELECT DISTINCT ON (cd.contact_id) cd.contact_id,
            cd.gender,
            cd.income
           FROM contact_demography cd
             JOIN paymenttable p_1 ON p_1.contact_id = cd.contact_id
          WHERE cd.gender IS NOT NULL
        ), occupation AS (
         SELECT DISTINCT ON (t.onboarding_id) t.occupation,
            t.onboarding_id
           FROM ( SELECT COALESCE(oar.response ->> 'occupation'::text, (((oar.response -> 'signing_parties'::text) -> 0) -> 'pki_signature_details'::text) ->> 'occupation'::text, ((((((((oar.response::json ->> 'actions'::text)::json) -> 1) ->> 'details'::text)::json) ->> 'pan'::text)::json) -> 'occupation'::text)::text, xml_occupation.occupation, (replace(TRIM(BOTH '"'::text FROM oar.response::text), '\"'::text, '"'::text)::json -> 'pan_details'::text) ->> 'occupation'::text) AS occupation,
                    oar.onboarding_id
                   FROM onboarding_api_response oar
                     LEFT JOIN paymenttable p_1 ON p_1.onboarding_id = oar.onboarding_id
                     LEFT JOIN LATERAL ( SELECT (regexp_matches(oar.response::text, '<occupation>(.*?)</occupation>'::text))[1] AS occupation) xml_occupation ON true
                  WHERE oar.response::text ~~* '%occupation%'::text AND p_1.onboarding_id IS NOT NULL) t
          WHERE t.occupation IS NOT NULL
        )
 SELECT DISTINCT ON (p.payment_id) p.payment_date AS refresh_date,
    c.contact_id,
    o.lead_id AS "Lead Id",
    p.payment_date AS "Payment Date",
    c.full_name AS "Lead Name",
    c.email_address AS "Lead Email ID",
    mp.name AS "Product",
    msp.name AS "Sub-Product",
    lt.lead_type AS "Lead Type",
    mu.full_name AS "Rm_Name",
    o.rm_id AS "RM_Id",
    ml.name AS "Rm_center",
    mu2.full_name AS "reporting manager Name",
    mu2.user_id AS "reporting manager Id",
    CURRENT_DATE - lt.created_at::date AS lead_age,
    ou.full_name AS "Onboarded By Name",
    ml2.name AS "Onboarding User Location",
    ms2.name AS "Status",
    ms.name AS "SubStatus",
    COALESCE(mls.name, lt.utm_source) AS "Lead Source",
    o.adjustment_amount,
    i.amount AS amt_recd,
    state.name AS state_name,
    city.name AS city_name,
    cad.pin_code,
    o.onboarding_id,
    p.payment_provider_id,
    p.payment_type,
        CASE
            WHEN p.payment_method = 110 AND (p.payment_provider_id = ANY (ARRAY[305, 170, 169, 168, 304])) AND (p.payment_type = ANY (ARRAY['Online'::text, 'Offline'::text])) THEN 'Cheque'::text
            WHEN (p.payment_method = ANY (ARRAY[110, 115, 114, 113, 111, 112, 109, 116])) AND p.payment_provider_id = 166 AND p.payment_type = 'Offline'::text THEN 'Old-Razorpay'::text
            WHEN (p.payment_method = ANY (ARRAY[110, 115, 114, 113, 111, 112, 109, 116])) AND p.payment_provider_id = 166 AND p.payment_type = 'Online'::text THEN 'New-Razorpay'::text
            WHEN (p.payment_method = ANY (ARRAY[115, 109])) AND p.payment_provider_id = 167 AND (p.payment_type = ANY (ARRAY['Online'::text, 'Offline'::text])) THEN 'Instamojo'::text
            WHEN (p.payment_method = ANY (ARRAY[115, 114])) AND p.payment_provider_id = 304 AND (p.payment_type = ANY (ARRAY['Online'::text, 'Offline'::text])) THEN 'Other'::text
            WHEN p.payment_method = 117 AND (p.payment_provider_id = ANY (ARRAY[166, 231])) AND p.payment_type = 'Online'::text THEN 'Razorpay-Emandate'::text
            WHEN p.payment_method = 117 AND (p.payment_provider_id = ANY (ARRAY[166, 231])) AND p.payment_type = 'Online'::text THEN 'CAMS-Emandate'::text
            WHEN p.payment_method = 113 AND (p.payment_provider_id = ANY (ARRAY[305, 170, 169, 168, 304])) AND (p.payment_type = ANY (ARRAY['Online'::text, 'Offline'::text])) THEN 'INTERNET BANKING'::text
            WHEN p.payment_method = 111 AND (p.payment_provider_id = ANY (ARRAY[305, 170, 169, 168, 304])) AND (p.payment_type = ANY (ARRAY['Online'::text, 'Offline'::text])) THEN 'NEFT'::text
            WHEN p.payment_method = 112 AND (p.payment_provider_id = ANY (ARRAY[305, 168, 304])) AND (p.payment_type = ANY (ARRAY['Online'::text, 'Offline'::text])) THEN 'RTGS'::text
            WHEN p.payment_method = 109 AND (p.payment_provider_id = ANY (ARRAY[305, 301, 170, 168, 304, 300])) AND (p.payment_type = ANY (ARRAY['Online'::text, 'Offline'::text])) THEN 'UPI'::text
            ELSE 'Unknown'::text
        END AS "Payment mode",
    s.payment_id,
    s.status,
    s.scenario,
    NULL::character varying AS "rm_Email Id",
    NULL::boolean AS is_active,
    NULL::character varying AS product,
    NULL::character varying AS "Sub Product",
    NULL::character varying AS flag,
    NULL::timestamp with time zone AS created_at,
    NULL::integer AS rm_id,
    NULL::integer AS lead_id,
    NULL::bigint AS called,
    NULL::bigint AS "Detail Conversation",
    NULL::bigint AS "Had a Phone Conversation",
    NULL::double precision AS "Call duration",
    NULL::character varying AS "group substatus",
    NULL::text AS lead_group_source,
    NULL::text AS utm_campaign,
    NULL::text AS utm_medium,
    a.date_of_birth AS "Date of Birth",
    a."Age"::smallint AS "Age",
    g.gender::text AS "Gender",
    op.occupation AS "Occupation",
    g.income::text AS "Income",
    'Payment'::text AS "Flag"
   FROM paymenttable p
     LEFT JOIN onboarding o ON o.onboarding_id = p.onboarding_id
     LEFT JOIN ( SELECT i_1.instalment_id,
            i_1.onboarding_id,
            i_1.contact_id,
            i_1.trackrr_customer_id,
            i_1.lead_id,
            i_1.sub_product_id,
            i_1.tranche_number,
            i_1.payable_on,
            i_1.amount,
            i_1.gst_percentage,
            i_1.gst_amount,
            i_1.total_amount,
            i_1.service_type,
            i_1.is_active,
            i_1.payment_id,
            i_1.company_id,
            i_1.created_at,
            i_1.created_by,
            i_1.updated_at,
            i_1.updated_by,
            i_1.instalment_number,
            i_1.emandate_discount_amount,
            i_1.balance_amount,
            i_1.is_refund_requested,
            i_1.description,
            i_1.trackrr_sales_source_id,
            i_1.service_period_start_date,
            i_1.service_period_end_date,
            i_1.is_token_fees,
            pid.pid AS payment_id_t
           FROM instalment i_1
             CROSS JOIN LATERAL unnest(i_1.payment_id) pid(pid)
          WHERE i_1.payment_id IS NOT NULL) i ON p.payment_id = i.payment_id_t AND p.sub_product_id = i.sub_product_id
     LEFT JOIN mst_subproduct msp ON msp.sub_product_id = p.sub_product_id
     LEFT JOIN mst_product mp ON mp.product_id = msp.product_id
     LEFT JOIN lead l ON l.lead_id = p.lead_id
     LEFT JOIN mst_user mu ON mu.user_id = l.rm_id
     LEFT JOIN mst_location ml ON mu.location_id = ml.location_id
     LEFT JOIN contact c ON c.contact_id = p.contact_id
     LEFT JOIN ( SELECT t.contact_address_detail_id,
            t.contact_id,
            t.address_line_1,
            t.address_line_2,
            t.address_line_3,
            t.pin_code,
            t.city_id,
            t.state_id,
            t.is_primary,
            t.company_id,
            t.created_at,
            t.created_by,
            t.updated_at,
            t.updated_by,
            t.country_id,
            t.rn
           FROM ( SELECT contact_address_detail.contact_address_detail_id,
                    contact_address_detail.contact_id,
                    contact_address_detail.address_line_1,
                    contact_address_detail.address_line_2,
                    contact_address_detail.address_line_3,
                    contact_address_detail.pin_code,
                    contact_address_detail.city_id,
                    contact_address_detail.state_id,
                    contact_address_detail.is_primary,
                    contact_address_detail.company_id,
                    contact_address_detail.created_at,
                    contact_address_detail.created_by,
                    contact_address_detail.updated_at,
                    contact_address_detail.updated_by,
                    contact_address_detail.country_id,
                    row_number() OVER (PARTITION BY contact_address_detail.contact_id ORDER BY contact_address_detail.updated_at DESC) AS rn
                   FROM contact_address_detail
                  WHERE contact_address_detail.is_primary = true) t
          WHERE t.rn = 1) cad ON c.contact_id = cad.contact_id
     LEFT JOIN mst_state state ON cad.state_id = state.state_id
     LEFT JOIN mst_city city ON cad.city_id = city.city_id
     LEFT JOIN mst_user ou ON ou.user_id = o.created_by
     LEFT JOIN mst_location ml2 ON ou.location_id = ml2.location_id
     LEFT JOIN mst_substatus ms ON o.substatus_id = ms.substatus_id
     LEFT JOIN mst_status ms2 ON o.status_id = ms2.status_id
     LEFT JOIN lead_type lt ON p.lead_id = lt.lead_id
     LEFT JOIN mst_user mu2 ON mu2.user_id = mu.reporting_manager_id
     LEFT JOIN mst_lead_source mls ON lt.lead_source_id = mls.lead_source_id
     LEFT JOIN senario s ON s.payment_id = p.payment_id
     LEFT JOIN age a ON a.onboarding_id = o.onboarding_id
     LEFT JOIN gender g ON g.contact_id = o.contact_id
     LEFT JOIN occupation op ON op.onboarding_id = o.onboarding_id
  WHERE COALESCE(mu.user_id, 0) <> 1518 AND i.payment_id IS NOT NULL
UNION ALL
( WITH user_list AS (
         SELECT unnest(ARRAY[2674, 2673, 1757, 2671, 2389, 2331, 2439, 1718, 328, 2576, 2284, 2487, 1728, 2152, 2652, 2221, 2640, 2577, 2083, 2145, 2662, 2657, 2488, 1762, 2136, 2663, 2659, 947, 380, 2081, 379, 1645, 1760, 2085, 2134, 298, 2665, 1637, 2643, 2110, 1717, 2149, 2525, 2741, 2333, 2212, 2198, 94, 2213, 2600, 2097, 2485, 1492, 2344, 1643, 1159, 2460, 2497, 2508, 1750, 450, 2582, 2626, 476, 2070, 1585, 2314, 2566, 1661, 2499, 2211, 2031, 2437, 2303, 2139, 2646, 2013, 1658, 825, 2114, 2222, 2209, 2324, 2233, 2516, 2317, 2289, 2587, 701, 2109, 397, 2101, 2102, 2167, 532, 942, 2192, 2649, 2295, 2234, 2591, 2527, 2651, 879, 2319, 374, 281, 2619, 2330, 2501, 2345, 2495, 1720, 2653, 2494, 2322, 2658, 1590, 2654, 2537, 1363, 2475, 2398, 2399, 2393, 2609, 2464, 2505, 2531, 2650, 2395, 2168, 2104, 2325, 2506, 2542, 2532, 2486, 2613, 2224, 2612, 2621, 2599, 2492, 2553, 1502, 2661, 2522, 2622, 2625, 1749, 246, 376, 2286, 2572, 2571, 1657, 2148, 1727, 2593, 2079, 2159, 2142, 2629, 2648, 2092, 2623, 2627, 2624, 2246, 2567, 2523, 2543, 2305, 2638, 2636, 2634, 2631, 2466, 2455, 2562, 2564, 358, 2584, 2655, 2632, 2605, 352, 2664, 2072, 2515, 595, 2633, 2606, 2405, 2402, 2394, 1734, 2351, 2025, 2617, 2105, 2294, 2581, 2677, 2656, 1761, 2120, 2684, 2628, 2685, 2683, 2688, 2166, 2678, 2682, 2689, 2729, 472, 2679, 2690, 2695, 2691, 2700, 2707, 2709, 2693, 2692, 2131, 2130, 2580, 2123, 1715, 2681, 2697, 2708, 2710, 2714, 2715, 2711, 2713, 2712, 2724, 2703, 2704, 2698, 2699, 2722, 2720, 2721, 2716, 2717, 2718, 2723, 2719, 2705, 2706, 2702, 2701, 2229, 2244, 2666, 2304, 2519, 2520, 2667, 2737, 2739, 2740, 2761, 2763, 2764, 2765, 2767, 2742, 2768, 2769, 2770, 2762]) AS user_id
        )
 SELECT NULL::timestamp with time zone AS refresh_date,
    NULL::integer AS contact_id,
    NULL::integer AS "Lead Id",
    NULL::timestamp with time zone AS "Payment Date",
    NULL::text AS "Lead Name",
    NULL::character varying AS "Lead Email ID",
    NULL::character varying AS "Product",
    NULL::character varying AS "Sub-Product",
    NULL::text AS "Lead Type",
    mu.full_name AS "Rm_Name",
    mu.user_id AS "RM_Id",
    ml.name AS "Rm_center",
    mu2.full_name AS "reporting manager Name",
    NULL::integer AS "reporting manager Id",
    NULL::integer AS lead_age,
    NULL::character varying AS "Onboarded By Name",
    NULL::character varying AS "Onboarding User Location",
    NULL::character varying AS "Status",
    NULL::character varying AS "SubStatus",
    NULL::character varying AS "Lead Source",
    NULL::double precision AS adjustment_amount,
    NULL::integer AS amt_recd,
    NULL::character varying AS state_name,
    NULL::character varying AS city_name,
    NULL::character varying AS pin_code,
    NULL::integer AS onboarding_id,
    NULL::smallint AS payment_provider_id,
    NULL::text AS payment_type,
    NULL::text AS "Payment mode",
    NULL::integer AS payment_id,
    NULL::text AS status,
    NULL::text AS scenario,
    NULL::character varying AS "rm_Email Id",
    NULL::boolean AS is_active,
    NULL::character varying AS product,
    NULL::character varying AS "Sub Product",
    NULL::character varying AS flag,
    NULL::timestamp with time zone AS created_at,
    NULL::integer AS rm_id,
    NULL::integer AS lead_id,
    NULL::bigint AS called,
    NULL::bigint AS "Detail Conversation",
    NULL::bigint AS "Had a Phone Conversation",
    NULL::double precision AS "Call duration",
    NULL::character varying AS "group substatus",
    NULL::text AS lead_group_source,
    NULL::text AS utm_campaign,
    NULL::text AS utm_medium,
    NULL::date AS "Date of Birth",
    NULL::smallint AS "Age",
    NULL::text AS "Gender",
    NULL::text AS "Occupation",
    NULL::text AS "Income",
    'Payment'::text AS "Flag"
   FROM mst_user mu
     LEFT JOIN mst_location ml ON mu.location_id = ml.location_id
     LEFT JOIN mst_user mu2 ON mu.reporting_manager_id = mu2.user_id
     JOIN user_list ul ON mu.user_id = ul.user_id
     LEFT JOIN ( SELECT DISTINCT payment.created_by
           FROM payment
          WHERE payment.payment_date::date >= date_trunc('month'::text, CURRENT_DATE::timestamp with time zone)) p ON mu.user_id = p.created_by
  WHERE p.created_by IS NULL)
UNION ALL
 SELECT DISTINCT ON (mu.user_id) NULL::timestamp with time zone AS refresh_date,
    NULL::integer AS contact_id,
    NULL::integer AS "Lead Id",
    CURRENT_DATE AS "Payment Date",
    NULL::text AS "Lead Name",
    NULL::character varying AS "Lead Email ID",
    NULL::character varying AS "Product",
    NULL::character varying AS "Sub-Product",
    NULL::text AS "Lead Type",
    mu.full_name AS "Rm_Name",
    mu.user_id AS "RM_Id",
    ml.name AS "Rm_center",
    mu2.full_name AS "reporting manager Name",
    mu2.user_id AS "reporting manager Id",
    NULL::integer AS lead_age,
    NULL::character varying AS "Onboarded By Name",
    NULL::character varying AS "Onboarding User Location",
    NULL::character varying AS "Status",
    NULL::character varying AS "SubStatus",
    NULL::character varying AS "Lead Source",
    NULL::double precision AS adjustment_amount,
    NULL::integer AS amt_recd,
    NULL::character varying AS state_name,
    NULL::character varying AS city_name,
    NULL::character varying AS pin_code,
    NULL::integer AS onboarding_id,
    NULL::smallint AS payment_provider_id,
    NULL::text AS payment_type,
    NULL::text AS "Payment mode",
    NULL::integer AS payment_id,
    NULL::text AS status,
    NULL::text AS scenario,
    mu.email_address AS "rm_Email Id",
    mu.is_active,
    mp.name AS product,
    ms.name AS "Sub Product",
        CASE
            WHEN mp.product_id = 1 AND (ms.sub_product_id = ANY (ARRAY[1, 2, 3])) THEN 'Retail'::text
            WHEN mp.product_id = 1 AND ms.sub_product_id = 4 THEN 'Retail PMP'::text
            WHEN mp.product_id = 3 AND (ms.sub_product_id = ANY (ARRAY[25, 27, 24, 23, 29, 26, 30, 28])) THEN 'Multiplyrr'::text
            WHEN mp.product_id = 2 AND (ms.sub_product_id = ANY (ARRAY[5, 8, 11])) THEN 'Dhanwaan'::text
            ELSE NULL::text
        END AS flag,
    NULL::timestamp with time zone AS created_at,
    NULL::integer AS rm_id,
    NULL::integer AS lead_id,
    NULL::bigint AS called,
    NULL::bigint AS "Detail Conversation",
    NULL::bigint AS "Had a Phone Conversation",
    NULL::double precision AS "Call duration",
    NULL::character varying AS "group substatus",
    NULL::text AS lead_group_source,
    NULL::text AS utm_campaign,
    NULL::text AS utm_medium,
    NULL::date AS "Date of Birth",
    NULL::smallint AS "Age",
    NULL::text AS "Gender",
    NULL::text AS "Occupation",
    NULL::text AS "Income",
    'Counsellor Details'::text AS "Flag"
   FROM mst_user mu
     LEFT JOIN mst_user mu2 ON mu.reporting_manager_id = mu2.user_id
     LEFT JOIN mst_location ml ON ml.location_id = mu.location_id
     LEFT JOIN mst_subproduct ms ON ms.sub_product_id = ANY (mu.sub_product_ids)
     LEFT JOIN mst_product mp ON mp.product_id = ms.product_id
  WHERE mu.user_id = ANY (ARRAY[2674, 2673, 1757, 2671, 2389, 2331, 2439, 1718, 328, 2576, 2284, 2487, 1728, 2152, 2652, 2221, 2640, 2577, 2083, 2145, 2662, 2657, 2488, 1762, 2136, 2663, 2659, 947, 380, 2081, 379, 1645, 1760, 2085, 2134, 298, 2665, 1637, 2643, 2110, 1717, 2149, 2525, 2741, 2333, 2212, 2198, 94, 2213, 2600, 2097, 2485, 1492, 2344, 1643, 1159, 2460, 2497, 2508, 1750, 450, 2582, 2626, 476, 2070, 1585, 2314, 2566, 1661, 2499, 2211, 2031, 2437, 2303, 2139, 2646, 2013, 1658, 825, 2114, 2222, 2209, 2324, 2233, 2516, 2317, 2289, 2587, 701, 2109, 397, 2101, 2102, 2167, 532, 942, 2192, 2649, 2295, 2234, 2591, 2527, 2651, 879, 2319, 374, 281, 2619, 2330, 2501, 2345, 2495, 1720, 2653, 2494, 2322, 2658, 1590, 2654, 2537, 1363, 2475, 2398, 2399, 2393, 2609, 2464, 2505, 2531, 2650, 2395, 2168, 2104, 2325, 2506, 2542, 2532, 2486, 2613, 2224, 2612, 2621, 2599, 2492, 2553, 1502, 2661, 2522, 2622, 2625, 1749, 246, 376, 2286, 2572, 2571, 1657, 2148, 1727, 2593, 2079, 2159, 2142, 2629, 2648, 2092, 2623, 2627, 2624, 2246, 2567, 2523, 2543, 2305, 2638, 2636, 2634, 2631, 2466, 2455, 2562, 2564, 358, 2584, 2655, 2632, 2605, 352, 2664, 2072, 2515, 595, 2633, 2606, 2405, 2402, 2394, 1734, 2351, 2025, 2617, 2105, 2294, 2581, 2677, 2656, 1761, 2120, 2684, 2628, 2685, 2683, 2688, 2166, 2678, 2682, 2689, 2729, 472, 1503, 2690, 2695, 2691, 2700, 2707, 2709, 2693, 2692, 2131, 2130, 2580, 2123, 1715, 2681, 2697, 2708, 2710, 2714, 2715, 2711, 2713, 2712, 2724, 2703, 2704, 2698, 2699, 2722, 2720, 2721, 2716, 2717, 2718, 2723, 2719, 2705, 2706, 2702, 2701, 2229, 2244, 2666, 2304, 2519, 2520, 2667, 2737, 2739, 2740, 2761, 2763, 2764, 2765, 2767, 2742, 2768, 2769, 2770, 2762])
UNION ALL
 SELECT DISTINCT ON (ll.lead_id, ll.rm_id) ll.created_at AS refresh_date,
    NULL::integer AS contact_id,
    NULL::integer AS "Lead Id",
    NULL::timestamp with time zone AS "Payment Date",
    NULL::text AS "Lead Name",
    NULL::character varying AS "Lead Email ID",
    NULL::character varying AS "Product",
    NULL::character varying AS "Sub-Product",
    NULL::text AS "Lead Type",
    mu.full_name AS "Rm_Name",
    mu.user_id AS "RM_Id",
    ml.name AS "Rm_center",
    mu2.full_name AS "reporting manager Name",
    NULL::integer AS "reporting manager Id",
    NULL::integer AS lead_age,
    NULL::character varying AS "Onboarded By Name",
    NULL::character varying AS "Onboarding User Location",
    NULL::character varying AS "Status",
    NULL::character varying AS "SubStatus",
    NULL::character varying AS "Lead Source",
    NULL::double precision AS adjustment_amount,
    NULL::integer AS amt_recd,
    NULL::character varying AS state_name,
    NULL::character varying AS city_name,
    NULL::character varying AS pin_code,
    NULL::integer AS onboarding_id,
    NULL::smallint AS payment_provider_id,
    NULL::text AS payment_type,
    NULL::text AS "Payment mode",
    NULL::integer AS payment_id,
    NULL::text AS status,
    NULL::text AS scenario,
    mu.email_address AS "rm_Email Id",
    mu.is_active,
    mp.name AS product,
    ms.name AS "Sub Product",
        CASE
            WHEN mp.product_id = 1 AND (ms.sub_product_id = ANY (ARRAY[1, 2, 3])) THEN 'Retail'::text
            WHEN mp.product_id = 1 AND ms.sub_product_id = 4 THEN 'Retail PMP'::text
            WHEN mp.product_id = 3 AND (ms.sub_product_id = ANY (ARRAY[25, 27, 24, 23, 29, 26, 30, 28])) THEN 'Multiplyrr'::text
            WHEN mp.product_id = 2 AND (ms.sub_product_id = ANY (ARRAY[5, 8, 11])) THEN 'Dhanwaan'::text
            ELSE NULL::text
        END AS flag,
    ll.created_at,
    ll.rm_id,
    ll.lead_id,
    NULL::bigint AS called,
    NULL::bigint AS "Detail Conversation",
    NULL::bigint AS "Had a Phone Conversation",
    NULL::double precision AS "Call duration",
    NULL::character varying AS "group substatus",
    NULL::text AS lead_group_source,
    NULL::text AS utm_campaign,
    NULL::text AS utm_medium,
    NULL::date AS "Date of Birth",
    NULL::smallint AS "Age",
    NULL::text AS "Gender",
    NULL::text AS "Occupation",
    NULL::text AS "Income",
    'Lead Taken'::text AS "Flag"
   FROM lead_log ll
     LEFT JOIN mst_user mu ON ll.rm_id = mu.user_id
     LEFT JOIN mst_user mu2 ON mu.reporting_manager_id = mu2.user_id
     LEFT JOIN mst_location ml ON ml.location_id = mu.location_id
     LEFT JOIN mst_subproduct ms ON ms.sub_product_id = ANY (mu.sub_product_ids)
     LEFT JOIN mst_product mp ON mp.product_id = ms.product_id
  WHERE ll.created_at::date >= '2025-09-01'::date AND (ll.rm_id = ANY (ARRAY[2674, 2673, 1757, 2671, 2389, 2331, 2439, 1718, 328, 2576, 2284, 2487, 1728, 2152, 2652, 2221, 2640, 2577, 2083, 2145, 2662, 2657, 2488, 1762, 2136, 2663, 2659, 947, 380, 2081, 379, 1645, 1760, 2085, 2134, 298, 2665, 1637, 2643, 2110, 1717, 2149, 2525, 2741, 2333, 2212, 2198, 94, 2213, 2600, 2097, 2485, 1492, 2344, 1643, 1159, 2460, 2497, 2508, 1750, 450, 2582, 2626, 476, 2070, 1585, 2314, 2566, 1661, 2499, 2211, 2031, 2437, 2303, 2139, 2646, 2013, 1658, 825, 2114, 2222, 2209, 2324, 2233, 2516, 2317, 2289, 2587, 701, 2109, 397, 2101, 2102, 2167, 532, 942, 2192, 2649, 2295, 2234, 2591, 2527, 2651, 879, 2319, 374, 281, 2619, 2330, 2501, 2345, 2495, 1720, 2653, 2494, 2322, 2658, 1590, 2654, 2537, 1363, 2475, 2398, 2399, 2393, 2609, 2464, 2505, 2531, 2650, 2395, 2168, 2104, 2325, 2506, 2542, 2532, 2486, 2613, 2224, 2612, 2621, 2599, 2492, 2553, 1502, 2661, 2522, 2622, 2625, 1749, 246, 376, 2286, 2572, 2571, 1657, 2148, 1727, 2593, 2079, 2159, 2142, 2629, 2648, 2092, 2623, 2627, 2624, 2246, 2567, 2523, 2543, 2305, 2638, 2636, 2634, 2631, 2466, 2455, 2562, 2564, 358, 2584, 2655, 2632, 2605, 352, 2664, 2072, 2515, 595, 2633, 2606, 2405, 2402, 2394, 1734, 2351, 2025, 2617, 2105, 2294, 2581, 2677, 2656, 1761, 2120, 2684, 2628, 2685, 2683, 2688, 2166, 2678, 2682, 2689, 2729, 472, 2679, 2690, 2695, 2691, 2700, 2707, 2709, 2693, 2692, 2131, 2130, 2580, 2123, 1715, 2681, 2697, 2708, 2710, 2714, 2715, 2711, 2713, 2712, 2724, 2703, 2704, 2698, 2699, 2722, 2720, 2721, 2716, 2717, 2718, 2723, 2719, 2705, 2706, 2702, 2701, 2229, 2244, 2666, 2304, 2519, 2520, 2667, 2737, 2739, 2740, 2761, 2763, 2764, 2765, 2767, 2742, 2768, 2769, 2770, 2762]))
UNION ALL
( WITH activity_selected AS (
         SELECT a_1.activity_id,
            a_1.company_id,
            a_1.lead_id,
            a_1.contact_id,
            a_1.contact_detail_id,
            a_1.customer_id,
            a_1.rm_id,
            a_1.activity_type_id,
            a_1.reference_id,
            a_1.meta_info,
            a_1.origin,
            a_1.call_duration,
            a_1.sent_to,
            a_1.status_id,
            a_1.substatus_id,
            a_1.location_id,
            a_1.department_id,
            a_1.reporting_manager_id,
            a_1.team_id,
            a_1.comment_ids,
            a_1.additional_comments,
            a_1.is_visible,
            a_1.tags_id,
            a_1.forward_to,
            a_1.message_id,
            a_1.score,
            a_1.conversion_interaction,
            a_1.created_at,
            a_1.created_by,
            a_1.updated_at,
            a_1.updated_by
           FROM activity a_1
          WHERE a_1.activity_type_id = ANY (ARRAY[1, 7])
        )
 SELECT a.created_at AS refresh_date,
    NULL::integer AS contact_id,
    NULL::integer AS "Lead Id",
    NULL::timestamp with time zone AS "Payment Date",
    NULL::text AS "Lead Name",
    NULL::character varying AS "Lead Email ID",
    NULL::character varying AS "Product",
    NULL::character varying AS "Sub-Product",
    NULL::text AS "Lead Type",
    mu.full_name AS "Rm_Name",
    mu.user_id AS "RM_Id",
    ml.name AS "Rm_center",
    NULL::character varying AS "reporting manager Name",
    NULL::integer AS "reporting manager Id",
    NULL::integer AS lead_age,
    NULL::character varying AS "Onboarded By Name",
    NULL::character varying AS "Onboarding User Location",
    NULL::character varying AS "Status",
    NULL::character varying AS "SubStatus",
    NULL::character varying AS "Lead Source",
    NULL::double precision AS adjustment_amount,
    NULL::integer AS amt_recd,
    NULL::character varying AS state_name,
    NULL::character varying AS city_name,
    NULL::character varying AS pin_code,
    NULL::integer AS onboarding_id,
    NULL::smallint AS payment_provider_id,
    NULL::text AS payment_type,
    NULL::text AS "Payment mode",
    NULL::integer AS payment_id,
    NULL::text AS status,
    NULL::text AS scenario,
    NULL::character varying AS "rm_Email Id",
    NULL::boolean AS is_active,
    NULL::character varying AS product,
    NULL::character varying AS "Sub Product",
    NULL::character varying AS flag,
    a.created_at,
    NULL::integer AS rm_id,
    a.lead_id,
    count(
        CASE
            WHEN mc.comment_id = 36 OR a.activity_type_id = 1 AND (a.call_duration <= 0::double precision OR a.call_duration IS NULL) THEN 1
            ELSE NULL::integer
        END) AS called,
    count(
        CASE
            WHEN (mc.comment_id = ANY (ARRAY[33, 61])) OR a.call_duration >= 600::double precision THEN 1
            ELSE NULL::integer
        END) AS "Detail Conversation",
    count(
        CASE
            WHEN mc.comment_id = 62 OR a.call_duration < 600::double precision AND a.call_duration > 0::double precision THEN 1
            ELSE NULL::integer
        END) AS "Had a Phone Conversation",
    sum(a.call_duration) AS "Call duration",
        CASE
            WHEN l.status_id = 5 AND (l.substatus_id = ANY (ARRAY[16, 17, 18, 19, 20, 21, 22, 2, 3, 24, 25, 26, 27, 28, 73, 74, 75, 54, 55, 66, 67, 68, 58])) THEN 'ONBOARDING'::character varying
            WHEN l.status_id = 6 AND (l.substatus_id = ANY (ARRAY[29, 30, 21, 32, 33, 34, 35, 36, 52, 53])) THEN 'SUBSCRIPTION'::character varying
            WHEN l.status_id = 7 AND (l.substatus_id = ANY (ARRAY[37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 71])) THEN 'SUBSCRIPTION'::character varying
            ELSE ms2.name
        END AS "group substatus",
    NULL::text AS lead_group_source,
    NULL::text AS utm_campaign,
    NULL::text AS utm_medium,
    NULL::date AS "Date of Birth",
    NULL::smallint AS "Age",
    NULL::text AS "Gender",
    NULL::text AS "Occupation",
    NULL::text AS "Income",
    'Activity'::text AS "Flag"
   FROM activity_selected a
     LEFT JOIN mst_comment mc ON (mc.comment_id = ANY (a.comment_ids)) AND (mc.comment_id = ANY (ARRAY[33, 36, 61, 62]))
     JOIN contact c ON a.contact_id = c.contact_id
     LEFT JOIN mst_user mu ON mu.user_id = a.rm_id
     LEFT JOIN mst_location ml ON ml.location_id = mu.location_id
     LEFT JOIN lead l ON a.lead_id = l.lead_id
     LEFT JOIN mst_lead_source mls ON l.lead_source_id = mls.lead_source_id
     LEFT JOIN mst_substatus ms2 ON ms2.substatus_id = l.substatus_id
  WHERE l.is_active
  GROUP BY mu.user_id, mu.full_name, ml.name, a.created_at, l.substatus_id, l.status_id, ms2.name, a.lead_id
 HAVING count(
        CASE
            WHEN mc.comment_id = 36 OR a.activity_type_id = 1 AND (a.call_duration <= 0::double precision OR a.call_duration IS NULL) THEN 1
            ELSE NULL::integer
        END) > 0 OR count(
        CASE
            WHEN (mc.comment_id = ANY (ARRAY[33, 61])) OR a.call_duration >= 600::double precision THEN 1
            ELSE NULL::integer
        END) > 0 OR count(
        CASE
            WHEN mc.comment_id = 62 OR a.call_duration < 600::double precision AND a.call_duration > 0::double precision THEN 1
            ELSE NULL::integer
        END) > 0)
UNION ALL
( WITH activity_selected AS (
         SELECT a_1.activity_id,
            a_1.company_id,
            a_1.lead_id,
            a_1.contact_id,
            a_1.contact_detail_id,
            a_1.customer_id,
            a_1.rm_id,
            a_1.activity_type_id,
            a_1.reference_id,
            a_1.meta_info,
            a_1.origin,
            a_1.call_duration,
            a_1.sent_to,
            a_1.status_id,
            a_1.substatus_id,
            a_1.location_id,
            a_1.department_id,
            a_1.reporting_manager_id,
            a_1.team_id,
            a_1.comment_ids,
            a_1.additional_comments,
            a_1.is_visible,
            a_1.tags_id,
            a_1.forward_to,
            a_1.message_id,
            a_1.score,
            a_1.conversion_interaction,
            a_1.created_at,
            a_1.created_by,
            a_1.updated_at,
            a_1.updated_by
           FROM activity a_1
          WHERE (a_1.activity_type_id = ANY (ARRAY[1, 7])) AND a_1.created_at::date >= (CURRENT_DATE - 91) OR a_1.status_id >= 5
        )
 SELECT a.created_at AS refresh_date,
    ll.contact_id,
    ll.lead_id AS "Lead Id",
    p.payment_date AS "Payment Date",
    c.full_name AS "Lead Name",
    c.email_address AS "Lead Email ID",
    mp.name AS "Product",
    ms3.name AS "Sub-Product",
    NULL::text AS "Lead Type",
    mu.full_name AS "Rm_Name",
    mu.user_id AS "RM_Id",
    ml.name AS "Rm_center",
    NULL::character varying AS "reporting manager Name",
    NULL::integer AS "reporting manager Id",
    NULL::integer AS lead_age,
    NULL::character varying AS "Onboarded By Name",
    NULL::character varying AS "Onboarding User Location",
    NULL::character varying AS "Status",
    NULL::character varying AS "SubStatus",
    NULL::character varying AS "Lead Source",
    NULL::double precision AS adjustment_amount,
    NULL::integer AS amt_recd,
    NULL::character varying AS state_name,
    NULL::character varying AS city_name,
    NULL::character varying AS pin_code,
    p.onboarding_id,
    NULL::smallint AS payment_provider_id,
    NULL::text AS payment_type,
    NULL::text AS "Payment mode",
    p.payment_id,
    s.status,
    s.scenario,
    NULL::character varying AS "rm_Email Id",
    NULL::boolean AS is_active,
    mp2.name AS product,
    ms4.name AS "Sub Product",
        CASE
            WHEN mp2.product_id = 1 AND (ms4.sub_product_id = ANY (ARRAY[1, 2, 3])) THEN 'Retail'::text
            WHEN mp2.product_id = 1 AND ms4.sub_product_id = 4 THEN 'Retail PMP'::text
            WHEN mp2.product_id = 3 AND (ms4.sub_product_id = ANY (ARRAY[25, 27, 24, 23, 29, 26, 30, 28])) THEN 'Multiplyrr'::text
            WHEN mp2.product_id = 2 AND (ms4.sub_product_id = ANY (ARRAY[5, 8, 11])) THEN 'Dhanwaan'::text
            ELSE NULL::text
        END AS flag,
    ll.created_at,
    NULL::integer AS rm_id,
    a.lead_id,
    count(
        CASE
            WHEN mc.comment_id = 36 OR a.activity_type_id = 1 AND (a.call_duration <= 0::double precision OR a.call_duration IS NULL) THEN 1
            ELSE NULL::integer
        END) AS called,
    count(
        CASE
            WHEN (mc.comment_id = ANY (ARRAY[33, 61])) OR a.call_duration >= 600::double precision THEN 1
            ELSE NULL::integer
        END) AS "Detail Conversation",
    count(
        CASE
            WHEN mc.comment_id = 62 OR a.call_duration < 600::double precision AND a.call_duration > 0::double precision THEN 1
            ELSE NULL::integer
        END) AS "Had a Phone Conversation",
    sum(a.call_duration) AS "Call duration",
    NULL::text AS "group substatus",
    NULL::text AS lead_group_source,
    NULL::text AS utm_campaign,
    NULL::text AS utm_medium,
    NULL::date AS "Date of Birth",
    NULL::smallint AS "Age",
    NULL::text AS "Gender",
    NULL::text AS "Occupation",
    NULL::text AS "Income",
    'Combine'::text AS "Flag"
   FROM lead ll
     LEFT JOIN activity_selected a ON ll.lead_id = a.lead_id AND ll.rm_id = a.rm_id
     LEFT JOIN mst_comment mc ON (mc.comment_id = ANY (a.comment_ids)) AND (mc.comment_id = ANY (ARRAY[33, 36, 61, 62]))
     JOIN contact c ON ll.contact_id = c.contact_id
     LEFT JOIN mst_user mu ON mu.user_id = ll.rm_id
     LEFT JOIN mst_user mu2 ON mu2.user_id = a.rm_id
     LEFT JOIN mst_location ml ON ml.location_id = mu.location_id
     LEFT JOIN mst_location ml2 ON ml2.location_id = mu2.location_id
     LEFT JOIN mst_lead_source mls ON ll.lead_source_id = mls.lead_source_id
     LEFT JOIN mst_substatus ms2 ON ms2.substatus_id = ll.substatus_id
     LEFT JOIN payment p ON p.lead_id = ll.lead_id
     LEFT JOIN senario s ON s.payment_id = p.payment_id
     LEFT JOIN mst_product mp ON ll.product_id = mp.product_id
     LEFT JOIN mst_subproduct ms3 ON ms3.sub_product_id = ANY (ll.sub_product_ids)
     LEFT JOIN mst_subproduct ms4 ON ms4.sub_product_id = ANY (mu.sub_product_ids)
     LEFT JOIN mst_product mp2 ON mp2.product_id = ms4.product_id
  WHERE ll.is_active
  GROUP BY mu.user_id, mp2.product_id, ms4.sub_product_id, mp2.name, ms4.name, mu.full_name, ml.name, a.created_at, ll.substatus_id, ll.status_id, ms2.name, ll.created_at, a.lead_id, p.amount, p.payment_id, p.onboarding_id, mp.name, ms3.name, s.status, ll.contact_id, ll.lead_id, c.full_name, c.email_address, s.scenario)
UNION ALL
 SELECT l.created_at AS refresh_date,
    l.contact_id,
    NULL::integer AS "Lead Id",
    p.payment_date AS "Payment Date",
    NULL::text AS "Lead Name",
    NULL::character varying AS "Lead Email ID",
    NULL::character varying AS "Product",
    NULL::character varying AS "Sub-Product",
    lt.lead_type AS "Lead Type",
    NULL::character varying AS "Rm_Name",
    NULL::integer AS "RM_Id",
    NULL::character varying AS "Rm_center",
    NULL::character varying AS "reporting manager Name",
    NULL::integer AS "reporting manager Id",
    NULL::integer AS lead_age,
    NULL::character varying AS "Onboarded By Name",
    ml.name AS "Onboarding User Location",
    ms.name AS "Status",
    ms2.name AS "SubStatus",
    COALESCE(l.utm_source, mls.name)::text AS "Lead Source",
    NULL::double precision AS adjustment_amount,
    NULL::integer AS amt_recd,
    NULL::character varying AS state_name,
    NULL::character varying AS city_name,
    NULL::character varying AS pin_code,
    NULL::integer AS onboarding_id,
    NULL::smallint AS payment_provider_id,
    NULL::text AS payment_type,
    NULL::text AS "Payment mode",
    p.payment_id,
    NULL::text AS status,
    NULL::text AS scenario,
    NULL::character varying AS "rm_Email Id",
    NULL::boolean AS is_active,
    NULL::character varying AS product,
    NULL::character varying AS "Sub Product",
    NULL::character varying AS flag,
    l.created_at,
    NULL::integer AS rm_id,
    l.lead_id,
    NULL::bigint AS called,
    NULL::bigint AS "Detail Conversation",
    NULL::bigint AS "Had a Phone Conversation",
    NULL::double precision AS "Call duration",
    NULL::character varying AS "group substatus",
        CASE
            WHEN COALESCE(l.utm_source, mls.name)::text = 'DSP_programmatic'::text THEN 'DSP_programmatic'::text
            WHEN COALESCE(l.utm_source, mls.name)::text = 'quora'::text THEN 'Quora'::text
            WHEN COALESCE(l.utm_source, mls.name)::text = 'Missed Call'::text THEN 'Missed Call'::text
            WHEN COALESCE(l.utm_source, mls.name)::text = 'youtube'::text OR COALESCE(l.utm_source, mls.name)::text = 'Youtube'::text THEN 'Youtube'::text
            WHEN lower(COALESCE(l.utm_source, mls.name)::text) = 'yahoo'::text THEN 'Yahoo'::text
            WHEN COALESCE(l.utm_source, mls.name)::text ~~* '%organic%'::text OR COALESCE(l.utm_source, mls.name)::text ~~* '%Direct Traffic%'::text OR COALESCE(l.utm_source, mls.name)::text ~~* '%Direct Traffic%'::text OR COALESCE(l.utm_source, mls.name)::text ~~* '%Zopim%'::text OR COALESCE(l.utm_source, mls.name)::text ~~* '%WhatsApp%'::text OR COALESCE(l.utm_source, mls.name)::text ~~* '%Moengage%'::text OR COALESCE(l.utm_source, mls.name)::text ~~* '%website%'::text THEN 'Organic'::text
            WHEN COALESCE(l.utm_source, mls.name)::text = 'Inbound Phone call'::text THEN 'Inbound Phone call'::text
            WHEN COALESCE(l.utm_source, mls.name)::text ~~* '%Customer%'::text THEN 'Customer Referral'::text
            WHEN COALESCE(l.utm_source, mls.name)::text ~~* '%fball%'::text THEN 'Facebook'::text
            WHEN lower(COALESCE(l.utm_source, mls.name)::text) ~~* '%outbrain%'::text THEN 'Outbrain'::text
            WHEN (COALESCE(l.utm_source, mls.name)::text ~~* '%Google%'::text OR COALESCE(l.utm_source, mls.name)::text ~~* '%Google%'::text) AND (lower(COALESCE(l.utm_source, mls.name)::text) ~~* '%discovery%'::text OR lower(COALESCE(l.utm_source, mls.name)::text) ~~* '%display%'::text) THEN 'Google Discovery'::text
            WHEN lower(COALESCE(l.utm_source, mls.name)::text) ~~* '%google%'::text AND (lower(COALESCE(l.utm_source, mls.name)::text) ~~* '%nonbrand%'::text OR lower(COALESCE(l.utm_source, mls.name)::text) ~~* '%brand%'::text) THEN 'Google Search (NB)'::text
            WHEN COALESCE(l.utm_source, mls.name)::text ~~* '%Affiliate%'::text OR lower(COALESCE(l.utm_source, mls.name)::text) ~~* '%digismart%'::text OR lower(COALESCE(l.utm_source, mls.name)::text) ~~* '%geoads%'::text THEN 'Affiliate'::text
            ELSE 'Other'::text
        END AS lead_group_source,
    l.utm_campaign,
    l.utm_medium,
    NULL::date AS "Date of Birth",
    NULL::smallint AS "Age",
    NULL::text AS "Gender",
    NULL::text AS "Occupation",
    NULL::text AS "Income",
    'Lead Details'::text AS "Flag"
   FROM lead l
     LEFT JOIN ( SELECT DISTINCT ON (p_1.lead_id) p_1.payment_id,
            p_1.onboarding_id,
            p_1.contact_id,
            p_1.trackrr_customer_id,
            p_1.lead_id,
            p_1.sub_product_id,
            p_1.payment_provider,
            p_1.amount,
            p_1.payment_utr_number,
            p_1.remitter_bank_name,
            p_1.remitter_bank_branch,
            p_1.remitter_ifsc_code,
            p_1.payment_date,
            p_1.provider_order_id,
            p_1.provider_reference_id,
            p_1.payment_response,
            p_1.emandate_collection_id,
            p_1.company_id,
            p_1.created_by,
            p_1.updated_by,
            p_1.updated_at,
            p_1.created_at,
            p_1.payment_method,
            p_1.payment_gateway_charges,
            p_1.payment_gateway_gst,
            p_1.net_amount,
            p_1.additional_info,
            p_1.trackrr_sales_source_id,
            p_1.gst_amount,
            p_1.tax_deducted_at_source_amount,
            p_1.tax_deducted_at_source_challan_no,
            p_1.tax_deducted_at_source_challan_url,
            p_1.tax_deducted_at_source_challan_date,
            p_1.provider_account_mid
           FROM payment p_1) p ON p.lead_id = l.lead_id
     LEFT JOIN mst_lead_source mls ON mls.lead_source_id = l.lead_source_id
     LEFT JOIN mst_user mu ON mu.user_id = l.rm_id
     LEFT JOIN mst_location ml ON ml.location_id = mu.location_id
     LEFT JOIN ( SELECT ll.lead_id,
                CASE
                    WHEN bool_or(ll.substatus_id = 3) THEN 'repeat_lead'::text
                    ELSE 'new_lead'::text
                END AS lead_type
           FROM lead_log ll
          GROUP BY ll.lead_id) lt ON l.lead_id = lt.lead_id
     LEFT JOIN mst_status ms ON l.status_id = ms.status_id
     LEFT JOIN mst_substatus ms2 ON ms2.substatus_id = l.substatus_id
  WHERE l.is_active;