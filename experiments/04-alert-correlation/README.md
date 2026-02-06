# Experiment 04: Alert Correlation

**Type:** Scenario-Based
**Model:** Claude Opus 4.6
**Date:** 2025-01-15
**Score:** Pass

## Objective

Evaluate Claude Opus 4.6's ability to analyze an alert storm and identify root cause, cascading failures, and noise in a realistic microservices incident scenario.

## Scenario: Cascading Failure

An e-commerce platform experiences an alert storm with **18 alerts firing within a 5-minute window** (14:30:02 to 14:34:30). The underlying scenario is:

1. **Trigger:** Payment service experiences a TLS certificate issue connecting to a downstream payment gateway
2. **Primary cascade:** Payment service latency spikes, causing the checkout service's database connection pool to exhaust (waiting threads pile up)
3. **Secondary cascade:** Checkout failures cascade to frontend, cart, shipping, and recommendation services
4. **Noise:** SLO burn rate alerts, email queue depth, and pod restart counts are symptoms, not causes

### Expected Root Cause Chain

```
Payment TLS cert expiry
  -> Payment service latency spike (14:30:02)
  -> Payment service error rate rise (14:30:15)
  -> Checkout DB pool exhaustion (14:30:28) -- waiting threads blocked on payment
  -> Checkout latency and error rate (14:30:45, 14:31:02)
  -> Frontend and downstream cascade (14:31:15+)
```

## Results

The model correctly:
- Grouped alerts into 3 clusters (payment origin, checkout cascade, downstream noise)
- Identified the payment service as the trigger event
- Distinguished 4 actionable alerts from 14 noise/symptom alerts
- Recommended checking payment service TLS certificates and downstream connectivity
- Suggested immediate remediation: circuit breaker activation and connection pool tuning

## Parseable's Built-in Alerting

Parseable provides built-in alerting capabilities that complement this type of LLM-driven analysis:

| Alert Type | Description | Targets |
|-----------|-------------|---------|
| **Threshold alerts** | Fire when a metric crosses a static threshold | Slack, webhook, email |
| **Anomaly detection** | ML-based detection of unusual patterns in log volume or latency | Slack, webhook, email |
| **Forecasting alerts** | Predictive alerts based on trend extrapolation | Slack, webhook, email |

Parseable supports **8 alert targets**: Slack, webhook, email, PagerDuty, OpsGenie, Microsoft Teams, Discord, and custom HTTP endpoints.

The combination of Parseable's real-time alerting with LLM-based correlation analysis provides:
- Parseable detects and fires alerts in real time
- Claude (or similar LLM) correlates the alert storm post-hoc to identify root cause
- This reduces MTTR by focusing the on-call engineer on the trigger event rather than chasing symptoms

## Files

- `prompt.md` -- The alert correlation prompt
- `sample_data.json` -- 18 alerts in chronological order
- `evaluation.md` -- Evaluation criteria and scoring
- `parseable_queries.sql` -- Supporting SQL queries to pull context from Parseable during an alert storm
