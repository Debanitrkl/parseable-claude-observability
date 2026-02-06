# Experiment 05: Incident RCA -- Evaluation

## Experiment Context

Claude was given a multi-signal incident dataset (CPU metrics, deployment history, trace data, and service logs) for a checkout success rate degradation scenario. The ground truth root cause was a CPU resource limit misconfiguration on the payment service (a typo reducing the limit from 2000m to 200m).

**Model:** Claude Opus 4.6 (`claude-opus-4-6`)
**Input tokens:** 8,167 | **Output tokens:** 3,935 | **Cost:** $0.42 | **Latency:** 82.2s
**Stop reason:** `end_turn` (completed naturally)

## Evaluation Criteria

### 1. Root Cause Identification (Weight: 35%)

**Expected root cause:** CPU resource limit misconfiguration on the payment service. The Kubernetes deployment YAML was changed from `2000m` to `200m` (a typo -- missing one zero), causing the Linux CFS (Completely Fair Scheduler) to aggressively throttle the payment service under normal load.

**Key evidence the model should cite:**
- CPU usage at 199m / 200m limit (99.5% utilization of a very low limit)
- 4,601 CFS throttle periods in 5 minutes (187.3 seconds of throttled time)
- Deployment diff showing `resources.limits.cpu: 2000m -> 200m`
- Memory and other resources are not under pressure (eliminates other hypotheses)
- Latency shift from p50=187ms to p50=3891ms correlates with CPU starvation

**Scoring:**
- 3/3: Correctly identifies CPU throttling as root cause with deployment diff as evidence
- 2/3: Identifies CPU issue but misses the deployment diff or misattributes the cause
- 1/3: Identifies payment service as the problem but wrong mechanism
- 0/3: Wrong root cause

**Model Score: 3/3** -- Correctly identified the CPU limit typo (2000m -> 200m) as the root cause with "99% -- Virtually Certain" confidence. Cited all key evidence: CPU at 199m/200m (99.5% saturation), 4,601 CFS throttled periods / 187.3s of throttled time, the deployment diff, healthy memory (50% utilization ruling out OOM), and the 20.8x latency increase (187ms -> 3,891ms). The response explicitly labeled the deployment diff as "Definitive" evidence.

### 2. Failure Chain (Weight: 25%)

**Expected 5-step failure chain:**

1. **CPU throttling activates:** Payment service hits 200m CPU limit under normal traffic. CFS throttles the process, adding 2-4 seconds of scheduling delays per request.
2. **gRPC deadlines exceeded:** Payment service cannot complete requests within 2000ms timeout. gRPC calls to payment-gateway fail with `DeadlineExceeded`.
3. **Checkout retries amplify load:** Checkout service retries failed payment calls (3 retries), tripling the load on an already throttled payment service.
4. **Checkout success rate drops:** With payment consistently failing, checkout success rate falls from 99.2% to 61.3%.
5. **Customer-facing errors:** Frontend surfaces "Payment processing failed" errors to end users.

**Scoring:**
- 3/3: All 5 steps identified in correct order with accurate mechanism descriptions
- 2/3: Chain direction correct but missing 1-2 steps or inaccurate mechanisms
- 1/3: Partially correct chain
- 0/3: Incorrect chain

**Model Score: 3/3** -- Produced a 7-step failure chain (more detailed than required) covering: trigger (deploy typo at 08:25 UTC), CPU saturation (14:25 UTC), latency explosion with CFS mechanics, cascading failures to checkout-service, retry amplification (3x multiplier creating feedback loop), customer impact (38.7% payment failures, success rate 99.2% -> 61.3%), alert firing (14:28, 3-min TTD), and resolution (14:52, 27-min TTR). Included both an ASCII timeline and an architectural diagram showing failure propagation.

The retry amplification observation was particularly strong -- Claude noted that the 3x retry pattern increased load on the already-saturated payment service, causing the throttle count to accelerate from 847 -> 4,601.

### 3. Immediate Remediation (Weight: 20%)

**Expected remediation steps:**

1. **Fix CPU limit:** Update payment-service deployment to set `resources.limits.cpu: 2000m` (or higher) and trigger a rolling restart
2. **Verify recovery:** Monitor payment service latency and error rate returning to baseline
3. **Communicate:** Update status page, notify affected customers if checkout failures were visible

**Scoring:**
- 3/3: All three steps identified with specific values (2000m, not just "increase CPU")
- 2/3: Remediation direction correct but missing specifics
- 1/3: Generic remediation without specific actions
- 0/3: Wrong remediation

**Model Score: 3/3** -- Provided a prioritized remediation table with 5 items:
- P0: Restore CPU limit to 2000m via `kubectl patch` (with exact JSON patch command)
- P0: Verify recovery (CFS throttle count stops increasing, p50 < 300ms, error rate < 1%)
- P1: Check for duplicate charges from retried payment requests
- P1: Audit failed orders during the 27-minute window for customer support
- P2: Communicate resolution to stakeholders

The duplicate charge audit (P1) was a valuable addition not in the expected output -- retried payment requests that partially succeeded upstream could cause revenue/trust issues.

### 4. Long-term Prevention (Weight: 20%)

**Expected prevention measures:**

1. **CI/CD validation:** Add a pipeline check that flags resource limit changes greater than 50%
2. **CFS throttle alerts:** Alert on `container_cpu_cfs_throttled_seconds_total` exceeding a threshold
3. **Resource limit guardrails:** Implement admission webhooks or OPA policies
4. **Load testing:** Run load tests in staging with production-equivalent resource limits

**Scoring:**
- 3/3: At least 3 of 4 prevention measures identified
- 2/3: 2 of 4 measures identified
- 1/3: 1 measure identified
- 0/3: No useful prevention measures

**Model Score: 3/3** -- Identified 14 prevention measures organized into three categories:

**Process & Deployment (5 measures):** CI/CD resource change validation, diff review enforcement, OPA/Kyverno admission policy rejecting >50% CPU limit drops, canary/progressive rollout with automated latency analysis, and separating infra changes from app changes (TLS cert rotation via cert-manager).

**Observability & Alerting (4 measures):** CFS throttle alert (on `container_cpu_cfs_throttled_periods_total` at 25% ratio), CPU limit utilization alert (at 85%), post-deploy latency comparison, and resource configuration drift detection.

**Resilience (5 measures):** Circuit breaker for checkout->payment path, retry with backoff + jitter, deadline propagation (frontend timeout -> gRPC deadline), HPA based on CPU utilization, and idempotency keys for payment operations.

The CFS throttle alert recommendation was particularly insightful -- Claude noted it would have detected the issue at ~08:30 UTC (6 hours earlier) during the first traffic bump, rather than waiting for the 14:25 UTC impact.

## Summary

| Criterion | Weight | Score | Weighted |
|-----------|--------|-------|----------|
| Root Cause Identification | 35% | 3/3 | 1.05 |
| Failure Chain | 25% | 3/3 | 0.75 |
| Immediate Remediation | 20% | 3/3 | 0.60 |
| Long-term Prevention | 20% | 3/3 | 0.60 |
| **Total** | **100%** | | **3.00/3.00** |

**Overall: Pass** (threshold: 2.0/3.0)

## Key Observations

1. **High confidence was justified.** The model stated "99% -- Virtually Certain" confidence because multiple independent signals (CPU metrics, CFS throttle count, deployment diff, latency correlation, healthy memory) all pointed to the same root cause. This is the correct reasoning pattern for RCA -- convergent evidence from independent sources.

2. **Retry amplification was called out.** The model identified that checkout's 3-retry pattern was making the situation worse by tripling load on the throttled payment service. This is a nuanced observation that many junior SREs miss. It also cited specific trace data (abc003 taking 15,234ms due to retries).

3. **Deployment diff was treated as definitive.** The model correctly treated the `2000m -> 200m` change in the deployment history as the smoking gun, and explained why the 6-hour latent period occurred (low morning traffic fit within 200m).

4. **No false leads.** The model did not pursue any incorrect hypotheses. Memory pressure, network issues, and downstream gateway failures were explicitly ruled out with evidence.

5. **Incident classification was thorough.** The response included a classification table (category: configuration error, trigger: human error/typo, blast radius, MTTR: 27 minutes) and 7 specific action items with owners and due dates.
