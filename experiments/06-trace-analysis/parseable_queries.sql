-- Experiment 06: Trace Analysis
-- SQL queries to extract a specific trace from Parseable's traces log stream
-- All queries use PostgreSQL-compatible SQL, executed by Parseable's DataFusion query engine.
-- Stream: astronomy-shop-traces (OpenTelemetry demo app)

-- =============================================================================
-- Extract a complete trace by trace_id
-- =============================================================================

-- 1. Get all spans for a specific trace
SELECT
    span_trace_id,
    span_span_id,
    span_parent_span_id,
    "service.name",
    span_name,
    p_timestamp,
    span_duration_ns,
    severity_text,
    "http.method",
    "http.status_code"
FROM
    "astronomy-shop-traces"
WHERE
    span_trace_id = 'trace_checkout_7f3a'
ORDER BY
    p_timestamp ASC;


-- 2. Get the root span (entry point) for the trace
SELECT
    span_span_id,
    "service.name",
    span_name,
    span_duration_ns,
    severity_text,
    "http.method",
    "http.status_code"
FROM
    "astronomy-shop-traces"
WHERE
    span_trace_id = 'trace_checkout_7f3a'
    AND (span_parent_span_id = '' OR span_parent_span_id IS NULL)
LIMIT 1;


-- 3. Get span count per service for the trace
SELECT
    "service.name",
    COUNT(*) AS span_count,
    ROUND(SUM(span_duration_ns / 1000000.0), 2) AS total_duration_ms,
    ROUND(MAX(span_duration_ns / 1000000.0), 2) AS max_span_duration_ms
FROM
    "astronomy-shop-traces"
WHERE
    span_trace_id = 'trace_checkout_7f3a'
GROUP BY
    "service.name"
ORDER BY
    total_duration_ms DESC;


-- 4. Find the critical path candidates (longest spans at each level)
SELECT
    t1.span_span_id,
    t1."service.name",
    t1.span_name,
    t1.span_duration_ns,
    t1.span_parent_span_id,
    t2."service.name" AS parent_service,
    t2.span_name AS parent_operation
FROM
    "astronomy-shop-traces" AS t1
LEFT JOIN
    "astronomy-shop-traces" AS t2
    ON t1.span_parent_span_id = t2.span_span_id
    AND t2.span_trace_id = 'trace_checkout_7f3a'
WHERE
    t1.span_trace_id = 'trace_checkout_7f3a'
ORDER BY
    t1.span_duration_ns DESC;


-- 5. Detect parallelism: find spans with the same parent that overlap in time
SELECT
    a.span_span_id AS span_a,
    a."service.name" AS service_a,
    a.span_name AS op_a,
    a.p_timestamp AS start_a,
    a.span_duration_ns AS duration_a,
    b.span_span_id AS span_b,
    b."service.name" AS service_b,
    b.span_name AS op_b,
    b.p_timestamp AS start_b,
    b.span_duration_ns AS duration_b
FROM
    "astronomy-shop-traces" AS a
INNER JOIN
    "astronomy-shop-traces" AS b
    ON a.span_parent_span_id = b.span_parent_span_id
    AND a.span_span_id < b.span_span_id
    AND a.span_trace_id = b.span_trace_id
WHERE
    a.span_trace_id = 'trace_checkout_7f3a'
    AND a.span_parent_span_id = 'span_0004'
ORDER BY
    a.p_timestamp ASC;


-- 6. Calculate self-time for each span
-- Self-time = span duration - sum of direct child durations
SELECT
    parent.span_span_id,
    parent."service.name",
    parent.span_name,
    parent.span_duration_ns AS total_duration_ns,
    COALESCE(SUM(child.span_duration_ns), 0) AS child_duration_ns,
    ROUND((parent.span_duration_ns - COALESCE(SUM(child.span_duration_ns), 0)) / 1000000.0, 2) AS self_time_ms
FROM
    "astronomy-shop-traces" AS parent
LEFT JOIN
    "astronomy-shop-traces" AS child
    ON parent.span_span_id = child.span_parent_span_id
    AND child.span_trace_id = 'trace_checkout_7f3a'
WHERE
    parent.span_trace_id = 'trace_checkout_7f3a'
GROUP BY
    parent.span_span_id,
    parent."service.name",
    parent.span_name,
    parent.span_duration_ns
ORDER BY
    self_time_ms DESC;


-- 7. Find error spans in the trace (if any)
SELECT
    span_span_id,
    "service.name",
    span_name,
    span_duration_ns,
    severity_text,
    "http.status_code"
FROM
    "astronomy-shop-traces"
WHERE
    span_trace_id = 'trace_checkout_7f3a'
    AND (severity_text = 'ERROR' OR "http.status_code" >= 400)
ORDER BY
    p_timestamp ASC;


-- 8. Compare this trace's duration to the service baseline
SELECT
    "service.name",
    span_name,
    COUNT(*) AS sample_count,
    ROUND(AVG(span_duration_ns / 1000000.0), 2) AS avg_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.50), 2) AS p50_ms,
    ROUND(APPROX_PERCENTILE_CONT(span_duration_ns / 1000000.0, 0.99), 2) AS p99_ms
FROM
    "astronomy-shop-traces"
WHERE
    p_timestamp > NOW() - INTERVAL '1 hour'
    AND "service.name" IN ('frontend', 'checkout-service', 'payment-service', 'shipping-service')
    AND span_name IN ('POST /api/checkout', 'ProcessCheckout', 'ProcessPayment', 'CalculateShipping')
GROUP BY
    "service.name", span_name
ORDER BY
    "service.name";
