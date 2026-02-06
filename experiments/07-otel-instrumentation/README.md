# Experiment 07: OTel Instrumentation Assistance

**Type:** Live Experiment
**Model:** Claude Opus 4.6

## Overview

This experiment evaluates Claude's ability to add OpenTelemetry instrumentation to an existing Flask service. The instrumented service sends traces via OTLP/HTTP to a Parseable instance acting as the trace backend.

## Setup

- **Input:** A bare Flask service with two endpoints (`/health` and `/process`) where `/process` makes an outgoing HTTP call.
- **Backend:** Parseable running on `parseable:8000` receiving traces at `/v1/traces`.
- **Exporter:** OTLP HTTP exporter configured to point to Parseable.

## Evaluation Criteria

| Criterion              | Weight | Description                                                  |
|------------------------|--------|--------------------------------------------------------------|
| Auto-instrumentation   | 20%    | Correct use of FlaskInstrumentor and RequestsInstrumentor    |
| Context propagation    | 25%    | W3C TraceContext propagated on outgoing HTTP calls           |
| Semantic conventions   | 20%    | Span names and attributes follow OTel semantic conventions   |
| Resource attributes    | 15%    | Service name, version, environment set on TracerProvider     |
| Exporter configuration | 20%    | OTLP/HTTP exporter correctly targeting Parseable endpoint    |

## Files

- `prompt.md` - The prompt given to Claude with the bare Flask service code
- `sample_data.json` - Input service code and expected instrumented output
- `parseable_queries.sql` - SQL queries to verify traces in Parseable
- `evaluation.md` - Detailed evaluation of Claude's response
