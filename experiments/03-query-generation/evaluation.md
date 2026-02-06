# Experiment 03: Query Generation -- Evaluation

## Scoring Rubric

Each query is scored on three dimensions (1 point each, max 3 per query):

| Dimension | Description |
|-----------|-------------|
| **Syntax Validity** | Query runs without errors in Parseable's SQL editor (DataFusion engine) |
| **Semantic Correctness** | Query returns logically correct results for the stated objective |
| **Idiomatic Usage** | Query uses DataFusion idioms and best practices, not ClickHouse or PostgreSQL-isms |

## DataFusion vs ClickHouse Syntax

A key challenge for LLMs is distinguishing DataFusion SQL from ClickHouse SQL. Many training examples use ClickHouse syntax, which will fail in Parseable:

| Operation | DataFusion (Correct) | ClickHouse (Will Fail) |
|-----------|---------------------|----------------------|
| 99th percentile | `APPROX_PERCENTILE_CONT(col, 0.99)` | `quantile(0.99)(col)` |
| Count rows | `COUNT(*)` | `count()` |
| Time interval | `INTERVAL '1 hour'` | `INTERVAL 1 HOUR` |
| Current time | `NOW()` | `now()` |
| String concat | `CONCAT(a, b)` or `a \|\| b` | `concat(a, b)` |
| Array access | Not applicable | `arrayElement()` |

## Query 1: P99 Latency -- Top 10 Slowest Endpoints

### Generated Query
```sql
SELECT
    service_name,
    operation_name,
    http_method,
    COUNT(*) AS request_count,
    ROUND(AVG(duration_ms), 2) AS avg_latency_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.99), 2) AS p99_latency_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.95), 2) AS p95_latency_ms,
    ROUND(MAX(duration_ms), 2) AS max_latency_ms
FROM traces
WHERE p_timestamp > NOW() - INTERVAL '1 hour'
    AND http_method IS NOT NULL
GROUP BY service_name, operation_name, http_method
HAVING COUNT(*) >= 10
ORDER BY p99_latency_ms DESC
LIMIT 10;
```

### Scoring

| Dimension | Score | Notes |
|-----------|-------|-------|
| Syntax Validity | 1/1 | Runs clean in Parseable SQL editor |
| Semantic Correctness | 1/1 | Correctly computes avg and p99 per endpoint, filters low-cardinality groups |
| Idiomatic Usage | 1/1 | Uses `APPROX_PERCENTILE_CONT`, `COUNT(*)`, `INTERVAL '1 hour'` correctly |

**Query 1 Score: 3/3**

## Query 2: PromQL Alert Rule -- Error Rate > 5%

### Generated Rule
```yaml
groups:
  - name: checkout-service-alerts
    rules:
      - alert: HighErrorRate
        expr: |
          (
            sum(rate(http_server_request_duration_seconds_count{
              job="checkout-service",
              http_status_code=~"5.."
            }[5m]))
          /
            sum(rate(http_server_request_duration_seconds_count{
              job="checkout-service"
            }[5m]))
          ) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Checkout service error rate above 5%"
          description: "Error rate is {{ $value | humanizePercentage }} over the last 5 minutes"
```

### Scoring

| Dimension | Score | Notes |
|-----------|-------|-------|
| Syntax Validity | 1/1 | Valid PromQL and valid Prometheus alerting rule YAML |
| Semantic Correctness | 1/1 | Correct ratio calculation with `rate()` over 5m window, `5..` regex for 5xx |
| Idiomatic Usage | 1/1 | Uses `for: 2m` to avoid flapping, proper annotations with template functions |

**Query 2 Score: 3/3**

## Query 3: Parent Trace Correlation -- First Attempt

### First Attempt (Failed)
```sql
SELECT
    slow.trace_id,
    root.service_name AS root_service,
    root.operation_name AS root_operation,
    root.duration_ms AS root_duration_ms,
    slow.service_name AS slow_span_service,
    slow.operation_name AS slow_span_operation,
    slow.duration_ms AS slow_span_duration_ms
FROM traces AS slow
INNER JOIN traces AS root
    ON slow.trace_id = root.trace_id
    AND (root.parent_span_id = '' OR root.parent_span_id IS NULL)
WHERE slow.p_timestamp > NOW() - INTERVAL '1 hour'
    AND slow.duration_ms > (
        SELECT quantile(0.99)(duration_ms) FROM traces
        WHERE p_timestamp > NOW() - INTERVAL '1 hour'
    )
ORDER BY slow.duration_ms DESC
LIMIT 20;
```

**Failure:** Used `quantile(0.99)(duration_ms)` in the subquery -- ClickHouse syntax. DataFusion does not support the `quantile()()` double-parenthesis function call syntax.

### After Correction (Passed)
The threshold subquery was corrected to use a fixed threshold (`duration_ms > 1000`) as specified in the prompt, and the query was simplified to avoid the unnecessary percentile subquery.

### Scoring (After Correction)

| Dimension | Score | Notes |
|-----------|-------|-------|
| Syntax Validity | 1/1 | Runs clean after correction |
| Semantic Correctness | 1/1 | Correctly joins slow spans to root spans via trace_id |
| Idiomatic Usage | 1/1 | Proper DataFusion self-join, time filtering on both sides |

**Query 3 Score: 3/3 (after correction)**
**Query 3 First Attempt Score: 1/3 (syntax failure)**

## Summary

| Query | First Attempt | After Correction |
|-------|--------------|-----------------|
| P99 Latency | 3/3 | 3/3 |
| PromQL Alert | 3/3 | 3/3 |
| Trace Correlation | 1/3 | 3/3 |
| **Overall** | **7/9 (2/3 pass)** | **9/9 (3/3 pass)** |

## Key Observations

1. **ClickHouse contamination is real.** The model's training data includes significant ClickHouse SQL examples, and it will occasionally produce ClickHouse syntax when generating analytical queries. Explicit prompting about the SQL dialect helps but does not fully prevent this.

2. **Self-correction is fast.** When told the syntax was wrong and why, the model immediately produced correct PostgreSQL-compatible SQL without further prompting.

3. **PromQL generation was clean.** The model has strong PromQL knowledge and produced a production-ready alerting rule on the first attempt.

4. **Schema context is essential.** Providing the explicit schema in the prompt was necessary. Without it, the model would have guessed column names and likely used generic observability column names that do not match Parseable's schema (e.g., `timestamp` instead of `p_timestamp`).
