--  analysis_date - returns last date of analysis formation
CREATE OR REPLACE FUNCTION analysis_date()
RETURNS TIMESTAMP
AS
$$
BEGIN
    RETURN (
        SELECT max(analysis_formation)
        FROM date_of_analysis_formation
    );
END;
$$ LANGUAGE plpgsql;

--  diff_days_between_dates - return difference between two dates in days AS float number
CREATE OR REPLACE FUNCTION diff_days_between_dates(first TIMESTAMP, second TIMESTAMP)
RETURNS NUMERIC
AS
$$
DECLARE
    time_interval INTERVAL := first - second;
BEGIN
    RETURN abs(date_part('day', time_interval) + date_part('hour', time_interval) / 24
                + date_part('minute', time_interval) / (24 * 60)
                + date_part('second', time_interval) / ( 24 * 60 * 60)
    );
END;
$$ LANGUAGE plpgsql;

--  primary_store_id - return primary store for customer
CREATE OR REPLACE FUNCTION primary_store_id(target_customer BIGINT)
RETURNS BIGINT
AS
$$
BEGIN
    RETURN (

        --  table about customers and stores, that has visits count, last visit date and rank of store
        WITH stores_stat AS (
            SELECT t.transaction_store_id,
                   count(*) OVER w1 AS visits_count,
                   max(t.transaction_datetime) OVER w1 AS last_visit_date,
                   row_number() OVER w2 AS rank
            FROM personal_data p
                JOIN cards c on p.customer_id = c.customer_id
                JOIN transactions t on c.customer_card_id = t.customer_card_id
            WHERE t.transaction_datetime <= analysis_date()
                AND p.customer_id = target_customer
            WINDOW w1 AS (PARTITION BY t.transaction_store_id),
                   w2 AS (ORDER BY t.transaction_datetime DESC)
        ),

        --  table with most popular stores for each customer
        popular_store AS (
            SELECT DISTINCT
                first_value(transaction_store_id) OVER
                    (ORDER BY visits_count DESC, last_visit_date DESC) AS popular_store_id
            FROM stores_stat),

        --  checking 3 last stores and that customer where there
        last_store AS (
            SELECT DISTINCT
                max(transaction_store_id) AS last_store_id,
                max(transaction_store_id) = min(transaction_store_id) AS is_last
            FROM stores_stat
            WHERE rank <= 3
        )

        --  get main store
        SELECT
            CASE
            WHEN (SELECT is_last
                  FROM last_store last)
            THEN (SELECT last_store_id
                  FROM last_store last)
            ELSE (SELECT popular_store_id
                  FROM popular_store)
        END AS customer_primary_store_id
    );
END;
$$ LANGUAGE plpgsql;

--  view that contains client_id, customer average check, customer average check, customer frequency,
--  customer frequency segment, customer inactive period, customer churn rate, customer churn segment,
--  customer segment, customer primary store
CREATE OR REPLACE VIEW view_customers AS
(

--  temporary table for statistic calculation
WITH stat_transaction AS (
SELECT c.customer_id,
       avg(t.transaction_summ) AS customer_average_check,
       diff_days_between_dates(first := max(t.transaction_datetime),
                               second := min(t.transaction_datetime)) / count(*) AS customer_frequency,
       diff_days_between_dates(first := analysis_date(), second := max(t.transaction_datetime)) AS customer_inactive_period
FROM personal_data p
    JOIN cards c on p.customer_id = c.customer_id
    JOIN transactions t on c.customer_card_id = t.customer_card_id
GROUP BY c.customer_id
),

--  calculate rank from average check, order frequency and churn segment
stat_rank AS (
SELECT customer_id,
       customer_average_check,
       cume_dist() OVER (ORDER BY customer_average_check) AS rank_check, customer_frequency,
       cume_dist() OVER (ORDER BY customer_frequency) AS rank_frequency, customer_inactive_period,
       customer_inactive_period / customer_frequency AS customer_churn_rate
FROM stat_transaction
),

--  segment from average check, frequency and churn rate
stat_segment AS (
SELECT customer_id,
       customer_average_check,
       CASE
           WHEN rank_check <= 0.1 THEN 'High'
           WHEN rank_check <= 0.35 THEN 'Medium'
           ELSE 'Low'
           END AS customer_average_check_segment,
       customer_frequency,
       CASE
           WHEN rank_frequency <= 0.1 THEN 'Often'
           WHEN rank_frequency <= 0.35 THEN 'Occasionally'
           ELSE 'Rarely'
           END AS customer_frequency_segment,
       customer_inactive_period,
       customer_churn_rate,
       CASE
           WHEN customer_churn_rate < 2 THEN 'Low'
           WHEN customer_churn_rate < 5 THEN 'Medium'
           ELSE 'High'
           END AS customer_churn_segment
FROM stat_rank
)

--  output view table
SELECT s.customer_id,
       s.customer_average_check,
       s.customer_average_check_segment,
       s.customer_frequency,
       s.customer_frequency_segment,
       s.customer_inactive_period,
       s.customer_churn_rate,
       s.customer_churn_segment,
       CASE customer_average_check_segment
           WHEN 'Low'
               THEN 0
           WHEN 'Medium'
               THEN 9
           ELSE 18 END +
       CASE customer_frequency_segment
           WHEN 'Rarely'
               THEN 0
           WHEN 'Occasionally'
               THEN 3
           ELSE 6 END +
       CASE customer_churn_segment
           WHEN 'Low'
               THEN 1
           WHEN 'Medium'
               THEN 2
           ELSE 3 END AS customer_segment,
       primary_store_id(target_customer := s.customer_id) AS customer_primary_store
FROM stat_segment s
ORDER BY customer_id
);
