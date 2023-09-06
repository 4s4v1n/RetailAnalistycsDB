CREATE OR REPLACE FUNCTION avg_transactions_by_date_range(p_start_date DATE, p_end_date DATE)
    RETURNS TABLE
            (
                Customer_ID       INTEGER,
                Transaction_Count BIGINT
            )
AS
$$
BEGIN
    RETURN QUERY
        SELECT t.customer_card_id, COUNT(t.transaction_id) AS transaction_count
        FROM transactions AS t
        WHERE t.transaction_datetime BETWEEN p_start_date AND p_end_date
        GROUP BY t.customer_card_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION create_personal_offer(
    p_start_date DATE,
    p_end_date DATE,
    p_added_transactions INTEGER,
    p_max_churn_index NUMERIC,
    p_max_discount_rate NUMERIC,
    p_acceptable_margin_rate NUMERIC
)
    RETURNS TABLE
            (
                Customer_ID                 INTEGER,
                Start_Date                  DATE,
                End_Date                    DATE,
                Required_Transactions_Count INTEGER,
                Group_Name                  VARCHAR,
                Offer_Discount_Depth        NUMERIC
            )
AS
$$
DECLARE
    avg_transaction_data RECORD;
    selected_group_id    INTEGER;
    max_allowed_discount NUMERIC;
    rounded_min_discount NUMERIC;
BEGIN
    FOR avg_transaction_data IN SELECT * FROM avg_transactions_by_date_range(p_start_date, p_end_date)
        LOOP
            selected_group_id := (SELECT vg.group_id
                                  FROM view_groups AS vg
                                  WHERE vg.customer_id = avg_transaction_data.Customer_ID
                                    AND vg.group_churn_rate <= p_max_churn_index
                                    AND vg.group_discount_share < p_max_discount_rate
                                  ORDER BY vg.group_affinity_index DESC
                                  LIMIT 1);

            max_allowed_discount := p_acceptable_margin_rate * (SELECT vg.group_margin
                                                                FROM view_groups AS vg
                                                                WHERE vg.customer_id = avg_transaction_data.Customer_ID
                                                                  AND vg.group_id = selected_group_id);
            rounded_min_discount := ceil((SELECT vg.group_minimum_discount
                                          FROM view_groups vg
                                          WHERE vg.customer_id = avg_transaction_data.Customer_ID
                                            AND vg.group_id = selected_group_id) / 0.05) * 0.05 * 100;

            IF rounded_min_discount <= max_allowed_discount THEN
                Customer_ID := avg_transaction_data.Customer_ID;
                Start_Date := p_start_date;
                End_Date := p_end_date;
                Required_Transactions_Count := avg_transaction_data.Transaction_Count + p_added_transactions;
                Group_Name := (SELECT gs.group_name FROM groups_sku gs WHERE gs.group_id = selected_group_id);
                Offer_Discount_Depth := rounded_min_discount;
                RETURN NEXT;
            END IF;
        END LOOP;
END;
$$ LANGUAGE plpgsql;
