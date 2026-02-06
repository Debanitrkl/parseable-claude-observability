-- Experiment 07: OTel Instrumentation - Parseable Trace Verification Queries
-- All queries use PostgreSQL-compatible SQL, executed by Parseable's DataFusion query engine.

-- 1. Verify traces are being received from the order-service
--    Check that OTLP/HTTP exporter is successfully sending to Parseable
SELECT
    p_timestamp,
    "resource.service.name" AS service_name,
    "name" AS span_name,
    "traceId" AS trace_id,
    "spanId" AS span_id,
    "kind" AS span_kind
FROM
    otel_traces
WHERE
    "resource.service.name" = 'order-service'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    p_timestamp DESC
LIMIT 20;

-- 2. Verify resource attributes are correctly set
--    Ensures service.name, service.version, and deployment.environment are present
SELECT DISTINCT
    "resource.service.name" AS service_name,
    "resource.service.version" AS service_version,
    "resource.deployment.environment" AS deployment_env
FROM
    otel_traces
WHERE
    "resource.service.name" = 'order-service'
    AND p_timestamp > NOW() - INTERVAL '1 hour';

-- 3. Verify context propagation - find complete trace trees
--    Parent-child span relationships confirm W3C TraceContext propagation
SELECT
    "traceId" AS trace_id,
    "spanId" AS span_id,
    "parentSpanId" AS parent_span_id,
    "name" AS span_name,
    "kind" AS span_kind,
    "scope.name" AS instrumentation_scope
FROM
    otel_traces
WHERE
    "resource.service.name" = 'order-service'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    "traceId", p_timestamp ASC
LIMIT 50;

-- 4. Verify Flask auto-instrumentation spans
--    FlaskInstrumentor should create SERVER spans for each route
SELECT
    p_timestamp,
    "name" AS span_name,
    "attributes.http.method" AS http_method,
    "attributes.http.route" AS http_route,
    "attributes.http.status_code" AS status_code,
    "duration" AS duration_ns
FROM
    otel_traces
WHERE
    "resource.service.name" = 'order-service'
    AND "kind" = 'SPAN_KIND_SERVER'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    p_timestamp DESC
LIMIT 20;

-- 5. Verify requests auto-instrumentation spans
--    RequestsInstrumentor should create CLIENT spans for outgoing HTTP calls
SELECT
    p_timestamp,
    "name" AS span_name,
    "attributes.http.method" AS http_method,
    "attributes.http.url" AS http_url,
    "attributes.http.status_code" AS status_code,
    "kind" AS span_kind
FROM
    otel_traces
WHERE
    "resource.service.name" = 'order-service'
    AND "kind" = 'SPAN_KIND_CLIENT'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    p_timestamp DESC
LIMIT 20;

-- 6. Verify custom span attributes (order.id, order.amount)
--    The manually created "process-payment" span should have business attributes
SELECT
    p_timestamp,
    "traceId" AS trace_id,
    "name" AS span_name,
    "attributes.order.id" AS order_id,
    "attributes.order.amount" AS order_amount,
    "attributes.payment.status_code" AS payment_status
FROM
    otel_traces
WHERE
    "resource.service.name" = 'order-service'
    AND "name" = 'process-payment'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
ORDER BY
    p_timestamp DESC
LIMIT 20;

-- 7. Trace latency analysis - end-to-end request duration
--    Measure how long the full POST /process request takes
SELECT
    "name" AS span_name,
    COUNT(*) AS span_count,
    APPROX_PERCENTILE_CONT("duration", 0.50) AS p50_duration_ns,
    APPROX_PERCENTILE_CONT("duration", 0.95) AS p95_duration_ns,
    APPROX_PERCENTILE_CONT("duration", 0.99) AS p99_duration_ns
FROM
    otel_traces
WHERE
    "resource.service.name" = 'order-service'
    AND "kind" = 'SPAN_KIND_SERVER'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
GROUP BY
    "name"
ORDER BY
    span_count DESC;

-- 8. Error rate from traces
--    Identify failed requests via HTTP status codes or error attributes
SELECT
    COUNT(*) AS total_spans,
    COUNT(*) FILTER (WHERE "attributes.http.status_code" >= 400) AS error_spans,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE "attributes.http.status_code" >= 400) AS FLOAT)
        / CAST(COUNT(*) AS FLOAT) * 100, 2
    ) AS error_rate_pct
FROM
    otel_traces
WHERE
    "resource.service.name" = 'order-service'
    AND "kind" = 'SPAN_KIND_SERVER'
    AND p_timestamp > NOW() - INTERVAL '1 hour';
