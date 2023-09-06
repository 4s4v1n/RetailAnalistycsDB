--  view that contains customer id, transaction id, transaction datetime, item group, amount of purchase,
--  base item price, paid price
CREATE OR REPLACE VIEW view_purchase_history AS
(
SELECT DISTINCT
    p.customer_id,
    t.transaction_id,
    t.transaction_datetime,
    s.group_id,
    sum(c2.sku_amount * s2.sku_purchase_price) OVER wnd AS group_cost,
    sum(c2.sku_summ) OVER wnd AS group_summ,
    sum(c2.sku_summ_paid) OVER wnd as group_summ_paid
FROM personal_data p
    JOIN cards c on p.customer_id = c.customer_id
    JOIN transactions t on c.customer_card_id = t.customer_card_id AND t.transaction_datetime <= analysis_date()
    JOIN checks c2 on t.transaction_id = c2.transaction_id
    JOIN sku s on s.sku_id = c2.sku_id
    JOIN stores s2 on s.sku_id = s2.sku_id AND t.transaction_store_id = s2.transaction_store_id
WINDOW wnd AS (PARTITION BY p.customer_id, t.transaction_id, transaction_datetime, s.group_id)
);
