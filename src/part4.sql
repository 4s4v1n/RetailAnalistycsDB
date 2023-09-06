CREATE OR REPLACE FUNCTION avg_check_by_num_transactions(num_transactions INTEGER)
    RETURNS TABLE
            (
                Customer_ID   INTEGER,
                Average_Check NUMERIC
            )
AS
$$
BEGIN
    RETURN QUERY
        SELECT t.customer_id,
               AVG(t.transaction_summ) as Average_Check
        FROM (SELECT c.customer_id,
                     tr.transaction_summ,
                     tr.transaction_datetime,
                     (SELECT COUNT(*)
                      FROM transactions
                      WHERE customer_card_id = tr.customer_card_id
                        AND transaction_datetime >= tr.transaction_datetime) as transaction_num
              FROM transactions AS tr
                       JOIN cards c ON tr.customer_card_id = c.customer_card_id) AS t
        WHERE t.transaction_num <= num_transactions
        GROUP BY t.customer_id;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION avg_check_by_date_range(start_date DATE, end_date DATE)
    RETURNS TABLE
            (
                Customer_ID   INTEGER,
                Average_Check NUMERIC
            )
AS
$$
BEGIN
    IF (start_date > end_date) THEN
        RAISE EXCEPTION 'incorrect data';
    END IF;
    RETURN QUERY
        SELECT c.customer_id,
               AVG(trans.transaction_summ) as Average_Check
        FROM transactions AS trans
                 JOIN cards c ON trans.customer_card_id = c.customer_card_id
        WHERE trans.transaction_datetime BETWEEN start_date AND end_date
        GROUP BY c.customer_id;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION calc_growth_offer(
    method INTEGER,
    start_date DATE,
    end_date DATE,
    num_transactions INTEGER,
    growth_coefficient NUMERIC,
    max_churn_index NUMERIC,
    max_discount_rate NUMERIC,
    acceptable_margin_rate NUMERIC
)
    RETURNS TABLE
            (
                Customer_ID            INTEGER,
                Required_Check_Measure NUMERIC,
                Group_Name             VARCHAR,
                Offer_Discount_Depth   NUMERIC
            )
AS
$$
DECLARE
    avg_check_data       RECORD;
    selected_group_id    INTEGER;
    max_allowed_discount NUMERIC;
    rounded_min_discount NUMERIC;
BEGIN
    IF method = 1 THEN
        FOR avg_check_data IN SELECT * FROM avg_check_by_date_range(start_date, end_date)
            LOOP
                selected_group_id := (SELECT vg.group_id
                                      FROM view_groups AS vg
                                      WHERE vg.customer_id = avg_check_data.Customer_ID
                                        AND vg.group_churn_rate <= max_churn_index
                                        AND vg.group_discount_share < max_discount_rate
                                      ORDER BY vg.group_affinity_index DESC
                                      LIMIT 1);

                max_allowed_discount := acceptable_margin_rate * (SELECT vg.group_margin
                                                                  FROM view_groups AS vg
                                                                  WHERE vg.customer_id = avg_check_data.Customer_ID
                                                                    AND vg.group_id = selected_group_id);

                rounded_min_discount := ceil((SELECT vg.group_minimum_discount
                                              FROM view_groups AS vg
                                              WHERE vg.customer_id = avg_check_data.Customer_ID
                                                AND vg.group_id = selected_group_id) / 0.05) * 0.05 * 100;

                IF rounded_min_discount <= max_allowed_discount THEN
                    Customer_ID := avg_check_data.Customer_ID;
                    Required_Check_Measure := avg_check_data.Average_Check * growth_coefficient;
                    Group_Name := (SELECT gs.group_name FROM groups_sku gs WHERE gs.group_id = selected_group_id);
                    Offer_Discount_Depth := rounded_min_discount;
                    RETURN NEXT;
                END IF;
            END LOOP;
    ELSIF method = 2 THEN
        FOR avg_check_data IN SELECT * FROM avg_check_by_num_transactions(num_transactions)
            LOOP
                selected_group_id := (SELECT vg.group_id
                                      FROM view_groups AS vg
                                      WHERE vg.customer_id = avg_check_data.Customer_ID
                                        AND vg.group_churn_rate <= max_churn_index
                                        AND vg.group_discount_share < max_discount_rate
                                      ORDER BY vg.group_affinity_index DESC
                                      LIMIT 1);

                max_allowed_discount := acceptable_margin_rate * (SELECT vg.group_margin
                                                                  FROM view_groups vg
                                                                  WHERE vg.customer_id = avg_check_data.Customer_ID
                                                                    AND vg.group_id = selected_group_id);

                rounded_min_discount := ceil((SELECT vg.group_minimum_discount
                                              FROM view_groups vg
                                              WHERE vg.customer_id = avg_check_data.Customer_ID
                                                AND vg.group_id = selected_group_id) / 0.05) * 0.05 * 100;

                IF rounded_min_discount <= max_allowed_discount THEN
                    Customer_ID := avg_check_data.Customer_ID;
                    Required_Check_Measure := avg_check_data.Average_Check * growth_coefficient;
                    Group_Name := (SELECT gs.group_name FROM groups_sku AS gs WHERE gs.group_id = selected_group_id);
                    Offer_Discount_Depth := rounded_min_discount;
                    RETURN NEXT;
                END IF;
            END LOOP;
    ELSE
        RAISE EXCEPTION 'incorrect method: %', method;
    END IF;
END;
$$ LANGUAGE plpgsql;
