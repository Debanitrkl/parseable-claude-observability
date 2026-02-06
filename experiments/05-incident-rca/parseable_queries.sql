-- Experiment 05: Incident RCA
-- SQL queries to extract incident data from Parseable log streams
-- All queries use PostgreSQL-compatible SQL, executed by Parseable's DataFusion query engine.

-- =============================================================================
-- Extract error logs from the payment service during the incident
-- =============================================================================

-- 1. Payment service error logs with gRPC deadline information
SELECT
    p_timestamp,
    service_name,
    level,
    message,
    trace_id,
    timeout_ms,
    actual_ms,
    cpu_throttle_count
FROM
    "application-logs"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND service_name = 'payment-service'
    AND level IN ('ERROR', 'WARN')
ORDER BY
    p_timestamp ASC;


-- 2. Error count and rate per service over the incident window
SELECT
    service_name,
    level,
    COUNT(*) AS log_count,
    MIN(p_timestamp) AS first_occurrence,
    MAX(p_timestamp) AS last_occurrence
FROM
    "application-logs"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND level IN ('ERROR', 'WARN')
GROUP BY
    service_name, level
ORDER BY
    first_occurrence ASC;


-- 3. CPU throttle count progression (from WARN logs)
SELECT
    p_timestamp,
    cpu_throttle_count
FROM
    "application-logs"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND service_name = 'payment-service'
    AND message LIKE '%CPU pressure%'
ORDER BY
    p_timestamp ASC;


-- =============================================================================
-- Extract slow traces involving the payment service
-- =============================================================================

-- 4. All payment service spans during the incident
SELECT
    trace_id,
    span_id,
    parent_span_id,
    service_name,
    operation_name,
    duration_ms,
    status_code,
    http_status
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND service_name = 'payment-service'
    AND duration_ms > 2000
ORDER BY
    duration_ms DESC
LIMIT 100;


-- 5. Full trace reconstruction for the slowest traces
SELECT
    t.trace_id,
    t.span_id,
    t.parent_span_id,
    t.service_name,
    t.operation_name,
    t.duration_ms,
    t.status_code,
    t.http_status
FROM
    traces AS t
WHERE
    t.trace_id IN (
        SELECT DISTINCT trace_id
        FROM traces
        WHERE p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
            AND service_name = 'payment-service'
            AND duration_ms > 4000
        LIMIT 10
    )
ORDER BY
    t.trace_id, t.p_timestamp ASC;


-- 6. Latency distribution comparison: incident vs baseline
-- During incident
SELECT
    'incident' AS period,
    service_name,
    COUNT(*) AS span_count,
    ROUND(AVG(duration_ms), 2) AS avg_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.50), 2) AS p50_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.95), 2) AS p95_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.99), 2) AS p99_ms
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:25:00Z' AND '2025-01-15T14:35:00Z'
    AND service_name = 'payment-service'
GROUP BY
    service_name;

-- Baseline (previous hour)
SELECT
    'baseline' AS period,
    service_name,
    COUNT(*) AS span_count,
    ROUND(AVG(duration_ms), 2) AS avg_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.50), 2) AS p50_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.95), 2) AS p95_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.99), 2) AS p99_ms
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T13:25:00Z' AND '2025-01-15T14:25:00Z'
    AND service_name = 'payment-service'
GROUP BY
    service_name;


-- =============================================================================
-- Supporting metrics queries
-- =============================================================================

-- 7. Kubernetes resource metrics during the incident
SELECT
    p_timestamp,
    service_name,
    cpu_usage_millicores,
    cpu_limit_millicores,
    memory_usage_mi,
    memory_limit_mi,
    cfs_throttled_periods,
    cfs_throttled_seconds
FROM
    "k8s-metrics"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND service_name = 'payment-service'
ORDER BY
    p_timestamp ASC;


-- 8. Checkout service success rate over time
SELECT
    DATE_TRUNC('minute', p_timestamp) AS time_bucket,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE status_code = 'OK') AS successful,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE status_code = 'OK') AS DOUBLE)
        / CAST(COUNT(*) AS DOUBLE) * 100,
        2
    ) AS success_rate_pct
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND service_name = 'checkout-service'
    AND operation_name = 'ProcessCheckout'
GROUP BY
    DATE_TRUNC('minute', p_timestamp)
ORDER BY
    time_bucket ASC;


-- 9. Retry pattern detection
SELECT
    trace_id,
    COUNT(*) AS payment_span_count,
    COUNT(*) FILTER (WHERE status_code = 'ERROR') AS error_count,
    ROUND(SUM(duration_ms), 2) AS total_payment_time_ms
FROM
    traces
WHERE
    p_timestamp BETWEEN '2025-01-15T14:25:00Z' AND '2025-01-15T14:35:00Z'
    AND service_name = 'payment-service'
    AND operation_name = 'ProcessPayment'
GROUP BY
    trace_id
HAVING
    COUNT(*) > 1
ORDER BY
    payment_span_count DESC
LIMIT 20;
