-- Experiment 07: OTel Instrumentation - Parseable Trace Verification Queries
-- All queries use PostgreSQL-compatible SQL, executed by Parseable's DataFusion query engine.
-- Stream: astronomy-shop-traces (OpenTelemetry demo app)

-- 1. Verify traces are being received from the order-service
--    Check that OTLP/HTTP exporter is successfully sending to Parseable
SELECT
    p_timestamp,
    "service.name",
    span_name,
    span_trace_id,
    span_span_id,
    span_kind
FROM
    "astronomy-shop-traces"
WHERE
    "service.name" = 'order-service'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    p_timestamp DESC
LIMIT 20;

-- 2. Verify resource attributes are correctly set
--    Ensures service.name, service.version, and deployment.environment are present
SELECT DISTINCT
    "service.name",
    "service.version",
    "deployment.environment"
FROM
    "astronomy-shop-traces"
WHERE
    "service.name" = 'order-service'
    AND p_timestamp > NOW() - INTERVAL '1 hour';

-- 3. Verify context propagation - find complete trace trees
--    Parent-child span relationships confirm W3C TraceContext propagation
SELECT
    span_trace_id,
    span_span_id,
    span_parent_span_id,
    span_name,
    span_kind,
    scope_name
FROM
    "astronomy-shop-traces"
WHERE
    "service.name" = 'order-service'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    span_trace_id, p_timestamp ASC
LIMIT 50;

-- 4. Verify Flask auto-instrumentation spans
--    FlaskInstrumentor should create SERVER spans for each route
SELECT
    p_timestamp,
    span_name,
    "http.method",
    "http.route",
    "http.status_code",
    span_duration_ns
FROM
    "astronomy-shop-traces"
WHERE
    "service.name" = 'order-service'
    AND span_kind = 'SPAN_KIND_SERVER'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    p_timestamp DESC
LIMIT 20;

-- 5. Verify requests auto-instrumentation spans
--    RequestsInstrumentor should create CLIENT spans for outgoing HTTP calls
SELECT
    p_timestamp,
    span_name,
    "http.method",
    "http.url",
    "http.status_code",
    span_kind
FROM
    "astronomy-shop-traces"
WHERE
    "service.name" = 'order-service'
    AND span_kind = 'SPAN_KIND_CLIENT'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    p_timestamp DESC
LIMIT 20;

-- 6. Verify custom span attributes (order.id, order.amount)
--    The manually created "process-payment" span should have business attributes
SELECT
    p_timestamp,
    span_trace_id,
    span_name,
    "order.id",
    "order.amount",
    "payment.status_code"
FROM
    "astronomy-shop-traces"
WHERE
    "service.name" = 'order-service'
    AND span_name = 'process-payment'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    p_timestamp DESC
LIMIT 20;

-- 7. Trace latency analysis - end-to-end request duration
--    Measure how long the full POST /process request takes
SELECT
    span_name,
    COUNT(*) AS span_count,
    APPROX_PERCENTILE_CONT(span_duration_ns, 0.50) AS p50_duration_ns,
    APPROX_PERCENTILE_CONT(span_duration_ns, 0.95) AS p95_duration_ns,
    APPROX_PERCENTILE_CONT(span_duration_ns, 0.99) AS p99_duration_ns
FROM
    "astronomy-shop-traces"
WHERE
    "service.name" = 'order-service'
    AND span_kind = 'SPAN_KIND_SERVER'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
GROUP BY
    span_name
ORDER BY
    span_count DESC;

-- 8. Error rate from traces
--    Identify failed requests via HTTP status codes or error attributes
SELECT
    COUNT(*) AS total_spans,
    COUNT(*) FILTER (WHERE "http.status_code" >= 400) AS error_spans,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE "http.status_code" >= 400) AS FLOAT)
        / CAST(COUNT(*) AS FLOAT) * 100, 2
    ) AS error_rate_pct
FROM
    "astronomy-shop-traces"
WHERE
    "service.name" = 'order-service'
    AND span_kind = 'SPAN_KIND_SERVER'
    AND p_timestamp > NOW() - INTERVAL '1 hour';
