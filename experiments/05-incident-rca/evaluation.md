# Experiment 05: Incident RCA -- Evaluation

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

**Model Score: 3/3** -- Correctly identified the CPU limit typo (200m vs 2000m) and cited CFS throttling metrics, deployment diff, and the absence of other resource pressure as supporting evidence.

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

**Model Score: 3/3** -- Identified all 5 steps. Notably called out the retry amplification pattern as making the situation worse, which is a sophisticated observation.

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

**Model Score: 3/3** -- Recommended setting CPU limit to 2000m explicitly, suggested a rolling restart (not a full redeploy), and mentioned status page updates.

### 4. Long-term Prevention (Weight: 20%)

**Expected prevention measures:**

1. **CI/CD validation:** Add a pipeline check that flags resource limit changes greater than 50% (would have caught the 10x reduction from 2000m to 200m)
2. **CFS throttle alerts:** Alert on `container_cpu_cfs_throttled_seconds_total` exceeding a threshold. This metric directly measures CPU throttling and would have caught the issue before it impacted latency.
3. **Resource limit guardrails:** Implement admission webhooks or OPA policies that prevent setting CPU limits below a minimum threshold for critical services
4. **Load testing:** Run load tests in staging with production-equivalent resource limits to catch misconfigurations before they reach production

**Scoring:**
- 3/3: At least 3 of 4 prevention measures identified
- 2/3: 2 of 4 measures identified
- 1/3: 1 measure identified
- 0/3: No useful prevention measures

**Model Score: 3/3** -- Identified CI/CD validation, CFS throttle alerting, and load testing. Also suggested a Kubernetes LimitRange object as an additional guardrail.

## Summary

| Criterion | Weight | Score | Weighted |
|-----------|--------|-------|----------|
| Root Cause Identification | 35% | 3/3 | 1.05 |
| Failure Chain | 25% | 3/3 | 0.75 |
| Immediate Remediation | 20% | 3/3 | 0.60 |
| Long-term Prevention | 20% | 3/3 | 0.60 |
| **Total** | **100%** | | **3.00/3.00** |

**Overall: Pass** (threshold: 2.0/3.0)

## Observations

1. **High confidence was justified.** The model explicitly stated high confidence because multiple independent signals (CPU metrics, CFS throttle count, deployment diff, latency correlation) all pointed to the same root cause. This is the correct reasoning pattern for RCA.

2. **Retry amplification was called out.** The model identified that checkout's 3-retry pattern was making the situation worse by tripling load on the throttled payment service. This is a nuanced observation that many junior SREs miss.

3. **Deployment diff was treated as definitive.** The model correctly treated the `2000m -> 200m` change in the deployment history as the smoking gun, rather than just one of many signals.

4. **No false leads.** The model did not pursue any incorrect hypotheses (e.g., network issues, memory pressure, downstream gateway failures). The CFS throttle count and CPU utilization at limit were correctly interpreted as the primary signal.
