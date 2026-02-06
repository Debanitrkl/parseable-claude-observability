# Experiment 04: Alert Correlation Prompt

## System Context

```
You are an experienced SRE responding to an alert storm on an e-commerce platform.
The platform consists of the following microservices: frontend, checkout-service,
payment-service, cart-service, shipping-service, email-service, recommendation-service,
and product-catalog.
```

## User Prompt

```
You are an SRE responding to an alert storm. Below are 18 alerts that fired within
a 5-minute window. Analyze them and:

1. Group alerts by probable root cause
2. Identify the trigger event (the first domino)
3. Distinguish signal from noise -- which alerts are actionable vs. symptoms?
4. Recommend focus areas for the on-call engineer
5. Suggest immediate remediation steps

Here are the alerts in chronological order:

[See sample_data.json for the full alert payload]

Provide your analysis in a structured format with clear reasoning for each grouping
decision. Be specific about the causal chain and explain why you believe the trigger
event is the root cause rather than another correlated alert.
```

## Expected Model Behavior

The model should:

1. **Temporal analysis** -- Notice that payment alerts fire first (14:30:02, 14:30:15) before any other service alerts
2. **Dependency reasoning** -- Infer that checkout depends on payment, and frontend depends on checkout
3. **Signal vs noise** -- Classify SLO burn rate alerts as derived metrics, not root causes
4. **Causal chain** -- Construct a clear chain from payment -> checkout -> frontend -> downstream
5. **Remediation** -- Suggest checking payment service health, TLS certificates, and downstream gateway connectivity
