# Experiment 03: Query Generation

**Type:** Live Experiment
**Model:** Claude Opus 4.6
**Date:** 2025-01-15
**Score:** 2/3 first attempt, 3/3 after correction

## Objective

Evaluate Claude Opus 4.6's ability to generate syntactically valid and semantically correct DataFusion SQL and PromQL queries for observability data stored in Parseable.

## Requests

Three progressively complex query generation tasks were issued:

1. **P99 Latency Query** -- Generate a DataFusion SQL query to find the top 10 slowest API endpoints with average and p99 latency from a Parseable log stream. This tests knowledge of DataFusion's `APPROX_PERCENTILE_CONT` function rather than ClickHouse's `quantile()`.

2. **PromQL Alert Rule** -- Write a PromQL alerting rule that fires when the error rate exceeds 5% over a 5-minute window. This tests the model's understanding of PromQL syntax and rate/ratio calculations.

3. **Parent Trace Correlation** -- Write a DataFusion SQL query to correlate high-latency spans with their parent traces using self-joins on `trace_id` and `parent_span_id`. This tests the model's ability to reason about distributed tracing data models.

## Results

| Request | First Attempt | After Correction | Notes |
|---------|--------------|-----------------|-------|
| P99 Latency | Pass | Pass | Correctly used `APPROX_PERCENTILE_CONT` |
| PromQL Alert | Pass | Pass | Clean PromQL with proper `rate()` usage |
| Parent Trace Correlation | Fail | Pass | Initially used `quantile()` (ClickHouse syntax) in a subquery; corrected to DataFusion after feedback |

### First Attempt Score: 2/3

The model correctly generated the p99 latency query and PromQL alert on the first attempt. The trace correlation query contained a ClickHouse-ism (`quantile()`) in a threshold subquery that would fail in DataFusion's SQL engine. After pointing out the syntax mismatch, the model immediately corrected to `APPROX_PERCENTILE_CONT`.

### After Correction Score: 3/3

All three queries ran successfully against a Parseable instance with the `traces` log stream.

## How Keystone Delivers These Capabilities

Parseable's Keystone (available in Parseable Cloud and Enterprise editions) orchestrates LLMs (including Claude) to convert natural language to SQL queries in production. It adds value on top of the raw LLM capability tested here:

- **Schema awareness:** Keystone's SQL agent automatically resolves log stream schemas, eliminating the need to provide schema context in prompts.
- **Multi-agent orchestration:** Keystone coordinates Intent, SQL, and Visualization agents to deliver end-to-end answers in the Prism UI.
- **Same underlying reasoning:** The SQL generation quality tested in this experiment is the same reasoning that powers Keystone's Text-to-SQL feature.

A more meaningful comparison than "Keystone vs. raw API" is **specialized vs. general-purpose models** for observability. Purpose-built models like Datadog's Toto (a time-series foundation model trained on 750B observability data points) trade breadth for depth on narrow tasks like forecasting. General-purpose LLMs like Claude offer flexibility across SQL generation, log analysis, and trace reasoning.

## Token Usage

| Metric | Value |
|--------|-------|
| Input tokens | ~3,000 |
| Output tokens | ~1,500 |
| Estimated cost | ~$0.10 |

## Files

- `prompt.md` -- The three prompts sent to the model
- `parseable_queries.sql` -- Schema retrieval and validation queries
- `evaluation.md` -- Scoring rubric and detailed evaluation
- `sample_data.json` -- Schema definition and sample rows from the traces log stream
