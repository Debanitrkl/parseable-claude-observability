# Experiment 03: Query Generation -- Evaluation

## Experiment Context

Claude was given the real schema from Parseable's `astronomy-shop-traces` log stream (extracted via the Parseable API) and asked to generate three queries: a P99 latency query (DataFusion SQL), a PromQL alert rule, and a parent trace correlation query (DataFusion SQL).

**Model:** Claude Opus 4.6 (`claude-opus-4-6`)
**Input tokens:** 18,679 | **Output tokens:** 1,656 | **Cost:** $0.40 | **Latency:** 31.0s
**Stop reason:** `end_turn` (completed naturally)

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

Claude used the **actual field names** from the real schema: `"service.name"` (quoted due to dot), `"http.method"`, `span_name`, `span_duration_ns`, and `p_timestamp`. It correctly converted nanoseconds to milliseconds by dividing by `1e6`.

### Scoring

| Dimension | Score | Notes |
|-----------|-------|-------|
| Syntax Validity | 1/1 | Uses `APPROX_PERCENTILE_CONT`, quoted field names, correct `INTERVAL` syntax |
| Semantic Correctness | 1/1 | Groups by service + method + span_name, filters with `HAVING COUNT(*) >= 5` |
| Idiomatic Usage | 1/1 | Proper DataFusion functions, `ROUND(..., 2)` for readability |

**Query 1 Score: 3/3**

## Query 2: PromQL Alert Rule -- Error Rate > 5%

### Generated Rule

Produced a complete Prometheus alerting rule YAML with `http_server_request_duration_seconds_count` as the metric, `http_status_code=~"5.."` regex for 5xx matching, `for: 2m` stabilization window, and `$value | humanizePercentage` in annotations.

### Scoring

| Dimension | Score | Notes |
|-----------|-------|-------|
| Syntax Validity | 1/1 | Valid PromQL and valid Prometheus alerting rule YAML |
| Semantic Correctness | 1/1 | Correct ratio calculation with `rate()` over 5m window |
| Idiomatic Usage | 1/1 | Uses `for: 2m` to avoid flapping, proper `sum()` wrappers for service-level aggregation |

**Query 2 Score: 3/3**

## Query 3: Parent Trace Correlation -- High-Latency Spans to Root Spans

### Generated Query

Used CTEs (`slow_spans` and `root_spans`) with time filtering on both sides of the join. Root spans identified via `span_parent_span_id = '' OR span_parent_span_id IS NULL`. Included a `pct_of_trace` calculated column showing what percentage of total trace time each slow span consumed.

Key design decisions noted by Claude:
- Used `> 1000000000` (1 second in nanoseconds) as the slow span threshold
- `NULLIF(r.root_duration_ns, 0)` guards against division by zero
- `INNER JOIN` (not LEFT JOIN) intentionally excludes orphan spans without root spans

### Scoring

| Dimension | Score | Notes |
|-----------|-------|-------|
| Syntax Validity | 1/1 | Valid CTE syntax, correct DataFusion functions |
| Semantic Correctness | 1/1 | Correctly joins slow spans to root spans via trace_id |
| Idiomatic Usage | 1/1 | Proper DataFusion CTEs, time filtering on both sides, `NULLIF` for safety |

**Query 3 Score: 3/3 (first attempt)**

## Summary

| Query | Score | Notes |
|-------|-------|-------|
| P99 Latency | 3/3 | Used real schema field names correctly |
| PromQL Alert | 3/3 | Production-ready alerting rule |
| Trace Correlation | 3/3 | Clean first attempt with CTEs |
| **Overall** | **9/9 (3/3 pass on first attempt)** | |

## Key Observations

1. **Real schema context was decisive.** The prompt included the actual Parseable schema with field names like `"service.name"` (with dot) and `span_duration_ns` (nanoseconds, not milliseconds). Claude used these exact field names and correctly handled the nanosecond-to-millisecond conversion. Without the real schema, the model would have guessed generic column names.

2. **No ClickHouse contamination.** Unlike prior experiments with synthetic schemas, all three queries used correct DataFusion syntax on the first attempt. `APPROX_PERCENTILE_CONT(span_duration_ns, 0.99)` was used correctly (not ClickHouse `quantile(0.99)(col)`).

3. **PromQL generation was clean.** The model has strong PromQL knowledge and produced a production-ready alerting rule with correct metric naming, regex matching, and stabilization windows.

4. **Design rationale was thorough.** Each query included detailed design decisions explaining why specific choices were made (e.g., `HAVING COUNT(*) >= 5`, `INNER JOIN` vs `LEFT JOIN`, CTE time filtering).

5. **Schema-aware field quoting.** Fields with dots in their names (e.g., `"service.name"`, `"http.method"`) were correctly double-quoted, which is required by DataFusion for identifiers containing special characters.
