# Experiment 06: Trace Analysis -- Evaluation

## Evaluation Criteria

### 1. Tree Reconstruction (Weight: 30%)

**Expected tree:**

```
frontend (POST /api/checkout) [span_0001] .................. 1847ms
  ├─ frontend (AuthMiddleware) [span_0002] .................   12ms
  ├─ frontend (RateLimitCheck) [span_0003] .................    3ms
  └─ checkout-service (ProcessCheckout) [span_0004] ........ 1790ms
       ├─ checkout-service (ValidateRequest) [span_0005] ...    8ms
       ├─ cart-service (GetCart) [span_0006] ................ 142ms
       │    ├─ cart-service (Redis.Get) [span_0007] ........    4ms
       │    ├─ product-catalog (GetProducts) [span_0008] ...   89ms
       │    │    ├─ product-catalog (PostgreSQL.Query) ......   67ms
       │    │    └─ product-catalog (Cache.Set) .............    5ms
       │    └─ cart-service (CalculateTotal) [span_0011] ...    6ms
       ├─ payment-service (ProcessPayment) [span_0012] ..... 1203ms
       │    ├─ payment-service (ValidateCard) [span_0013] ..   23ms
       │    ├─ payment-service (FraudCheck) [span_0014] .... 156ms
       │    ├─ currency-service (Convert) [span_0015] ......   34ms
       │    │    └─ currency-service (Redis.Get) [span_0016]    2ms
       │    ├─ payment-service (GatewayCharge) [span_0017] . 934ms
       │    │    ├─ payment-service (TLS.Handshake) ........   45ms
       │    │    └─ payment-service (HTTP.POST gateway) .... 867ms
       │    └─ payment-service (PostgreSQL.Insert) .........   18ms
       ├─ shipping-service (CalculateShipping) [span_0021] . 287ms
       │    ├─ shipping-service (GetWarehouseLocations) ....   34ms
       │    ├─ shipping-service (CalculateRates) [span_0023] 198ms
       │    └─ email-service (SendConfirmation) [span_0024]  156ms
       │         ├─ email-service (RenderTemplate) .........   23ms
       │         └─ email-service (SMTP.Send) .............. 120ms
       └─ checkout-service (UpdateOrderStatus) [span_0027] .  45ms
            └─ checkout-service (PostgreSQL.Update) ........   38ms
```

**Scoring:**
- 3/3: Correct tree structure with all 28 spans correctly placed
- 2/3: Minor errors (1-2 misplaced spans) but overall structure correct
- 1/3: Major structural errors
- 0/3: Unable to reconstruct tree

**Model Score: 3/3** -- Correctly reconstructed the full tree with all 28 spans in the right positions.

### 2. Critical Path Identification (Weight: 25%)

**Expected critical path:**

```
frontend (POST /api/checkout)         1847ms (37ms self-time)
  └─ checkout-service (ProcessCheckout) 1790ms (~22ms self-time)
       └─ payment-service (ProcessPayment) 1203ms (~38ms self-time)
            └─ payment-service (GatewayCharge) 934ms (~22ms self-time)
                 └─ payment-service (HTTP.POST gateway) 867ms (867ms self-time)
```

The critical path is: **frontend -> checkout-service -> payment-service -> GatewayCharge -> HTTP.POST**

Total critical path duration: 1847ms, dominated by the 867ms HTTP call to the payment gateway.

**Scoring:**
- 3/3: Correct critical path with all 5 hops identified
- 2/3: Correct top 3 hops (frontend -> checkout -> payment) but misses inner critical path
- 1/3: Identifies payment as bottleneck but wrong path
- 0/3: Incorrect critical path

**Model Score: 3/3** -- Correctly identified the full critical path through to the gateway HTTP call.

### 3. Bottleneck Detection (Weight: 20%)

**Expected bottleneck analysis:**

The primary bottleneck is `payment-service (ProcessPayment)` at span_0012:
- **Total duration:** 1203ms
- **Child durations:** ValidateCard(23ms) + FraudCheck(156ms) + Convert(34ms) + GatewayCharge(934ms) + PostgreSQL.Insert(18ms) = 1165ms
- **Self-time:** 1203ms - 1165ms = ~38ms

However, the deeper bottleneck is the external gateway call:
- `HTTP.POST gateway.stripe.com` [span_0019]: 867ms self-time (leaf span, no children)

This is the single largest contributor to the trace duration -- an external HTTP call to the payment gateway that accounts for 47% of the total trace duration (867ms / 1847ms).

**Scoring:**
- 3/3: Identifies both the payment service and the gateway call as bottlenecks with self-time calculations
- 2/3: Identifies payment service as bottleneck but misses the gateway call detail
- 1/3: Generic bottleneck identification without self-time analysis
- 0/3: Wrong bottleneck

**Model Score: 3/3** -- Correctly identified the gateway HTTP call as the deepest bottleneck and calculated self-times.

### 4. Parallelism Detection (Weight: 15%)

**Expected parallelism findings:**

Under `checkout-service (ProcessCheckout)` [span_0004], the following children execute in parallel:

| Span | Service | Start Time | Duration |
|------|---------|-----------|----------|
| span_0012 | payment-service | 14:32:00.180 | 1203ms |
| span_0021 | shipping-service | 14:32:00.182 | 287ms |

Evidence: Both start within 2ms of each other (after cart-service returns at ~14:32:00.174), indicating they are dispatched concurrently.

Key observation: Shipping completes at ~14:32:00.469 while payment completes at ~14:32:01.383. The overall checkout duration is gated by payment, not shipping. If they were sequential, checkout would take ~1203 + 287 = 1490ms for just these two calls, but since they overlap, the combined wall time is just ~1203ms.

**Scoring:**
- 3/3: Correctly identifies payment and shipping as parallel, explains impact on total duration
- 2/3: Identifies parallelism but does not explain duration impact
- 1/3: Mentions parallelism vaguely
- 0/3: Misses parallelism

**Model Score: 3/3** -- Correctly identified the parallel execution of payment and shipping, and explained that the checkout duration is gated by the slower payment path.

### 5. Plain-English Narrative (Weight: 10%)

**Expected narrative (example):**

A checkout request arrived at the frontend and was routed to the checkout service after passing authentication and rate limiting (15ms). The checkout service first fetched the user's cart (142ms), which included a product catalog lookup. It then dispatched payment processing and shipping calculation in parallel. Payment was the bottleneck at 1203ms, dominated by an 867ms call to the external Stripe payment gateway. Shipping completed in 287ms. After payment confirmed, the order status was updated in the database (45ms) and the total request completed in 1847ms.

**Scoring:**
- 3/3: Clear, accurate narrative covering all major phases with timing
- 2/3: Mostly accurate but missing key details
- 1/3: Vague or partially incorrect narrative
- 0/3: Inaccurate narrative

**Model Score: 3/3** -- Produced a clear, accurate narrative suitable for a non-technical audience.

## Summary

| Criterion | Weight | Score | Weighted |
|-----------|--------|-------|----------|
| Tree Reconstruction | 30% | 3/3 | 0.90 |
| Critical Path | 25% | 3/3 | 0.75 |
| Bottleneck Detection | 20% | 3/3 | 0.60 |
| Parallelism Detection | 15% | 3/3 | 0.45 |
| Plain-English Narrative | 10% | 3/3 | 0.30 |
| **Total** | **100%** | | **3.00/3.00** |

**Overall: Pass** (threshold: 2.0/3.0)

## Key Observations

1. **Flat-to-tree reconstruction is straightforward for the model.** Given `span_id` and `parent_span_id`, the model had no difficulty building the hierarchy. This is encouraging because Parseable stores spans as flat records, and this reconstruction must happen at analysis time.

2. **Self-time calculation was correct.** The model correctly subtracted child durations from parent durations to identify where time was actually spent. This is a non-trivial operation that requires understanding the difference between wall-clock time and self-time in distributed traces.

3. **Parallelism detection used timestamps.** The model used the `p_timestamp` field (not just parent_span_id) to infer that payment and shipping were parallel. This is the correct approach -- sibling spans with overlapping time windows are likely parallel calls.

4. **External dependency highlighted.** The model correctly identified the Stripe gateway call as the primary latency contributor, which is valuable for capacity planning and SLO budgeting.
