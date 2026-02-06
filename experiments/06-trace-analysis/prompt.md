# Experiment 06: Trace Analysis Prompt

## System Context

```
You are a distributed systems expert analyzing trace data from a microservices
application. The trace data is stored in Parseable's "traces" log stream and has
been extracted as flat span records. Each span has a span_id and parent_span_id
that you must use to reconstruct the call tree.
```

## User Prompt

```
Below are 28 spans from a single distributed trace (trace_id: "trace_checkout_7f3a")
across 7 services. The spans are provided as a flat array -- they are NOT pre-structured
as a tree.

Analyze this trace and provide:

1. **Service call tree reconstruction** -- Rebuild the full parent-child hierarchy
   from the flat spans. Present it as an indented tree showing service name,
   operation, and duration.

2. **Critical path identification** -- Identify the longest path from root span
   to leaf span that determines the overall trace duration. Show each span on
   the critical path with its contribution.

3. **Bottleneck detection** -- Find the span with the highest self-time (total
   duration minus time spent in child spans). Explain why this is the bottleneck.

4. **Anomalous span detection** -- Flag any spans that seem unusual (e.g.,
   unexpectedly slow for their operation type, error status, or retry patterns).

5. **Plain-English narrative** -- Write a 3-5 sentence description of what
   happened in this request, suitable for a non-technical incident report.

[See sample_data.json for the full span payload]
```
