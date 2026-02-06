# Experiment 05: Incident Root Cause Analysis

**Type:** Live Experiment
**Model:** Claude Opus 4.6
**Date:** 2025-01-15
**Score:** Pass -- Correct diagnosis with high confidence

## Objective

Evaluate Claude Opus 4.6's ability to perform multi-signal root cause analysis using logs, traces, and metrics exported from Parseable log streams.

## Known Fault

The incident was caused by a **CPU resource limit misconfiguration** on the payment service. A YAML typo in the Kubernetes deployment set the CPU limit to `200m` (200 millicores) instead of the intended `2000m` (2 full cores). Under normal load this was sufficient, but during a traffic spike the payment service was immediately CPU-throttled by the Linux CFS (Completely Fair Scheduler), causing:

- gRPC deadline exceeded errors on all downstream calls
- Payment processing latency spiking from ~200ms to 4000-5000ms
- Checkout success rate dropping from 99.2% to 61.3%

## Data Sources

All data was exported from Parseable log streams:

| Stream | Description |
|--------|-------------|
| `application-logs` | Structured application logs with service_name, level, message |
| `traces` | Distributed trace spans with timing and status |
| `k8s-metrics` | Kubernetes resource metrics (CPU, memory, pod status) |

## Results

The model correctly identified:

1. **Root cause:** CPU throttling on the payment service (200m limit vs actual need)
2. **Failure chain:** CPU throttle -> gRPC timeouts -> checkout failures -> success rate drop
3. **Immediate remediation:** Increase CPU limit to 2000m (or higher) and restart pods
4. **Long-term prevention:**
   - CI/CD pipeline validation for resource limits (detect 10x reductions)
   - CFS throttle rate alerts (alert when `container_cpu_cfs_throttled_seconds_total` exceeds threshold)
   - Load testing in staging with production-equivalent resource limits

## Confidence

The model expressed high confidence in the diagnosis because:
- CPU utilization was at 100% of the 200m limit (not 100% of node capacity)
- The throttle pattern matched the latency distribution shift exactly
- No other resource (memory, disk, network) was under pressure
- The timing of CPU saturation correlated with the onset of gRPC errors

## Files

- `prompt.md` -- The full RCA prompt with all signal sections
- `sample_data.json` -- Incident data: symptoms, logs, traces, metrics
- `parseable_queries.sql` -- SQL queries to extract incident data from Parseable
- `evaluation.md` -- Evaluation criteria and detailed scoring
