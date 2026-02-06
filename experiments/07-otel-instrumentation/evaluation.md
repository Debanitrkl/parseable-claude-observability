# Evaluation: Experiment 07 - OTel Instrumentation Assistance

## Summary

Claude Opus 4.6 was asked to add OpenTelemetry instrumentation to a bare Flask service with traces exported via OTLP/HTTP to Parseable. The response demonstrated strong knowledge of the OTel Python SDK and instrumentation libraries.

**Overall Rating: 4.2 / 5**

## Detailed Evaluation

| Criterion              | Rating    | Score | Notes                                                                                      |
|------------------------|-----------|-------|--------------------------------------------------------------------------------------------|
| Auto-instrumentation   | Correct   | 5/5   | Used both `FlaskInstrumentor` and `RequestsInstrumentor` correctly                         |
| Context propagation    | Correct   | 5/5   | W3C TraceContext automatically propagated via `RequestsInstrumentor` on outgoing HTTP calls |
| Semantic conventions   | Mostly correct | 4/5 | Used `ResourceAttributes` constants; custom attributes used domain-specific naming rather than strict semconv |
| Resource attributes    | Correct   | 5/5   | Set `service.name`, `service.version`, `deployment.environment` via `Resource.create()`    |
| Exporter configuration | Correct   | 5/5   | OTLP/HTTP exporter correctly pointed to `http://parseable:8000/v1/traces`                  |
| Custom span            | Good      | 3/5   | Added `process-payment` span - functional but partially redundant with FlaskInstrumentor   |

## Criterion Details

### Auto-instrumentation (5/5)

Claude correctly identified and applied both relevant auto-instrumentation libraries:

- `FlaskInstrumentor().instrument_app(app)` - creates SERVER spans for all Flask routes
- `RequestsInstrumentor().instrument()` - creates CLIENT spans for all `requests` library calls

This is the idiomatic approach. The instrumentors automatically capture HTTP method, route, status code, and other standard attributes without manual intervention.

### Context Propagation (5/5)

Context propagation was handled correctly through `RequestsInstrumentor`, which automatically injects W3C TraceContext headers (`traceparent`, `tracestate`) into outgoing HTTP requests made via the `requests` library. This ensures the payment service can participate in the same distributed trace.

No manual context injection was needed, and Claude did not attempt to add unnecessary manual propagation code.

### Semantic Conventions (4/5)

Resource attributes used proper OTel semantic convention constants (`ResourceAttributes.SERVICE_NAME`, etc.). The auto-instrumented spans follow semantic conventions automatically (`http.method`, `http.route`, `http.status_code`).

Minor deduction: Custom span attributes used `order.id` and `order.amount` rather than attempting to align with any emerging OTel semantic convention for business transactions. This is acceptable since there are no stable conventions for these, but a brief note about this decision would have been helpful.

### Resource Attributes (5/5)

Correctly configured:
```python
resource = Resource.create({
    ResourceAttributes.SERVICE_NAME: "order-service",
    ResourceAttributes.SERVICE_VERSION: "1.0.0",
    ResourceAttributes.DEPLOYMENT_ENVIRONMENT: "production",
})
```

These attributes are attached to the `TracerProvider` and appear on every span emitted by the service, enabling filtering in Parseable.

### Exporter Configuration (5/5)

The OTLP/HTTP exporter was correctly configured:
```python
exporter = OTLPSpanExporter(
    endpoint="http://parseable:8000/v1/traces"
)
provider.add_span_processor(BatchSpanProcessor(exporter))
```

- Used `OTLPSpanExporter` from `opentelemetry.exporter.otlp.proto.http.trace_exporter` (HTTP, not gRPC)
- Endpoint correctly targets Parseable's OTLP-compatible ingestion path
- Used `BatchSpanProcessor` for production-appropriate batching

### Custom Span (3/5)

The `process-payment` custom span wrapping the payment call is functional and demonstrates manual instrumentation knowledge. However, it is partially redundant:

- `FlaskInstrumentor` already creates a parent SERVER span for `POST /process`
- `RequestsInstrumentor` already creates a CLIENT span for the outgoing `requests.post()` call
- The custom span sits between these two, adding `order.id` and `order.amount` attributes

A more idiomatic approach would be to add these business attributes directly to the current span using `trace.get_current_span().set_attribute(...)` rather than creating an additional span layer. However, the approach taken is not incorrect and does provide a clear business-context span in the trace.

## Parseable-Specific Observations

- Traces sent to Parseable via OTLP/HTTP are queryable using DataFusion SQL
- The `p_timestamp` field is automatically added by Parseable for each ingested trace span
- Resource attributes appear as nested fields (e.g., `resource.service.name`) in the Parseable schema
- Span attributes appear as nested fields (e.g., `attributes.http.method`)
- Trace and span IDs are stored as string fields and can be used for JOIN operations across streams
