-- Experiment 06: Trace Analysis
-- SQL queries to extract a specific trace from Parseable's traces log stream
-- All SQL uses DataFusion syntax (Parseable's query engine)

-- =============================================================================
-- Extract a complete trace by trace_id
-- =============================================================================

-- 1. Get all spans for a specific trace
SELECT
    trace_id,
    span_id,
    parent_span_id,
    service_name,
    operation_name,
    p_timestamp,
    duration_ms,
    status_code,
    http_method,
    http_status
FROM
    traces
WHERE
    trace_id = 'trace_checkout_7f3a'
ORDER BY
    p_timestamp ASC;


-- 2. Get the root span (entry point) for the trace
SELECT
    span_id,
    service_name,
    operation_name,
    duration_ms,
    status_code,
    http_method,
    http_status
FROM
    traces
WHERE
    trace_id = 'trace_checkout_7f3a'
    AND (parent_span_id = '' OR parent_span_id IS NULL)
LIMIT 1;


-- 3. Get span count per service for the trace
SELECT
    service_name,
    COUNT(*) AS span_count,
    ROUND(SUM(duration_ms), 2) AS total_duration_ms,
    ROUND(MAX(duration_ms), 2) AS max_span_duration_ms
FROM
    traces
WHERE
    trace_id = 'trace_checkout_7f3a'
GROUP BY
    service_name
ORDER BY
    total_duration_ms DESC;


-- 4. Find the critical path candidates (longest spans at each level)
SELECT
    t1.span_id,
    t1.service_name,
    t1.operation_name,
    t1.duration_ms,
    t1.parent_span_id,
    t2.service_name AS parent_service,
    t2.operation_name AS parent_operation
FROM
    traces AS t1
LEFT JOIN
    traces AS t2
    ON t1.parent_span_id = t2.span_id
    AND t2.trace_id = 'trace_checkout_7f3a'
WHERE
    t1.trace_id = 'trace_checkout_7f3a'
ORDER BY
    t1.duration_ms DESC;


-- 5. Detect parallelism: find spans with the same parent that overlap in time
SELECT
    a.span_id AS span_a,
    a.service_name AS service_a,
    a.operation_name AS op_a,
    a.p_timestamp AS start_a,
    a.duration_ms AS duration_a,
    b.span_id AS span_b,
    b.service_name AS service_b,
    b.operation_name AS op_b,
    b.p_timestamp AS start_b,
    b.duration_ms AS duration_b
FROM
    traces AS a
INNER JOIN
    traces AS b
    ON a.parent_span_id = b.parent_span_id
    AND a.span_id < b.span_id
    AND a.trace_id = b.trace_id
WHERE
    a.trace_id = 'trace_checkout_7f3a'
    AND a.parent_span_id = 'span_0004'
ORDER BY
    a.p_timestamp ASC;


-- 6. Calculate self-time for each span
-- Self-time = span duration - sum of direct child durations
SELECT
    parent.span_id,
    parent.service_name,
    parent.operation_name,
    parent.duration_ms AS total_duration_ms,
    COALESCE(SUM(child.duration_ms), 0) AS child_duration_ms,
    ROUND(parent.duration_ms - COALESCE(SUM(child.duration_ms), 0), 2) AS self_time_ms
FROM
    traces AS parent
LEFT JOIN
    traces AS child
    ON parent.span_id = child.parent_span_id
    AND child.trace_id = 'trace_checkout_7f3a'
WHERE
    parent.trace_id = 'trace_checkout_7f3a'
GROUP BY
    parent.span_id,
    parent.service_name,
    parent.operation_name,
    parent.duration_ms
ORDER BY
    self_time_ms DESC;


-- 7. Find error spans in the trace (if any)
SELECT
    span_id,
    service_name,
    operation_name,
    duration_ms,
    status_code,
    http_status
FROM
    traces
WHERE
    trace_id = 'trace_checkout_7f3a'
    AND (status_code = 'ERROR' OR http_status >= 400)
ORDER BY
    p_timestamp ASC;


-- 8. Compare this trace's duration to the service baseline
SELECT
    service_name,
    operation_name,
    COUNT(*) AS sample_count,
    ROUND(AVG(duration_ms), 2) AS avg_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.50), 2) AS p50_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.99), 2) AS p99_ms
FROM
    traces
WHERE
    p_timestamp > NOW() - INTERVAL '1 hour'
    AND service_name IN ('frontend', 'checkout-service', 'payment-service', 'shipping-service')
    AND operation_name IN ('POST /api/checkout', 'ProcessCheckout', 'ProcessPayment', 'CalculateShipping')
GROUP BY
    service_name, operation_name
ORDER BY
    service_name;
