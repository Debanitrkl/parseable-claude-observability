# Evaluation: Log Analysis

## Experiment Context

This experiment used **real production data** from the OpenTelemetry Demo application running against Parseable. The input consisted of live log lines from multiple OTel Demo services. Unlike synthetic scenarios with pre-injected anomalies, Claude was asked to find genuine anomalies in real operational data.

**Model:** Claude Opus 4.6 (`claude-opus-4-6`)
**Input tokens:** 126,451 | **Output tokens:** 2,870 | **Cost:** $2.11 | **Latency:** 68.4s
**Stop reason:** `end_turn` (completed naturally)

## Scoring Rubric

### Anomaly Detection (0-5 points)
- 1 point per correctly identified real anomaly (with evidence)
- Bonus point for cascading failure pattern identification
- -0.5 points per false positive

### Severity Classification (0-3 points)
- 1 point per correctly classified severity level (critical/warning/info)

### Root Cause Identification (0-3 points)
- 1 point per plausible root cause hypothesis with supporting evidence

### Output Quality (0-2 points)
- 1 point for valid JSON output matching requested schema
- 1 point for clear, actionable descriptions

## Results

| Criterion | Score | Max | Notes |
|-----------|-------|-----|-------|
| Anomaly detection | 5 | 5 | Found 9 anomalies (3 critical, 3 warning, 3 info) + 2 cascading failure patterns |
| Severity classification | 3 | 3 | Appropriate severity tiers: critical for 500 errors and load-gen crash, warning for CPU load and catalog reload, info for redirects and empty userId |
| Root cause identification | 3 | 3 | Plausible hypotheses for each anomaly, with trace IDs and timestamps as evidence |
| Output quality | 2 | 2 | Valid JSON, clear descriptions with evidence counts and time ranges |
| **Total** | **13** | **13** | |

## Anomalies Found by Claude

### Critical (3)
1. **Playwright browser context failure storm** in load-generator -- 52 TargetClosedError events in a tight error loop. Hypothesis: Chromium process crash due to memory pressure.
2. **HTTP 500 on POST /api/checkout** -- 2 failed checkout requests with trace IDs cited. Correctly identified as revenue-impacting.
3. **HTTP 500 on GET /api/products/OLJCESPC7Z** -- 3 requests for a specific product ID all returning 500, while other products succeed. Correctly identified the SKU-specific failure pattern.

### Warning (3)
4. **HTTP 500 on GET /api/recommendations** -- Intermittent failures on recommendation service (2 of 3 requests failed).
5. **Ad service CPU load problem pattern enabled** -- Detected the OTel Demo's intentional chaos injection feature flag.
6. **Product catalog reloading every ~1 second** -- Identified excessive 1-second reload interval with timestamps showing the pattern.

### Info (3)
7. **HTTP 308 redirects** on /api/data/ endpoints -- trailing slash causing unnecessary redirect hops.
8. **Cart service called with empty userId** -- potential session management issue.
9. **Kafka cluster metadata log segment rolling** -- correctly classified as normal housekeeping.

### Cascading Failure Patterns (2)
1. **Product OLJCESPC7Z failure -> checkout 500 cascade**: Product lookup fails, cart still accepts the item, checkout then fails trying to resolve product details.
2. **Ad service CPU load -> potential noisy-neighbor effect**: CPU problem pattern consuming shared host resources.

## Key Observations

1. **No injected anomalies -- all findings are from real data.** Since this was live OTel Demo data, there were no pre-planted anomalies with known ground truth. The evaluation assesses quality of analysis rather than recall against a fixed answer key.

2. **Trace ID citations throughout.** Claude cited specific trace IDs (e.g., `be27ceb66fab...`, `e720518cf095...`, `ffdb42b7...`) as evidence for each finding, making every claim verifiable against the raw data.

3. **Cascading failure reasoning was strong.** The connection between OLJCESPC7Z product failures and checkout 500s was a non-obvious cross-service correlation that required understanding the request flow (product lookup -> cart add -> checkout).

4. **OTel Demo domain knowledge.** Claude recognized the Ad service CPU load as an intentional "problem pattern" feature of the OpenTelemetry Demo, which is a specific domain detail.

5. **Zero false positives.** All 9 anomalies are genuine operational concerns, appropriately severity-classified. Normal operations (successful requests, expected log patterns) were not flagged.

6. **Context window handled 126K tokens.** The full log dataset was processed in a single prompt without chunking, demonstrating effective large-context analysis.
