# Evaluation: Experiment 08 - Schema + SLO Design

## Summary

Claude Opus 4.6 was asked to design a structured logging schema for a Go payment service suitable for Parseable ingestion, along with an SLO/SLI monitoring framework using DataFusion SQL. The response showed strong understanding of both observability schema design and SRE practices.

**Overall Rating: 4.4 / 5**

## Detailed Evaluation

| Criterion              | Rating         | Score | Notes                                                                                   |
|------------------------|----------------|-------|-----------------------------------------------------------------------------------------|
| Schema design          | Excellent      | 5/5   | Includes trace context, correlation_id, flattened fields, appropriate types              |
| PII handling           | Correct        | 4/5   | Hashed customer_id, kept card_last_four; could note hashing must happen at app layer     |
| Parseable compatibility| Good           | 4/5   | Aware of static schema mode and p_timestamp; could mention p_tags for filtering          |
| SLO/SLI framework      | Excellent      | 5/5   | Multi-window burn rate alerting, correct budget calculations                             |
| Monitoring queries     | Mostly correct | 4/5   | Valid DataFusion SQL; minor improvements possible in window alignment                    |

## Criterion Details

### Schema Design (5/5)

The schema demonstrates excellent observability-first design:

**Trace context inclusion:** Both `trace_id` and `span_id` fields are present, enabling direct correlation between structured logs in Parseable and distributed traces (whether stored in Parseable via OTLP or in another trace backend). This is critical for the log-to-trace pivot workflow.

**Correlation ID:** The `correlation_id` field provides business-level request tracking independent of distributed tracing. This allows correlating events across services even when trace context is lost (e.g., through message queues).

**Flattened fields:** All fields are top-level rather than nested (e.g., `gateway_response_code` instead of `gateway.response.code`). This is important for DataFusion performance in Parseable, as nested JSON requires more complex query syntax and may not benefit from columnar storage optimizations.

**Type choices:** Using `duration_ms` as a float and `amount_cents` as an integer avoids floating-point precision issues with currency while keeping duration granular. The `status` enum is well-scoped to operation outcomes rather than HTTP status codes.

### PII Handling (4/5)

The schema correctly addresses PII:

- `customer_id_hash` uses SHA-256 hashing of the customer email, making it non-reversible while still allowing grouping queries (all events for the same customer hash together)
- `card_last_four` retains only the last four digits, which is PCI DSS compliant for logging
- Full card numbers never appear in the schema

Minor deduction: The response could have explicitly noted that hashing must occur at the application layer (in the Go service) before log emission, not at the Parseable ingestion layer. Parseable does not perform field-level transformations during ingestion.

### Parseable Compatibility (4/5)

Good awareness of Parseable-specific features:

- **Static schema mode:** Correctly referenced using `X-P-Static-Schema-Flag` header at stream creation time. The schema definition uses Parseable's expected format with `data_type` fields mapping to Arrow types (Utf8, Float64, Int64).
- **p_timestamp:** Correctly noted that Parseable automatically adds `p_timestamp` to every ingested event. The schema does not duplicate this - the application-level `timestamp` field serves as the event timestamp while `p_timestamp` is the ingestion timestamp.
- **DataFusion types:** Field types map correctly to DataFusion/Arrow types.

Minor deduction: Could have mentioned `p_tags` as a mechanism for adding filterable metadata to log events without schema changes, and `p_metadata` for attaching custom metadata at ingestion time via HTTP headers.

### SLO/SLI Framework (5/5)

The SLO design follows Google SRE best practices:

**Availability SLO (99.95%):**
- SLI correctly counts `success` and `invalid` as good events (client validation errors are not service failures)
- Error budget calculated correctly: 0.05% of ~43,200 minutes/month = ~21.6 minutes of allowed downtime

**Latency SLO:**
- Uses p99 percentile, which is appropriate for payment operations where tail latency impacts user experience
- Target of 500ms is reasonable for a payment charge operation
- Correctly scoped to `charge` operations only, not all operation types

**Multi-window burn rate alerting:**
- Implements the Google SRE multi-window approach correctly:
  - Fast burn: 14.4x rate over 1-hour window with 5-minute confirmation
  - Slow burn: 6x rate over 6-hour window with 30-minute confirmation
- Budget consumption thresholds correctly calculated from the 0.05% error budget

### Monitoring Queries (4/5)

The DataFusion SQL queries are syntactically correct and operationally useful:

- `COUNT(*) FILTER (WHERE ...)` is valid PostgreSQL-compatible SQL for conditional aggregation
- `APPROX_PERCENTILE_CONT` is the correct DataFusion function for approximate percentiles
- `DATE_TRUNC` and `INTERVAL` usage is correct
- `ROUND` and `CAST` are used appropriately for percentage calculations

Minor deduction: The burn rate queries use `NOW() - INTERVAL '1 hour'` which creates a sliding window. For strict SLO compliance, fixed calendar-aligned windows (e.g., aligned to the start of each hour) might be preferable for some use cases. However, sliding windows are standard practice for burn rate alerting.

## Parseable-Specific Observations

- The `p_timestamp` field added by Parseable serves as the ingestion timestamp and is used in all `WHERE` clauses for time-range filtering. This is distinct from the application `timestamp` field.
- Static schema mode prevents schema drift, which is particularly important for SLO queries that depend on consistent field names and types.
- The flattened schema design avoids the need for JSON path extraction in queries, which improves DataFusion query performance.
- For high-cardinality fields like `trace_id` and `correlation_id`, Parseable's columnar storage (Parquet-based) provides efficient string matching without requiring secondary indexes.
