DROP FUNCTION IF EXISTS fnc_personal_offers_aimed_at_cross_selling;

CREATE FUNCTION fnc_personal_offers_aimed_at_cross_selling(
    num_groups INTEGER,
    max_churn_index NUMERIC,
    max_consumption_stability_index NUMERIC,
    max_sku_share NUMERIC,
    allowable_margin_share NUMERIC
)
    RETURNS TABLE
            (
                customer_id INTEGER,
               sku_name VARCHAR,
               offer_discount_depth NUMERIC
            )
AS
$$
WITH client_groups AS (
    SELECT customer_id,
           group_id,
           group_affinity_index
    FROM (
            SELECT vg.customer_id,
                   group_id,
                   group_affinity_index,
                   rank() OVER (PARTITION BY vg.customer_id ORDER BY group_id) AS num
            FROM view_groups vg
            JOIN (
                SELECT customer_id,
                       max(group_affinity_index) AS max_group_affinity_index
                FROM view_groups vg
                WHERE group_churn_rate <= max_churn_index AND group_stability_index < max_consumption_stability_index
                GROUP BY customer_id) AS g
            ON vg.customer_id = g.customer_id AND vg.group_affinity_index = g.max_group_affinity_index) AS sg
    WHERE num <= num_groups),
max_sku_margin AS (
    SELECT t1.customer_id,
           t1.group_id,
           sku_id AS max_sku_margin_id,
           sku_purchase_price,
           sku_retail_price,
           margin,
           customer_primary_store
    FROM (
            SELECT client_groups.customer_id,
                   client_groups.group_id,
                   sku.sku_id,
                   sku_purchase_price,
                   sku_retail_price,
                   sku_retail_price - sku_purchase_price AS margin,
                   customer_primary_store
            FROM client_groups
            INNER JOIN view_customers ON client_groups.customer_id = view_customers.customer_id
            INNER JOIN sku ON client_groups.group_id = sku.group_id
            INNER JOIN stores ON customer_primary_store = stores.transaction_store_id
                       AND sku.sku_id = stores.sku_id) AS t1
    INNER JOIN (
                SELECT client_groups.customer_id,
                       client_groups.group_id,
                       max(sku_retail_price - sku_purchase_price) max_margin
                FROM client_groups
                INNER JOIN view_customers ON client_groups.customer_id = view_customers.customer_id
                INNER JOIN sku ON client_groups.group_id = sku.group_id
                INNER JOIN stores ON customer_primary_store = stores.transaction_store_id AND sku.sku_id = stores.sku_id
                GROUP BY client_groups.customer_id, client_groups.group_id) AS t2
        ON t1.customer_id = t2.customer_id AND t1.group_id = t2.group_id AND t1.margin = t2.max_margin),
group_part_sku AS (
    SELECT max_sku_margin.*
    FROM max_sku_margin
    INNER JOIN (
                SELECT max_sku_margin.customer_id,
                       max_sku_margin.group_id,
                        count(*) AS group_transactions_count
                FROM max_sku_margin
                INNER JOIN cards ON max_sku_margin.customer_id = cards.customer_id
                INNER JOIN transactions ON cards.customer_card_id = transactions.customer_card_id
                GROUP BY max_sku_margin.customer_id, max_sku_margin.group_id) AS group_transactions
        ON max_sku_margin.customer_id = group_transactions.customer_id
               AND max_sku_margin.group_id = group_transactions.group_id
    INNER JOIN (
                SELECT max_sku_margin.customer_id,
                       max_sku_margin.group_id,
                       count(*) AS sku_transactions_count
                FROM max_sku_margin
                INNER JOIN cards ON max_sku_margin.customer_id = cards.customer_id
                INNER JOIN transactions ON cards.customer_card_id = transactions.customer_card_id
                INNER JOIN checks ON transactions.transaction_id = checks.transaction_id
                           AND max_sku_margin.max_sku_margin_id = checks.sku_id
                GROUP BY max_sku_margin.customer_id, max_sku_margin.group_id) AS sku_transactions
        ON max_sku_margin.customer_id = sku_transactions.customer_id
               AND max_sku_margin.group_id = sku_transactions.group_id
               AND sku_transactions_count * 100.0 / group_transactions_count <= max_sku_share),
discount_margin_part AS(
    SELECT group_part_sku.*,
           sku.sku_name,
           30.0 * view_groups.group_minimum_discount / 30 * 100 AS minimum_discount
    FROM group_part_sku
    INNER JOIN sku ON group_part_sku.max_sku_margin_id = sku.sku_id
    INNER JOIN view_groups ON group_part_sku.customer_id = view_groups.customer_id
               AND group_part_sku.group_id = view_groups.group_id)
SELECT customer_id,
       sku_name,
       minimum_discount AS offer_discount_depth
FROM discount_margin_part
WHERE allowable_margin_share * margin / sku_retail_price >= minimum_discount
$$ LANGUAGE sql;


SELECT * FROM fnc_personal_offers_aimed_at_cross_selling(5, 3, 0.5, 100, 30);
SELECT * FROM fnc_personal_offers_aimed_at_cross_selling(12, 13, 0.7, 100, 30);
