# Evaluation: Experiment 07 - OTel Instrumentation Assistance

## Experiment Context

Claude was asked to add OpenTelemetry instrumentation to a bare Flask service, with traces exported via OTLP/HTTP to Parseable. The prompt provided a minimal Flask app skeleton and asked for both auto-instrumentation and a custom span.

**Model:** Claude Opus 4.6 (`claude-opus-4-6`)
**Input tokens:** 2,788 | **Output tokens:** 2,704 | **Cost:** $0.24 | **Latency:** 34.8s
**Stop reason:** `end_turn` (completed naturally)

**Overall Rating: 4.5 / 5**

## Detailed Evaluation

| Criterion              | Rating    | Score | Notes                                                                                      |
|------------------------|-----------|-------|--------------------------------------------------------------------------------------------|
| Auto-instrumentation   | Correct   | 5/5   | Used both `FlaskInstrumentor` and `RequestsInstrumentor` correctly                         |
| Context propagation    | Correct   | 5/5   | W3C TraceContext automatically propagated via `RequestsInstrumentor` on outgoing HTTP calls |
| Semantic conventions   | Correct   | 5/5   | Used `ResourceAttributes` constants; custom attributes use domain-specific naming appropriately |
| Resource attributes    | Correct   | 5/5   | Set `service.name`, `service.version`, `deployment.environment` via `Resource.create()`    |
| Exporter configuration | Correct   | 5/5   | OTLP/HTTP exporter correctly pointed to `http://parseable:8000/v1/traces`                  |
| Custom span            | Good      | 3/5   | Added `process-payment` span -- functional but partially redundant with auto-instrumentation |

## Criterion Details

### Auto-instrumentation (5/5)

Claude correctly identified and applied both relevant auto-instrumentation libraries:

- `FlaskInstrumentor().instrument_app(app)` -- creates SERVER spans for all Flask routes
- `RequestsInstrumentor().instrument()` -- creates CLIENT spans for all `requests` library calls

This is the idiomatic approach. The instrumentors automatically capture HTTP method, route, status code, and other standard attributes without manual intervention. Claude also correctly used `instrument_app(app)` (targeting a specific Flask app instance) rather than the global `FlaskInstrumentor().instrument()`, which is safer in multi-app or testing scenarios.

### Context Propagation (5/5)

Context propagation was handled correctly through `RequestsInstrumentor`, which automatically injects W3C TraceContext headers (`traceparent`, `tracestate`) into outgoing HTTP requests made via the `requests` library. The response included a detailed ASCII diagram showing the propagation flow from order-service to payment-service, demonstrating understanding of the end-to-end mechanism.

No manual context injection was needed, and Claude did not attempt to add unnecessary manual propagation code.

### Semantic Conventions (5/5)

Resource attributes used proper OTel semantic convention constants (`ResourceAttributes.SERVICE_NAME`, `ResourceAttributes.SERVICE_VERSION`, `ResourceAttributes.DEPLOYMENT_ENVIRONMENT`). Custom span attributes used reasonable domain-specific naming (`order.id`, `order.amount`, `payment.status_code`). Claude correctly noted that `float(amount)` is needed because OTel attribute values must be one of `str | bool | int | float | Sequence[...]`.

### Resource Attributes (5/5)

Correctly configured with all three recommended resource attributes:
- `service.name`: "order-service"
- `service.version`: "1.0.0"
- `deployment.environment`: "production"

These attributes are attached to the `TracerProvider` and appear on every span emitted by the service.

### Exporter Configuration (5/5)

The OTLP/HTTP exporter was correctly configured:
- Used `OTLPSpanExporter` from `opentelemetry.exporter.otlp.proto.http.trace_exporter` (HTTP, not gRPC)
- Endpoint correctly targets Parseable's OTLP-compatible ingestion path: `http://parseable:8000/v1/traces`
- Used `BatchSpanProcessor` for production-appropriate batching (Claude explicitly noted why `SimpleSpanProcessor` should only be used for debugging)

### Custom Span (3/5)

The `process-payment` custom span wrapping the payment call is functional and demonstrates manual instrumentation knowledge. It adds domain-specific attributes (`order.id`, `order.amount`, `payment.status_code`) that the auto-instrumentors do not capture.

However, it is partially redundant:
- `FlaskInstrumentor` already creates a parent SERVER span for `POST /process`
- `RequestsInstrumentor` already creates a CLIENT span for the outgoing `requests.post()` call
- The custom span sits between these two, adding an extra layer

A more idiomatic approach would be to add business attributes directly to the current span using `trace.get_current_span().set_attribute(...)` rather than creating an additional span layer. However, the approach taken is not incorrect and does provide a clear business-context span in the trace.

## Additional Output Quality

The response went well beyond the minimum requirements:

1. **requirements.txt included** -- lists all 7 required Python packages
2. **Span hierarchy diagram** -- ASCII tree showing the 3-span hierarchy for POST /process
3. **Component breakdown table** -- Explains what each OTel component does
4. **Context propagation diagram** -- ASCII flow showing traceparent header injection/extraction
5. **Sample OTLP JSON output** -- Full example of what the exported trace data looks like
6. **4 key design decisions** -- Explains BatchSpanProcessor choice, instrument_app vs instrument, custom span scoping, and float casting

## Parseable-Specific Observations

- Traces sent to Parseable via OTLP/HTTP are correctly queryable using DataFusion SQL
- The endpoint `http://parseable:8000/v1/traces` matches Parseable's actual OTLP ingestion path
- Resource attributes (`service.name`, etc.) appear as filterable fields in Parseable's schema
