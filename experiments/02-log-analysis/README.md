# Experiment 02: Log Analysis -- Pattern Recognition and Anomaly Detection

## Type: Live Experiment

## Objective

Test Claude Opus 4.6's ability to analyze 200 JSON-structured log lines, detect anomalous patterns, identify root causes, and produce structured output -- all using data exported from Parseable log streams.

## Injected Anomalies (Ground Truth)

1. **Payment timeout burst**: 12 `connection_timeout` errors from the payment service between `14:32:01` and `14:32:18`
2. **Cart slow query escalation**: Gradual increase in `slow_query` warnings from cart service, escalating from 1/min to 8/min over 10 minutes
3. **OOM on recommendation service**: Single `out_of_memory` error at `14:35:42`, preceded by steadily growing heap usage at debug level

## Files

- `prompt.md` -- The exact prompt sent to Claude
- `sample_data.json` -- 200 JSON log lines with injected anomalies
- `parseable_queries.sql` -- SQL queries to extract similar data from your Parseable instance
- `evaluation.md` -- Scoring rubric and results

## How to Reproduce

1. Load `sample_data.json` into a Parseable log stream, or use the SQL queries in `parseable_queries.sql` to extract real data from your running OTel Demo
2. Copy the prompt from `prompt.md`
3. Send the prompt + log data to Claude Opus 4.6
4. Compare the response against the evaluation criteria in `evaluation.md`

### Using Parseable's SQL Editor

```sql
SELECT * FROM "checkout"
WHERE level = 'error'
ORDER BY p_timestamp DESC
LIMIT 200
```

### Using Keystone (comparison)

In Parseable's Prism UI, open Keystone and ask:
> "What anomalies are in the checkout logs from the last hour?"

Compare Keystone's response to Claude's analysis.

## Expected Results

| Anomaly | Detected | Severity | Root Cause |
|---------|----------|----------|------------|
| Payment timeout burst | Yes | Critical | Connection pool / downstream timeout |
| Cart slow query escalation | Yes | Warning | Increased load (partial -- missing index not identified without schema) |
| OOM on recommendation svc | Yes | Critical | Memory leak (connected debug heap logs to OOM) |
| False positive (normal 404s) | No | -- | -- |

**Score: 3/3 anomalies detected, 0 false positives, 2/3 root causes correctly identified.**

## Token Usage

- Input: ~45,000 tokens
- Output: ~2,000 tokens
- Estimated cost: ~$0.75
