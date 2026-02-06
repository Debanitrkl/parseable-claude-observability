-- Experiment 04: Alert Correlation
-- Supporting SQL queries to pull context from Parseable during an alert storm
-- All SQL uses DataFusion syntax (Parseable's query engine)

-- =============================================================================
-- During an alert storm, these queries pull supporting data from Parseable
-- to help validate the LLM's correlation analysis
-- =============================================================================

-- 1. Error counts per service in the alert window
SELECT
    service_name,
    COUNT(*) AS total_spans,
    COUNT(*) FILTER (WHERE status_code = 'ERROR') AS error_count,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE status_code = 'ERROR') AS DOUBLE)
        / CAST(COUNT(*) AS DOUBLE) * 100,
        2
    ) AS error_rate_pct
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
GROUP BY
    service_name
ORDER BY
    error_rate_pct DESC;


-- 2. Latency spikes per service (p50, p95, p99) during the alert window
SELECT
    service_name,
    COUNT(*) AS span_count,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.50), 2) AS p50_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.95), 2) AS p95_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.99), 2) AS p99_ms,
    ROUND(MAX(duration_ms), 2) AS max_ms
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
GROUP BY
    service_name
ORDER BY
    p99_ms DESC;


-- 3. Timeline of errors: when did each service start failing?
SELECT
    service_name,
    MIN(p_timestamp) AS first_error_at,
    MAX(p_timestamp) AS last_error_at,
    COUNT(*) AS error_count
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND status_code = 'ERROR'
GROUP BY
    service_name
ORDER BY
    first_error_at ASC;


-- 4. Payment service errors -- what operations are failing?
SELECT
    operation_name,
    http_status,
    status_code,
    COUNT(*) AS occurrence_count,
    ROUND(AVG(duration_ms), 2) AS avg_duration_ms,
    ROUND(MAX(duration_ms), 2) AS max_duration_ms
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND service_name = 'payment-service'
    AND status_code = 'ERROR'
GROUP BY
    operation_name, http_status, status_code
ORDER BY
    occurrence_count DESC;


-- 5. Checkout service -- traces that include both checkout and payment spans
-- to confirm the dependency chain
SELECT
    t1.trace_id,
    t1.service_name AS checkout_service,
    t1.operation_name AS checkout_op,
    t1.duration_ms AS checkout_duration_ms,
    t1.status_code AS checkout_status,
    t2.service_name AS payment_service,
    t2.operation_name AS payment_op,
    t2.duration_ms AS payment_duration_ms,
    t2.status_code AS payment_status
FROM
    traces AS t1
INNER JOIN
    traces AS t2
    ON t1.trace_id = t2.trace_id
WHERE
    t1.p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND t2.p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND t1.service_name = 'checkout-service'
    AND t2.service_name = 'payment-service'
    AND (t1.status_code = 'ERROR' OR t2.status_code = 'ERROR')
ORDER BY
    t1.p_timestamp DESC
LIMIT 50;


-- 6. 30-second bucketed error timeline to visualize the cascade
SELECT
    DATE_TRUNC('minute', p_timestamp) AS time_bucket,
    service_name,
    COUNT(*) AS total_spans,
    COUNT(*) FILTER (WHERE status_code = 'ERROR') AS error_count
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
GROUP BY
    DATE_TRUNC('minute', p_timestamp), service_name
ORDER BY
    time_bucket ASC, service_name;


-- 7. Downstream services -- are they failing because of checkout or independently?
SELECT
    service_name,
    operation_name,
    COUNT(*) FILTER (WHERE status_code = 'ERROR') AS errors,
    COUNT(*) FILTER (WHERE duration_ms > 3000) AS slow_spans,
    ROUND(AVG(duration_ms), 2) AS avg_duration_ms
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND service_name IN ('cart-service', 'shipping-service', 'email-service', 'recommendation-service')
GROUP BY
    service_name, operation_name
ORDER BY
    errors DESC;


-- 8. Pre-incident baseline (30 minutes before) for comparison
SELECT
    service_name,
    COUNT(*) AS total_spans,
    COUNT(*) FILTER (WHERE status_code = 'ERROR') AS error_count,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.99), 2) AS p99_ms
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T13:58:00Z' AND '2025-01-15T14:28:00Z'
GROUP BY
    service_name
ORDER BY
    service_name;
