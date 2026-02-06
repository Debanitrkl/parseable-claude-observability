# Experiment 06: Trace Analysis

**Type:** Live Experiment
**Model:** Claude Opus 4.6
**Date:** 2025-01-15
**Score:** Pass

## Objective

Evaluate Claude Opus 4.6's ability to reconstruct a distributed trace tree from flat span data, identify the critical path, detect bottlenecks, and produce a plain-English narrative of the request flow.

## Setup

A single distributed trace consisting of **28 spans across 7 services** was extracted from Parseable's `traces` log stream. The spans are presented in a flat JSON array (not pre-structured as a tree), requiring the model to reconstruct the parent-child relationships using `span_id` and `parent_span_id` fields.

## Trace Structure

The trace represents a checkout flow through an e-commerce platform:

```
frontend (POST /checkout) .................. 1847ms
  └─ checkout-service (ProcessCheckout) .... 1790ms
       ├─ cart-service (GetCart) ............ 142ms
       │    └─ product-catalog (GetProducts)  89ms
       ├─ payment-service (ProcessPayment) . 1203ms  [BOTTLENECK]
       │    └─ currency-service (Convert) ...  34ms
       ├─ shipping-service (CalcShipping) .. 287ms   [parallel with payment]
       │    └─ email-service (SendConfirm) . 156ms
       └─ (other child spans)
```

Key characteristics:
- Payment and shipping are called in **parallel** by the checkout service
- Payment is the **bottleneck** (1203ms, with ~1169ms self-time)
- Cart service is called **sequentially** before payment/shipping
- The critical path runs through: frontend -> checkout -> payment

## Results

The model correctly:

1. **Reconstructed the trace tree** -- Built the full parent-child hierarchy from flat spans, correctly identifying root, intermediate, and leaf spans
2. **Identified the critical path** -- frontend -> checkout-service -> payment-service (total 1847ms, dominated by payment's 1203ms)
3. **Found the bottleneck** -- Payment service with ~1169ms self-time (1203ms total minus 34ms for the currency-service child call)
4. **Detected parallelism** -- Correctly identified that payment-service and shipping-service execute in parallel based on overlapping timestamps
5. **Produced a clear narrative** -- Described the checkout flow in plain English with timing breakdowns

## Files

- `prompt.md` -- The trace analysis prompt
- `sample_data.json` -- 28 spans as flat JSON array
- `parseable_queries.sql` -- SQL to extract a specific trace from Parseable
- `evaluation.md` -- Evaluation criteria and scoring
