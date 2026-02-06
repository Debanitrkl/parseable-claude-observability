-- Experiment 04: Alert Correlation
-- Supporting SQL queries to pull context from Parseable during an alert storm
-- All queries use PostgreSQL-compatible SQL, executed by Parseable's DataFusion query engine.
-- Stream: astronomy-shop-traces (OpenTelemetry demo app)

-- =============================================================================
-- During an alert storm, these queries pull supporting data from Parseable
-- to help validate the LLM's correlation analysis
-- =============================================================================

-- 1. Error counts per service in the alert window
SELECT
    "service.name",
    COUNT(*) AS total_spans,
    COUNT(*) FILTER (WHERE severity_text = 'ERROR') AS error_count,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE severity_text = 'ERROR') AS DOUBLE)
        / CAST(COUNT(*) AS DOUBLE) * 100,
        2
    ) AS error_rate_pct
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
GROUP BY
    "service.name"
ORDER BY
    error_rate_pct DESC;


-- 2. Latency spikes per service (p50, p95, p99) during the alert window
SELECT
    "service.name",
    COUNT(*) AS span_count,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.50), 2) AS p50_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.95), 2) AS p95_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.99), 2) AS p99_ms,
    ROUND(MAX(span_duration_ns / 1000000.0), 2) AS max_ms
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
GROUP BY
    "service.name"
ORDER BY
    p99_ms DESC;


-- 3. Timeline of errors: when did each service start failing?
SELECT
    "service.name",
    MIN(p_timestamp) AS first_error_at,
    MAX(p_timestamp) AS last_error_at,
    COUNT(*) AS error_count
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND severity_text = 'ERROR'
GROUP BY
    "service.name"
ORDER BY
    first_error_at ASC;


-- 4. Payment service errors -- what operations are failing?
SELECT
    span_name,
    "http.status_code",
    severity_text,
    COUNT(*) AS occurrence_count,
    ROUND(AVG(span_duration_ns / 1000000.0), 2) AS avg_duration_ms,
    ROUND(MAX(span_duration_ns / 1000000.0), 2) AS max_duration_ms
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND "service.name" = 'payment-service'
    AND severity_text = 'ERROR'
GROUP BY
    span_name, "http.status_code", severity_text
ORDER BY
    occurrence_count DESC;


-- 5. Checkout service -- traces that include both checkout and payment spans
-- to confirm the dependency chain
SELECT
    t1.span_trace_id,
    t1."service.name" AS checkout_service,
    t1.span_name AS checkout_op,
    t1.span_duration_ns / 1000000.0 AS checkout_duration_ms,
    t1.severity_text AS checkout_status,
    t2."service.name" AS payment_service,
    t2.span_name AS payment_op,
    t2.span_duration_ns / 1000000.0 AS payment_duration_ms,
    t2.severity_text AS payment_status
FROM
    "astronomy-shop-traces" AS t1
INNER JOIN
    "astronomy-shop-traces" AS t2
    ON t1.span_trace_id = t2.span_trace_id
WHERE
    t1.p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND t2.p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND t1."service.name" = 'checkout-service'
    AND t2."service.name" = 'payment-service'
    AND (t1.severity_text = 'ERROR' OR t2.severity_text = 'ERROR')
ORDER BY
    t1.p_timestamp DESC
LIMIT 50;


-- 6. 30-second bucketed error timeline to visualize the cascade
SELECT
    DATE_TRUNC('minute', p_timestamp) AS time_bucket,
    "service.name",
    COUNT(*) AS total_spans,
    COUNT(*) FILTER (WHERE severity_text = 'ERROR') AS error_count
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
GROUP BY
    DATE_TRUNC('minute', p_timestamp), "service.name"
ORDER BY
    time_bucket ASC, "service.name";


-- 7. Downstream services -- are they failing because of checkout or independently?
SELECT
    "service.name",
    span_name,
    COUNT(*) FILTER (WHERE severity_text = 'ERROR') AS errors,
    COUNT(*) FILTER (WHERE span_duration_ns > 3000000000) AS slow_spans,
    ROUND(AVG(span_duration_ns / 1000000.0), 2) AS avg_duration_ms
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T14:28:00Z' AND '2025-01-15T14:36:00Z'
    AND "service.name" IN ('cart-service', 'shipping-service', 'email-service', 'recommendation-service')
GROUP BY
    "service.name", span_name
ORDER BY
    errors DESC;


-- 8. Pre-incident baseline (30 minutes before) for comparison
SELECT
    "service.name",
    COUNT(*) AS total_spans,
    COUNT(*) FILTER (WHERE severity_text = 'ERROR') AS error_count,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.99), 2) AS p99_ms
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp BETWEEN '2025-01-15T13:58:00Z' AND '2025-01-15T14:28:00Z'
GROUP BY
    "service.name"
ORDER BY
    "service.name";
