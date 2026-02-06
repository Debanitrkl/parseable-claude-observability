-- Experiment 05: Incident RCA
-- SQL queries to extract incident data from Parseable log streams
-- All queries use PostgreSQL-compatible SQL, executed by Parseable's DataFusion query engine.
-- Streams: astronomy-shop-logs, astronomy-shop-traces, astronomy-shop-metrics

-- =============================================================================
-- Extract error logs from the payment service during the incident
-- =============================================================================

-- 1. Payment service error logs with gRPC deadline information
SELECT
    p_timestamp,
    "service.name",
    severity_text,
    body,
    span_trace_id,
    timeout_ms,
    actual_ms,
    cpu_throttle_count
FROM
    "astronomy-shop-logs"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND "service.name" = 'payment-service'
    AND severity_text IN ('ERROR', 'WARN')
ORDER BY
    p_timestamp ASC;


-- 2. Error count and rate per service over the incident window
SELECT
    "service.name",
    severity_text,
    COUNT(*) AS log_count,
    MIN(p_timestamp) AS first_occurrence,
    MAX(p_timestamp) AS last_occurrence
FROM
    "astronomy-shop-logs"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND severity_text IN ('ERROR', 'WARN')
GROUP BY
    "service.name", severity_text
ORDER BY
    first_occurrence ASC;


-- 3. CPU throttle count progression (from WARN logs)
SELECT
    p_timestamp,
    cpu_throttle_count
FROM
    "astronomy-shop-logs"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND "service.name" = 'payment-service'
    AND body LIKE '%CPU pressure%'
ORDER BY
    p_timestamp ASC;


-- =============================================================================
-- Extract slow traces involving the payment service
-- =============================================================================

-- 4. All payment service spans during the incident
SELECT
    span_trace_id,
    span_span_id,
    span_parent_span_id,
    "service.name",
    span_name,
    span_duration_ns,
    severity_text,
    "http.status_code"
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND "service.name" = 'payment-service'
    AND span_duration_ns > 2000000000
ORDER BY
    span_duration_ns DESC
LIMIT 100;


-- 5. Full trace reconstruction for the slowest traces
SELECT
    t.span_trace_id,
    t.span_span_id,
    t.span_parent_span_id,
    t."service.name",
    t.span_name,
    t.span_duration_ns,
    t.severity_text,
    t."http.status_code"
FROM
    "astronomy-shop-traces" AS t
WHERE
    t.span_trace_id IN (
        SELECT DISTINCT span_trace_id
        FROM "astronomy-shop-traces"
        WHERE p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
            AND "service.name" = 'payment-service'
            AND span_duration_ns > 4000000000
        LIMIT 10
    )
ORDER BY
    t.span_trace_id, t.p_timestamp ASC;


-- 6. Latency distribution comparison: incident vs baseline
-- During incident
SELECT
    'incident' AS period,
    "service.name",
    COUNT(*) AS span_count,
    ROUND(AVG(span_duration_ns / 1000000.0), 2) AS avg_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.50), 2) AS p50_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.95), 2) AS p95_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.99), 2) AS p99_ms
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:25:00Z' AND '2025-01-15T14:35:00Z'
    AND "service.name" = 'payment-service'
GROUP BY
    "service.name";

-- Baseline (previous hour)
SELECT
    'baseline' AS period,
    "service.name",
    COUNT(*) AS span_count,
    ROUND(AVG(span_duration_ns / 1000000.0), 2) AS avg_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.50), 2) AS p50_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.95), 2) AS p95_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.99), 2) AS p99_ms
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T13:25:00Z' AND '2025-01-15T14:25:00Z'
    AND "service.name" = 'payment-service'
GROUP BY
    "service.name";


-- =============================================================================
-- Supporting metrics queries
-- =============================================================================

-- 7. Kubernetes resource metrics during the incident
SELECT
    p_timestamp,
    "service.name",
    cpu_usage_millicores,
    cpu_limit_millicores,
    memory_usage_mi,
    memory_limit_mi,
    cfs_throttled_periods,
    cfs_throttled_seconds
FROM
    "astronomy-shop-metrics"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND "service.name" = 'payment-service'
ORDER BY
    p_timestamp ASC;


-- 8. Checkout service success rate over time
SELECT
    DATE_TRUNC('minute', p_timestamp) AS time_bucket,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE severity_text = 'OK') AS successful,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE severity_text = 'OK') AS DOUBLE)
        / CAST(COUNT(*) AS DOUBLE) * 100,
        2
    ) AS success_rate_pct
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:20:00Z' AND '2025-01-15T14:55:00Z'
    AND "service.name" = 'checkout-service'
    AND span_name = 'ProcessCheckout'
GROUP BY
    DATE_TRUNC('minute', p_timestamp)
ORDER BY
    time_bucket ASC;


-- 9. Retry pattern detection
SELECT
    span_trace_id,
    COUNT(*) AS payment_span_count,
    COUNT(*) FILTER (WHERE severity_text = 'ERROR') AS error_count,
    ROUND(SUM(span_duration_ns / 1000000.0), 2) AS total_payment_time_ms
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:25:00Z' AND '2025-01-15T14:35:00Z'
    AND "service.name" = 'payment-service'
    AND span_name = 'ProcessPayment'
GROUP BY
    span_trace_id
HAVING
    COUNT(*) > 1
ORDER BY
    payment_span_count DESC
LIMIT 20;
