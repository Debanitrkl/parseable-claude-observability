# Experiment 03: Query Generation Prompts

## Prompt 1: P99 Latency Query

```
Given this Parseable log stream schema for the "astronomy-shop-traces" stream, write a DataFusion SQL
query to find the top 10 slowest API endpoints with average and p99 latency.

Schema (key fields):
- p_timestamp (TIMESTAMP) -- ingestion timestamp assigned by Parseable
- span_trace_id (VARCHAR) -- distributed trace identifier
- span_span_id (VARCHAR) -- unique span identifier
- span_parent_span_id (VARCHAR) -- parent span identifier (empty for root spans)
- "service.name" (VARCHAR) -- originating microservice name (quoted due to dot)
- span_name (VARCHAR) -- the operation or endpoint name
- span_duration_ns (BIGINT) -- span duration in nanoseconds
- span_status_code (VARCHAR) -- span status: OK, ERROR, UNSET
- "http.method" (VARCHAR) -- HTTP method: GET, POST, PUT, DELETE
- "http.status_code" (VARCHAR) -- HTTP response status code
- "http.url" (VARCHAR) -- request URL path

Important: Use PostgreSQL-compatible SQL supported by Parseable's DataFusion engine. Use APPROX_PERCENTILE_CONT (not quantile()),
COUNT(*) (not count()), and INTERVAL '1 hour' (not INTERVAL 1 HOUR).
Field names containing dots must be quoted with double quotes (e.g., "service.name").
```

## Prompt 2: PromQL Alert Rule

```
Write a PromQL alert rule that fires when the error rate exceeds 5% over a 5-minute
window. The metric names follow OpenTelemetry conventions:

- http_server_request_duration_seconds_count -- total request count
- http_server_request_duration_seconds_bucket -- histogram buckets

HTTP status codes are available via the "http_status_code" label. Errors are any
status code >= 500.

The alert should:
- Use a 5-minute rate window
- Fire when error ratio > 0.05 (5%)
- Include severity and summary annotations
- Target the "checkout-service" job
```

## Prompt 3: Parent Trace Correlation

```
Write a DataFusion SQL query to correlate high-latency spans with their parent traces.
The query should:

1. Find spans in the last 1 hour where span_duration_ns > 1000000000 (high latency, > 1s)
2. Join back to the same table to find the root span of each trace
   (root span has span_parent_span_id = '' or span_parent_span_id IS NULL)
3. Return: span_trace_id, root "service.name", root span_name, root span_duration_ns,
   slow span "service.name", slow span span_name, slow span span_duration_ns
4. Order by slow span duration descending
5. Limit to 20 results

Use the "astronomy-shop-traces" log stream in Parseable. Use PostgreSQL-compatible SQL:
- APPROX_PERCENTILE_CONT for percentiles
- INTERVAL '1 hour' for time intervals
- p_timestamp for the Parseable ingestion timestamp
- Field names with dots must be quoted: "service.name", "http.method", etc.
```
