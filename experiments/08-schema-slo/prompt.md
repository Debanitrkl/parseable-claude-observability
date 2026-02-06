# Prompt: Log Stream Schema Design and SLO/SLI Framework

## System Context

You are an expert in observability engineering, structured logging, and SRE practices.

## Prompt

Design a structured logging schema for a Go-based payment service. The logs will be ingested into a Parseable log stream. Then design an SLO/SLI framework with SQL queries for monitoring.

**Schema Requirements:**
- The payment service handles charge, refund, and payout operations
- Include distributed tracing fields (trace_id, span_id) for correlation with traces
- Include a correlation_id for business-level request tracking
- PII fields (customer email, card number) must be hashed (SHA-256) before emission
- Flatten nested structures for better DataFusion query performance in Parseable
- Consider Parseable's static schema mode for enforcing field types

**SLO Requirements:**
- Availability SLO: 99.95% of payment requests return a non-error response
- Latency SLO: 99th percentile latency under 500ms for charge operations
- Error budget burn rate alerting with multi-window approach

**Parseable Context:**
- Parseable supports both dynamic and static schema modes for log streams
- In static schema mode, the schema is defined at stream creation time and enforced on ingestion
- `p_timestamp` is automatically added by Parseable to every log event
- `p_tags` and `p_metadata` are reserved field prefixes
- DataFusion SQL is used for querying (supports `APPROX_PERCENTILE_CONT`, `COUNT(*) FILTER`, `INTERVAL`)

**Output:**
1. The JSON schema definition suitable for Parseable static schema mode
2. Example log events for each operation type
3. SLO/SLI definitions with monitoring SQL queries
4. Guidance on burn rate alerting windows
