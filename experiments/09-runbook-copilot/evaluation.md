# Evaluation: Experiment 09 - Runbook + On-Call Copilot

## Summary

Claude Opus 4.6 was evaluated as a multi-turn on-call copilot during a simulated P1 incident (CheckoutDBPoolExhausted). The model generated diagnostic runbooks combining Parseable SQL queries with infrastructure commands, analyzed results reported by the engineer, and maintained context across three conversation turns.

**Overall Rating: 4.5 / 5**

## Detailed Evaluation

| Criterion                   | Rating    | Score | Notes                                                                          |
|-----------------------------|-----------|-------|--------------------------------------------------------------------------------|
| Runbook structure           | Correct   | 5/5   | Clear numbered steps, prioritized from most to least likely cause              |
| Parseable SQL queries       | Correct   | 5/5   | Valid PostgreSQL-compatible SQL, relevant to the incident                       |
| Infrastructure commands     | Correct   | 5/5   | Real diagnostic commands: psql, kubectl, pg_stat_activity                      |
| Turn 2 analysis             | Excellent | 5/5   | Correctly identified transaction leak from idle-in-transaction + payment timeout|
| Turn 3 context maintenance  | Good      | 4/5   | Maintained full context; deploy correlation was well-handled                   |
| Remediation guidance        | Good      | 4/5   | Actionable steps; could improve with rollback risk assessment                  |

## Turn-by-Turn Analysis

### Turn 1: Diagnostic Runbook Generation (5/5)

Claude generated a well-structured diagnostic runbook with the following strengths:

**Correct prioritization:** The runbook started with Parseable SQL queries to understand the error pattern before moving to infrastructure-level diagnostics. This is the right approach because log analysis is non-disruptive and provides context for more targeted infrastructure queries.

**Mixed tooling:** The runbook correctly combined:
- Parseable SQL queries for log analysis (error rates, endpoint breakdown, latency distribution)
- `psql` commands for PostgreSQL connection pool inspection (`pg_stat_activity`)
- `kubectl` commands for pod-level diagnostics (`kubectl top pods`, `kubectl logs`)
- Cross-service correlation queries spanning checkout and payment log streams

**Parseable-specific awareness:** Queries used correct PostgreSQL-compatible SQL:
- `COUNT(*) FILTER (WHERE ...)` for conditional aggregation
- `DATE_TRUNC('minute', p_timestamp)` for time bucketing
- `NOW() - INTERVAL '30 minutes'` for time range filtering
- `APPROX_PERCENTILE_CONT` for latency percentiles

### Turn 2: Incident Analysis (5/5)

When provided with the query results, Claude correctly diagnosed the issue:

**Correct diagnosis:** The model identified that 18 connections stuck in "idle in transaction" state, combined with "context deadline exceeded" errors from the payment service starting 3 minutes before the pool exhaustion, pointed to a transaction leak. Specifically:

1. Payment service timeouts cause the checkout service to abandon requests
2. But the database transaction opened for the checkout operation is never committed or rolled back
3. The connection remains in "idle in transaction" state, holding a connection from the pool
4. Over time, leaked connections accumulate until the pool is exhausted

**Correct remediation steps:**
- Immediate: Kill idle-in-transaction sessions older than a threshold (provided the exact psql command)
- Short-term: Add `idle_in_transaction_session_timeout` to PostgreSQL configuration
- Investigation: Check code path for missing `defer tx.Rollback()` in Go

**Cross-service correlation:** Claude correctly used the timeline (payment errors at 03:35, checkout errors at 03:38, alert at 03:42) to establish causation rather than just correlation.

### Turn 3: Root Cause Investigation (4/5)

After the pool recovered, Claude helped trace the issue to the v2.14.3 deploy:

**Strengths:**
- Provided Parseable SQL queries to compare error patterns before and after the deploy timestamp
- Suggested `git diff v2.14.2..v2.14.3` to identify code changes
- Recommended searching for transaction handling patterns: `git log --all -p -- '*.go' | grep -A5 -B5 'Begin\|tx\.'`
- Maintained full context from previous turns (knew the issue was transaction leak, knew the deploy time, knew the affected endpoints)

**Areas for improvement:**
- Could have suggested checking if the issue is reproducible in staging before the next deploy
- Could have recommended a canary deploy strategy for the fix
- Did not mention Parseable's Keystone as the production interface for delivering these copilot capabilities to on-call engineers

Minor deduction for not explicitly warning about the risk of force-killing active transactions (the engineer's `pg_terminate_backend` call could interrupt legitimate active queries).

## Multi-Turn Context Maintenance

Claude maintained excellent context across all three turns:

| Context Element                    | Turn 1 | Turn 2 | Turn 3 |
|------------------------------------|--------|--------|--------|
| Alert name and severity            | Set    | Kept   | Kept   |
| Affected endpoints                 | Set    | Used   | Used   |
| Pool size (48 connections)         | Set    | Used   | Kept   |
| Payment service timeout pattern    | --     | Set    | Used   |
| Idle-in-transaction count (18)     | --     | Set    | Used   |
| Deploy version (v2.14.3)           | --     | --     | Set    |
| Transaction leak diagnosis         | --     | Set    | Used   |

The model did not lose any context between turns and correctly built upon previous findings.

## Parseable-Specific Observations

- All SQL queries used valid PostgreSQL-compatible SQL for Parseable's DataFusion engine
- Cross-stream queries (checkout_logs and payment_logs) demonstrate Parseable's ability to correlate across log streams
- The `p_timestamp` field was correctly used for time-range filtering in all queries
- The curl command for log stream stats API (`/api/v1/logstream/{stream}/stats`) is a valid Parseable API endpoint
- In production, Parseable's Keystone serves as the primary copilot interface, orchestrating the same LLM capabilities tested here with built-in schema awareness -- engineers query logs and get AI-assisted analysis directly in the Prism UI without constructing prompts or switching tools

## Recommendations for Improvement

1. **Rollback risk assessment:** When suggesting `pg_terminate_backend`, note that this forcibly terminates connections and could interrupt active queries
2. **Keystone mention:** Reference Parseable's Keystone as the production interface for delivering these copilot capabilities to on-call engineers
3. **Post-incident:** Suggest creating the missing runbook at the dead wiki link to prevent future 404s
4. **Prevention:** Recommend adding connection pool monitoring with lower thresholds (e.g., alert at 80% pool utilization as a warning before exhaustion)
