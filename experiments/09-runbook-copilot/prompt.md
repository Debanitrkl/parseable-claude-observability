# Prompt: Multi-Turn On-Call Copilot Conversation

## System Context

You are an expert SRE on-call copilot. You help engineers diagnose and resolve production incidents by combining log analysis (using Parseable SQL queries), infrastructure commands, and operational knowledge.

---

## Turn 1

**Alert Context:**

```
Alert: CheckoutDBPoolExhausted
Severity: P1
Service: checkout-service
Cluster: prod-us-east-1
Time: 2025-01-25T03:42:00Z
Description: Database connection pool utilization at 100% (48/48 connections in use).
             New requests are being rejected with "connection pool exhausted" errors.
Affected: /api/v1/checkout, /api/v1/cart/finalize
Runbook: https://wiki.internal/runbooks/db-pool-exhausted (404 - not found)
```

**User Message:**

"This P1 alert just fired. The linked runbook is a dead link. Generate a diagnostic runbook for me that includes Parseable SQL queries to investigate what's happening with the checkout service. I need to understand why the DB pool is exhausted."

---

## Turn 2

**User Message:**

"I ran the Parseable query and the psql check you suggested. Here are the results:

From Parseable - recent errors in the checkout stream:
- 847 errors in the last 30 minutes, all 'connection pool exhausted'
- Error rate jumped from 0.1% to 34% at 03:38 UTC
- The errors are only on `/api/v1/checkout` and `/api/v1/cart/finalize`

From psql (`SELECT state, count(*) FROM pg_stat_activity WHERE datname = 'checkout_db' GROUP BY state`):
- 18 connections in 'idle in transaction' state
- 24 connections in 'active' state
- 6 connections in 'idle' state

From Parseable - correlating with upstream services:
- Payment service logs show 'context deadline exceeded' errors starting at 03:35 UTC
- 23 payment requests stuck with no response logged

What does this tell us? What should I do next?"

---

## Turn 3

**User Message:**

"OK, I killed the idle-in-transaction sessions with `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle in transaction' AND query_start < NOW() - INTERVAL '5 minutes'`. The pool has recovered and errors are dropping.

But I need to find the root cause. Looking at the deploy log, we deployed checkout-service v2.14.3 yesterday at 14:00 UTC. This is the first time this alert has fired. How do I find the problematic code in that deploy? Can you give me Parseable queries and git commands to narrow it down?"
