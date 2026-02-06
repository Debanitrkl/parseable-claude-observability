# Experiment 04: Alert Correlation -- Evaluation

## Evaluation Criteria

### 1. Alert Grouping (Weight: 30%)

**Expected grouping into 3 clusters:**

| Cluster | Alerts | Rationale |
|---------|--------|-----------|
| **Payment (Trigger)** | PaymentServiceLatencyHigh, PaymentServiceErrorRate, PaymentCircuitBreakerOpen | All originate from the payment service; circuit breaker confirms downstream gateway failure |
| **Checkout (Primary Cascade)** | CheckoutDBPoolExhausted, CheckoutLatencyHigh, CheckoutErrorRate, CheckoutCPUHigh, CheckoutGoroutineCount, PodRestartCount | All symptoms of checkout service overwhelmed by payment failures; DB pool exhaustion is the key mechanism |
| **Downstream (Noise/Secondary)** | CartServiceTimeout, FrontendErrorRate, FrontendLatencyHigh, SLOBurnRateCheckout, SLOBurnRateFrontend, SLOBurnRateOverall, EmailServiceQueueDepth, ShippingServiceTimeout, RecommendationLatencyHigh | Downstream effects and derived SLO metrics; not actionable on their own |

**Scoring:**
- 3/3: All three clusters correctly identified with correct alert membership
- 2/3: Two clusters identified correctly; third partially correct
- 1/3: One cluster identified correctly
- 0/3: Incorrect grouping

**Model Score: 3/3** -- Correctly identified all three clusters

### 2. Trigger Identification (Weight: 25%)

**Expected trigger:** PaymentServiceLatencyHigh (14:30:02) as the first alert, with the root cause being the payment gateway TLS/connectivity issue (evidenced by the circuit breaker opening at 14:32:18).

**Scoring:**
- 3/3: Correctly identifies payment service as trigger and reasons about TLS/gateway issue
- 2/3: Identifies payment as trigger but attributes to wrong mechanism
- 1/3: Identifies wrong trigger service
- 0/3: No trigger identification

**Model Score: 3/3** -- Correctly identified payment as trigger and cited the circuit breaker as evidence of downstream gateway failure

### 3. Signal vs Noise (Weight: 20%)

**Expected classification:**

| Classification | Alerts |
|---------------|--------|
| **Signal (Actionable)** | PaymentServiceLatencyHigh, PaymentServiceErrorRate, PaymentCircuitBreakerOpen, CheckoutDBPoolExhausted |
| **Symptom (Non-actionable)** | All remaining 14 alerts |

**Scoring:**
- 3/3: Correctly classifies 4 signal alerts and explains why the rest are symptoms
- 2/3: Mostly correct with 1-2 misclassifications
- 1/3: Significant misclassifications
- 0/3: No classification attempted

**Model Score: 2/3** -- Correctly classified 3 of 4 signal alerts; included CheckoutCPUHigh as actionable when it is a symptom of the connection pool exhaustion

### 4. Remediation Suggestions (Weight: 15%)

**Expected suggestions:**
1. **Immediate:** Check payment service TLS certificates and downstream gateway connectivity
2. **Short-term:** Increase checkout DB connection pool timeout or activate payment circuit breaker fallback
3. **Communication:** Page the payments team, update status page

**Scoring:**
- 3/3: All three categories of remediation addressed
- 2/3: Two categories addressed
- 1/3: Only immediate actions suggested
- 0/3: No useful remediation

**Model Score: 3/3** -- Comprehensive remediation covering all three categories

### 5. Causal Chain Accuracy (Weight: 10%)

**Expected chain:**
```
Payment gateway TLS failure
  -> Payment latency spike (threads waiting for TLS handshake timeout)
  -> Payment error rate increase (timeouts converted to errors)
  -> Checkout DB pool exhaustion (goroutines blocked waiting for payment response hold DB connections)
  -> Checkout latency and errors (no DB connections available)
  -> Frontend and downstream cascade (checkout unavailable)
```

**Scoring:**
- 3/3: Correct 5-step chain with accurate mechanism descriptions
- 2/3: Correct chain but missing mechanism detail
- 1/3: Partially correct chain
- 0/3: Incorrect chain

**Model Score: 2/3** -- Correct chain direction (payment -> checkout -> downstream) but did not specifically identify the DB pool exhaustion mechanism as being caused by goroutines holding connections while waiting for payment

## What Was Missed

The model did not identify the following nuance:

- **Cart -> Checkout dependency is uncertain without a service graph.** The CartServiceTimeout alert labels include `dependency: checkout-service`, but in a real scenario without explicit dependency metadata, it would be unclear whether cart calls checkout or the reverse. The model assumed cart depends on checkout, which is correct for this scenario but would require service graph data to confirm in production.

- **Recommendation service latency** may be coincidental rather than caused by the cascade. The recommendation service does not have an obvious dependency on checkout or payment. The model correctly flagged it as noise but did not consider that it might be an unrelated issue masked by the alert storm.

## Summary

| Criterion | Weight | Score | Weighted |
|-----------|--------|-------|----------|
| Alert Grouping | 30% | 3/3 | 0.90 |
| Trigger Identification | 25% | 3/3 | 0.75 |
| Signal vs Noise | 20% | 2/3 | 0.40 |
| Remediation | 15% | 3/3 | 0.45 |
| Causal Chain | 10% | 2/3 | 0.20 |
| **Total** | **100%** | | **2.70/3.00** |

**Overall: Pass** (threshold: 2.0/3.0)
