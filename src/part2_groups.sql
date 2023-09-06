--  affinity_group_index - return rate of affinity by customer and group ids
CREATE OR REPLACE FUNCTION group_affinity_index(target_customer_id BIGINT, target_group_id BIGINT)
RETURNS NUMERIC
AS
$$
BEGIN
    RETURN (
        SELECT (
            SELECT p.group_purchase::NUMERIC / count(DISTINCT ph.transaction_id)
            FROM view_purchase_history ph
            WHERE ph.customer_id = target_customer_id
            AND ph.transaction_datetime BETWEEN p.first_group_purchase_date AND p.last_group_purchase_date
        )
        FROM view_periods p
        WHERE P.customer_id = target_customer_id AND p.group_id = target_group_id
    );
END;
$$ LANGUAGE plpgsql;

--  group_churn_rate - return rate of churn, days after last transaction by purchase frequency
CREATE OR REPLACE FUNCTION group_churn_rate(target_customer_id BIGINT, target_group_id BIGINT)
RETURNS NUMERIC
AS
$$
BEGIN
    RETURN (
        SELECT diff_days_between_dates(first := analysis_date(),
                                       second := p.last_group_purchase_date) / p.group_frequency
        FROM view_periods p
        WHERE p.customer_id = target_customer_id AND p.group_id = target_group_id
    );
END;
$$ LANGUAGE plpgsql;

--  group_stability_rate - return stability rate, calculated by days between transactions and average days
CREATE OR REPLACE FUNCTION group_stability_index(target_customer_id BIGINT, target_group_id BIGINT)
RETURNS NUMERIC
AS
$$
DECLARE
    target_group_frequency NUMERIC := (
        SELECT group_frequency
        FROM view_periods
        WHERE customer_id = target_customer_id AND group_id = target_group_id
    );
BEGIN
    RETURN (
        WITH calculate_interval AS (
            SELECT coalesce(diff_days_between_dates(first := vph.transaction_datetime,
                second := lag(vph.transaction_datetime) OVER (ORDER BY vph.transaction_datetime)), 0) AS target_interval
            FROM view_purchase_history vph
            WHERE vph.customer_id = target_customer_id AND vph.group_id = target_group_id
        )
        SELECT coalesce(avg(abs(target_interval - target_group_frequency) / target_group_frequency), 0)
        FROM calculate_interval
        WHERE target_interval > 0
    );
END;
$$ LANGUAGE plpgsql;

--  group_margin - return margin by group
CREATE OR REPLACE FUNCTION group_margin(target_customer_id BIGINT, target_group_id BIGINT, method INT, count INT)
RETURNS NUMERIC
AS
$$
DECLARE
    group_margin NUMERIC;
    first_date TIMESTAMP := analysis_date() - (INTERVAL '1 day') *  count;
    last_date TIMESTAMP := analysis_date();
BEGIN
    IF method = 1
        THEN
            group_margin := (
                SELECT sum(group_summ_paid - group_cost)
                FROM view_purchase_history
                WHERE customer_id = target_customer_id AND group_id = target_group_id
                    AND transaction_datetime BETWEEN first_date AND last_date
            );
        ELSE
            group_margin := (
                WITH solo_margin AS (
                    SELECT group_summ_paid - group_cost AS margin
                    FROM view_purchase_history
                    WHERE customer_id = target_customer_id AND group_id = target_group_id
                    LIMIT count
                )
                SELECT sum(margin)
                FROM solo_margin
            );
    END IF;

    RETURN group_margin;
END;
$$ LANGUAGE plpgsql;

--  group_discount_share - return part rate of transactions in group
CREATE OR REPLACE FUNCTION group_discount_share(target_customer_id INT, target_group_id INT)
RETURNS NUMERIC
AS
$$
DECLARE
    group_purchase NUMERIC := (
        SELECT group_purchase
        FROM view_periods
        WHERE customer_id = target_customer_id AND group_id = target_group_id
    );
BEGIN
    RETURN (
        SELECT coalesce(count(*), 0) / group_purchase
        FROM personal_data p
        JOIN cards c ON p.customer_id = c.customer_id AND p.customer_id = target_customer_id
        JOIN transactions t ON c.customer_card_id = t.customer_card_id
        JOIN checks c2 ON t.transaction_id = c2.transaction_id
        JOIN sku s ON s.sku_id = c2.sku_id AND s.group_id = target_group_id AND c2.sku_discount > 0
    );
END;
$$ LANGUAGE plpgsql;

--  group_minimum_discount return minimal discount for client by group
CREATE OR REPLACE FUNCTION group_minimum_discount(target_customer_id BIGINT, target_group_id BIGINT)
RETURNS NUMERIC
AS
$$
BEGIN
    RETURN (
        SELECT group_min_discount
        FROM view_periods
        WHERE customer_id = target_customer_id AND group_id = target_group_id
    );
END;
$$ LANGUAGE plpgsql;

--  group_average_discount - return average discount for client by group
CREATE OR REPLACE FUNCTION group_average_discount(target_customer_id BIGINT, target_group_id BIGINT)
RETURNS NUMERIC
AS
$$
BEGIN
    RETURN (
        SELECT sum(group_summ_paid) / sum(group_summ)
        FROM view_purchase_history
        WHERE customer_id = target_customer_id AND group_id = target_group_id
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_view_groups(
    method INT DEFAULT 1,  -- method for calculation margin (1) by period, (2) - by transactions count
    count INT DEFAULT 100) -- days from analysis date
RETURNS TABLE
        (
            customer_id  INT,
            group_id INT,
            group_affinity_index NUMERIC,
            group_churn_rate NUMERIC,
            group_stability_index NUMERIC,
            group_margin NUMERIC,
            group_discount_share NUMERIC,
            group_minimum_discount NUMERIC,
            group_average_discount NUMERIC
        )
AS
$$
BEGIN
    RETURN QUERY (
        SELECT p.customer_id,
               s.group_id,
               group_affinity_index(p.customer_id, s.group_id),
               group_churn_rate(p.customer_id, s.group_id),
               group_stability_index(p.customer_id, s.group_id),
               group_margin(p.customer_id, s.group_id, method := method, count := count),
               group_discount_share(p.customer_id, s.group_id),
               group_minimum_discount(p.customer_id, s.group_id),
               group_average_discount(p.customer_id, s.group_id)
        FROM personal_data p
        JOIN cards c on p.customer_id = c.customer_id
        JOIN transactions t on c.customer_card_id = t.customer_card_id
        JOIN checks c2 on t.transaction_id = c2.transaction_id
        JOIN sku s on s.sku_id = c2.sku_id
        GROUP BY p.customer_id, s.group_id
        ORDER BY p.customer_id, s.group_id
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW view_groups AS (
    SELECT *
    FROM create_view_groups()
);
