--  group_min_discount - return minimal discount by group for each client
CREATE OR REPLACE FUNCTION group_min_discount(target_customer_id BIGINT, target_group_id BIGINT)
RETURNS NUMERIC
AS
$$
BEGIN
    RETURN (
        SELECT coalesce(min(c2.sku_discount / c2.sku_summ), 0)
        FROM personal_data p
        JOIN cards c on p.customer_id = c.customer_id AND p.customer_id = target_customer_id
        JOIN transactions t on c.customer_card_id = t.customer_card_id
        JOIN checks c2 on t.transaction_id = c2.transaction_id AND c2.sku_discount > 0
        JOIN sku s on s.sku_id = c2.sku_id AND s.group_id = target_group_id
    );
END;
$$ LANGUAGE plpgsql;

--  view that contains customer id, group id, date of first purchase from group, date of last purchase from group,
--  amount of transactions with group, frequency of purchase from group, minimal discount by group
CREATE OR REPLACE VIEW view_periods AS
(

--  temporary table for statistics, that contains: customer id, group id, first and last dates of purchase from group,
--  amount of transactions by group
WITH customer_and_group_statistics AS (
    SELECT
        p.customer_id,
        s.group_id,
        min(t.transaction_datetime) as first_group_purchase_date,
        max(t.transaction_datetime) as last_group_purchase_date,
        count(DISTINCT t.transaction_id) as group_purchase
    FROM personal_data p
    JOIN cards c ON p.customer_id = c.customer_id
    JOIN transactions t ON c.customer_card_id = t.customer_card_id
    JOIN checks c2 ON t.transaction_id = c2.transaction_id
    JOIN sku s ON s.sku_id = c2.sku_id
    GROUP BY p.customer_id, s.group_id
    )

-- output view table
SELECT customer_id,
       group_id,
       first_group_purchase_date,
       last_group_purchase_date,
       group_purchase,
       (diff_days_between_dates(first := first_group_purchase_date, second := last_group_purchase_date) + 1)
       / group_purchase AS group_frequency,
       group_min_discount(target_customer_id := customer_id, target_group_id := group_id) AS group_min_discount
FROM customer_and_group_statistics
);
