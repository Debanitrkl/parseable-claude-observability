# Experiment 05: Incident RCA Prompt

## System Context

```
You are a senior SRE performing root cause analysis on a production incident.
You have access to logs, traces, and metrics from the affected time window.
Provide a structured RCA with root cause, failure chain, remediation, and
prevention recommendations.
```

## User Prompt

```
Perform root cause analysis on the following production incident. Data has been
exported from Parseable log streams.

## Symptoms

- Checkout success rate dropped from 99.2% to 61.3% starting at 14:25 UTC
- Customer-facing error: "Payment processing failed, please try again"
- PagerDuty incident opened at 14:28 UTC after SLO burn rate alert fired
- No recent deployments (last deploy was 6 hours ago to payment-service)

## Log Excerpts (from Parseable application-logs stream)

14:25:01 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=4213ms trace_id=abc001
14:25:01 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=847
14:25:02 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=3891ms trace_id=abc002
14:25:03 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc001
14:25:03 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc002
14:25:04 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=5102ms trace_id=abc003
14:25:04 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=1203
14:25:05 [checkout-service] WARN   Payment retry 1/3 failed for order ord_98234 trace_id=abc003
14:25:06 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=4567ms trace_id=abc004
14:25:07 [checkout-service] ERROR  Payment retry 2/3 failed for order ord_98234 trace_id=abc003
14:25:08 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=1589
14:25:09 [checkout-service] ERROR  Payment retry 3/3 failed for order ord_98234 trace_id=abc003
14:25:09 [checkout-service] ERROR  Order ord_98234 failed: payment processing exhausted retries
14:25:10 [frontend] ERROR  Checkout failed for user usr_44521: "Payment processing failed" trace_id=abc003
14:25:11 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=3756ms trace_id=abc005
14:25:12 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=1923
14:25:13 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=4891ms trace_id=abc006
14:25:14 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc005
14:25:14 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc006
14:25:15 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=2341
14:25:16 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=5234ms trace_id=abc007
14:25:17 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=4102ms trace_id=abc008
14:25:18 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc007
14:25:18 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc008
14:25:19 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=2756
14:25:20 [frontend] ERROR  Checkout failed for user usr_44589: "Payment processing failed" trace_id=abc007
14:25:21 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=3945ms trace_id=abc009
14:25:22 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=3102
14:25:23 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc009
14:25:24 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=4678ms trace_id=abc010
14:25:25 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=3489
14:25:26 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc010
14:25:27 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=5012ms trace_id=abc011
14:25:28 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=3891
14:25:29 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc011
14:25:30 [frontend] ERROR  Checkout failed for user usr_44601: "Payment processing failed" trace_id=abc011
14:25:31 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=4345ms trace_id=abc012
14:25:32 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=4234
14:25:33 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc012
14:25:34 [payment-service] ERROR  gRPC deadline exceeded calling payment-gateway timeout=2000ms actual=4890ms trace_id=abc013
14:25:35 [payment-service] WARN   Request processing slow, CPU pressure detected pid=1 cpu_throttle_count=4601
14:25:36 [checkout-service] ERROR  PaymentService.ProcessPayment failed: DeadlineExceeded trace_id=abc013
14:25:37 [frontend] ERROR  Checkout failed for user usr_44623: "Payment processing failed" trace_id=abc013

## Trace Samples (from Parseable traces stream)

Trace 1 (abc001):
  frontend POST /checkout          1847ms  OK->ERROR (502)
  └─ checkout ProcessCheckout      1790ms  ERROR
     └─ payment ProcessPayment     4213ms  ERROR (DeadlineExceeded)

Trace 2 (abc003):
  frontend POST /checkout          15234ms OK->ERROR (504)
  └─ checkout ProcessCheckout      15180ms ERROR
     ├─ payment ProcessPayment     5102ms  ERROR (DeadlineExceeded) [retry 1]
     ├─ payment ProcessPayment     4567ms  ERROR (DeadlineExceeded) [retry 2]
     └─ payment ProcessPayment     5012ms  ERROR (DeadlineExceeded) [retry 3]

Trace 3 (abc005):
  frontend POST /checkout          1623ms  OK->ERROR (502)
  └─ checkout ProcessCheckout      1580ms  ERROR
     └─ payment ProcessPayment     3756ms  ERROR (DeadlineExceeded)

## Metric Snapshots (from Parseable k8s-metrics stream)

Payment service resource utilization:
  CPU usage:     199m / 200m limit  (99.5% of limit)
  CPU request:   100m
  Memory usage:  256Mi / 512Mi limit (50%)
  Replicas:      3/3 running

  CFS throttle periods:  4601 (in last 5 minutes)
  CFS throttled time:    187.3 seconds (in last 5 minutes)

Payment service latency distribution (last 5 min vs previous hour):
  Metric          Last 5 min    Previous hour
  p50 latency     3891ms        187ms
  p95 latency     4890ms        312ms
  p99 latency     5234ms        456ms
  Error rate      38.7%         0.3%

Checkout service:
  CPU usage:     450m / 2000m limit (22.5%)
  Memory usage:  1.2Gi / 4Gi limit (30%)
  Success rate:  61.3% (was 99.2%)

Kubernetes deployment history:
  Last deploy: 6 hours ago (payment-service v2.14.3)
  Change: "Update payment gateway TLS certificates"
  Deployment diff includes: resources.limits.cpu changed from 2000m to 200m

Provide:
1. Root cause identification with confidence level
2. Complete failure chain (step by step)
3. Immediate remediation steps
4. Long-term prevention measures
```
