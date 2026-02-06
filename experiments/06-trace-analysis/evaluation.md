# Experiment 06: Trace Analysis -- Evaluation

## Experiment Context

Claude was given raw span data from a **real distributed trace** captured from the OpenTelemetry Demo application running against Parseable. The trace (`971a659583cb354ebf2a7babf50db2f8`) contained 33 spans across 5 real services: load-generator, frontend-proxy, frontend, product-catalog, and cart. Claude was asked to reconstruct the service call tree, identify the critical path, detect bottlenecks, find anomalous spans, and produce a plain-English narrative.

**Model:** Claude Opus 4.6 (`claude-opus-4-6`)
**Input tokens:** 24,376 | **Output tokens:** 3,513 | **Cost:** $0.63 | **Latency:** 65.4s
**Stop reason:** `end_turn` (completed naturally)

## Evaluation Criteria

### 1. Tree Reconstruction (Weight: 30%)

**Expected:** Reconstruct the full span hierarchy from flat span records using `span_span_id` and `span_parent_span_id` fields.

**Scoring:**
- 3/3: Correct tree structure with all spans correctly placed
- 2/3: Minor errors (1-2 misplaced spans) but overall structure correct
- 1/3: Major structural errors
- 0/3: Unable to reconstruct tree

**Model Score: 3/3** -- Claude first performed deduplication (noting that several spans appeared multiple times in the flat array due to multiple events per span), identifying 20+ unique spans. The reconstructed ASCII tree correctly shows:
- Root: `load-generator` `user_add_to_cart` (1,080.96 ms)
- Branch 1: GET /api/products/HQTGWGPNH4 path through frontend-proxy -> frontend -> product-catalog (6.01 ms total)
- Branch 2: POST /api/cart path through frontend-proxy -> frontend -> cart service with Redis operations (1,074.40 ms total)
- Leaf spans: Redis HGET, HMSET, EXPIRE operations under cart service

The deduplication step (Step 0) was a valuable addition -- real Parseable trace data includes multiple rows per span (one per span event), and the model correctly handled this without being prompted.

### 2. Critical Path Identification (Weight: 25%)

**Expected critical path:** The longest chain through the POST /api/cart branch, dominated by the gRPC AddItem client span.

**Scoring:**
- 3/3: Correct critical path with all hops identified and self-time calculations
- 2/3: Correct top-level path but misses inner critical path
- 1/3: Identifies the slow branch but wrong path
- 0/3: Incorrect critical path

**Model Score: 3/3** -- Correctly identified the critical path through the POST branch:
```
user_add_to_cart (1,080.96 ms) -> POST client (1,074.40 ms) -> ingress (1,069.75 ms)
-> router egress (1,069.68 ms) -> POST /api/cart (1,069.49 ms) -> handleRequest (1,069.38 ms)
-> executing api route (1,069.14 ms) -> grpc.CartService/AddItem (1,066.79 ms)
```
Each hop included both duration and self-time calculations, correctly showing that the `grpc.CartService/AddItem` CLIENT span consumed ~1,066 ms of self-time while the actual cart server processing took only 0.38 ms.

### 3. Bottleneck Detection (Weight: 20%)

**Expected:** Identify the gRPC AddItem client span as the bottleneck, with extreme client-to-server time gap.

**Scoring:**
- 3/3: Identifies the bottleneck with self-time calculations and root cause hypothesis
- 2/3: Identifies bottleneck but misses the client-server gap analysis
- 1/3: Generic bottleneck identification
- 0/3: Wrong bottleneck

**Model Score: 3/3** -- Correctly identified `grpc.oteldemo.CartService/AddItem` (span `0ebfca528fb2a3c7`) as the bottleneck:
- Total duration: 1,066.79 ms
- Child spans total: ~2.52 ms (dns.lookup + tcp.connect + cart server)
- Self-time: ~1,064.27 ms (99.76% of its duration)

Provided a clear root cause hypothesis: the ~1,064 ms of unaccounted time is consumed by gRPC channel setup / HTTP/2 negotiation after TCP connection establishment. The dns.lookup (1.36 ms) and tcp.connect (0.78 ms) children confirm a **new connection** was being established (not reusing a pooled connection).

### 4. Anomalous Span Detection (Weight: 15%)

**Expected:** Identify unusual patterns in the trace data.

**Scoring:**
- 3/3: Identifies multiple anomalies with evidence and impact assessment
- 2/3: Identifies 1-2 anomalies
- 1/3: Vague anomaly detection
- 0/3: No anomalies found

**Model Score: 3/3** -- Identified 3 anomalies plus a positive finding:

1. **Extreme client-to-server time gap (2,800:1 ratio):** Client span 1,066.79 ms vs. server span 0.38 ms. This is a severe connection establishment delay.
2. **DNS lookup and TCP connect as children of gRPC call:** Indicates no pre-existing connection pool to the cart service -- either a cold start or connection eviction.
3. **Sequential GET then POST with 178x time difference:** GET path (product-catalog) completed in 6 ms while POST path (cart) took 1,074 ms despite doing comparable work.
4. **No error-status anomalies:** Confirmed all spans have status code 0 (OK) and HTTP 200 -- this is a latency issue, not a functional failure.

### 5. Plain-English Narrative (Weight: 10%)

**Expected:** Clear narrative suitable for a non-technical audience.

**Scoring:**
- 3/3: Clear, accurate narrative covering all major phases with timing
- 2/3: Mostly accurate but missing key details
- 1/3: Vague or partially incorrect
- 0/3: Inaccurate narrative

**Model Score: 3/3** -- Produced a concise narrative explaining that a load-generator test simulated adding product HQTGWGPNH4 to a cart, the product lookup completed in 6 ms but the cart addition took over 1 second due to a new gRPC connection being established (not a server-side issue), and the problem would likely resolve on subsequent requests once the connection is pooled.

## Summary

| Criterion | Weight | Score | Weighted |
|-----------|--------|-------|----------|
| Tree Reconstruction | 30% | 3/3 | 0.90 |
| Critical Path | 25% | 3/3 | 0.75 |
| Bottleneck Detection | 20% | 3/3 | 0.60 |
| Anomalous Span Detection | 15% | 3/3 | 0.45 |
| Plain-English Narrative | 10% | 3/3 | 0.30 |
| **Total** | **100%** | | **3.00/3.00** |

**Overall: Pass** (threshold: 2.0/3.0)

## Key Observations

1. **Deduplication was handled unprompted.** Real Parseable trace data includes multiple rows per span (one per span event like "Enqueued", "Sent", "ResponseReceived"). Claude identified this pattern and deduplicated by `span_span_id` before reconstruction, producing a clean 20+ unique span table. This is a practical skill that would be required in any real Parseable trace analysis workflow.

2. **Client-server gap analysis was the key insight.** The 2,800:1 ratio between client span (1,066 ms) and server span (0.38 ms) immediately narrows the problem to connection establishment overhead, not server-side processing. This distinction is critical for directing remediation to the right team.

3. **gRPC connection pooling recommendation was implicit.** By identifying dns.lookup and tcp.connect as children of the gRPC call, Claude demonstrated that the frontend lacked a warm connection pool to the cart service. The fix (pre-warming connections or increasing pool TTL) follows directly from this observation.

4. **Real data vs. synthetic data.** Unlike the previous evaluation which used a synthetic 28-span checkout trace, this experiment used a real 33-span trace from the OTel Demo. The model handled the messier real-world data (duplicate span events, real nanosecond timestamps, actual OTel Demo service names) without difficulty.

5. **Self-time calculation was precise.** The model correctly calculated self-time by subtracting child durations from parent durations across the entire tree, identifying exactly where wall-clock time was consumed versus simply propagated through parent spans.
