# Evaluation: Experiment 08 - Schema + SLO Design

## Experiment Context

Claude was asked to design a structured logging schema for a Go payment service suitable for Parseable ingestion (using static schema mode), along with an SLO/SLI monitoring framework using DataFusion SQL. The response included a full JSON schema definition, a Go implementation with PII handling, and schema design rationale.

**Model:** Claude Opus 4.6 (`claude-opus-4-6`)
**Input tokens:** 2,873 | **Output tokens:** 4,096 | **Cost:** $0.35 | **Latency:** 60.0s
**Stop reason:** `max_tokens` (response was truncated at 4096 tokens)

**Note:** The response hit the max_tokens limit and was truncated partway through the Go implementation's example usage function. The schema definition, design rationale, and Go struct/helper functions were all complete before truncation. The SLO/SLI framework with DataFusion SQL queries was likely planned but not rendered due to the token limit.

**Overall Rating: 4.5 / 5**

## Detailed Evaluation

| Criterion              | Rating         | Score | Notes                                                                                   |
|------------------------|----------------|-------|-----------------------------------------------------------------------------------------|
| Schema design          | Excellent      | 5/5   | 24-field flat schema with trace context, correlation_id, appropriate types, metadata     |
| PII handling           | Excellent      | 5/5   | SHA-256 hashed customer_id, card_last_four truncation, explicit app-layer hashing in Go  |
| Parseable compatibility| Excellent      | 5/5   | Static schema mode via `X-P-Static-Schema-Flag`, correct Arrow types, p_timestamp awareness |
| Go implementation      | Good           | 4/5   | Complete struct + helpers (HashPII, MaskCardNumber, Emit), truncated before SLO queries  |
| Design rationale       | Excellent      | 5/5   | Detailed rationale for flat structure, static schema, PII handling, nullable strategy    |

## Criterion Details

### Schema Design (5/5)

The schema demonstrates production-quality observability design with 24 fields organized into logical groups:

**Envelope (6 fields):** `timestamp`, `level`, `service`, `version`, `environment`, `host` -- all non-nullable, covering the minimum viable context for any log event.

**Distributed Tracing (3 fields):** `trace_id` (32 hex chars), `span_id` (16 hex chars), `correlation_id` (business-level, survives async boundaries). The inclusion of `correlation_id` is a sophisticated design choice -- it provides continuity across message queues and retry boundaries where trace context may break.

**Business Context (5 fields):** `operation` (charge/refund/payout), `status` (success/failure/timeout/invalid), `duration_ms` (Float64), `amount_cents` (Int64 to avoid floating-point currency issues), `currency` (ISO 4217).

**Customer PII-safe (3 fields):** `customer_id_hash` (SHA-256), `card_last_four` (nullable), `card_brand` (nullable).

**Gateway (4 fields):** `gateway`, `gateway_response_code` (nullable -- null on timeout), `error_code` (nullable -- null on success), `error_message` (nullable, sanitized of PII).

**Observability (3 fields):** `idempotency_key`, `retry_count` (Int32, 0 = first attempt), `message`.

### PII Handling (5/5)

Previous evaluation deducted a point for not noting that hashing must happen at the app layer. The actual response explicitly addresses this:

- `customer_id_hash`: SHA-256 computed in Go before serialization. The `HashPII()` function normalizes input (lowercase, trim whitespace) before hashing for consistency.
- `card_last_four`: The `MaskCardNumber()` function extracts only the last 4 digits, handling both `4242424242424242` and `4242-4242-4242-4242` formats. Returns nil for empty input (payout operations).
- Schema metadata explicitly states: "SHA-256 pre-hashed at application layer" and "PCI-DSS compliant: only the last four digits are emitted."
- The design rationale box notes: "hashing 4 digits is trivially reversible (only 10,000 possibilities)" -- correctly explaining why card_last_four is truncated rather than hashed.

### Parseable Compatibility (5/5)

The response demonstrates strong Parseable-specific knowledge:

- **Static schema mode:** Correctly uses `X-P-Static-Schema-Flag: true` header at stream creation time.
- **Arrow type mapping:** All `data_type` values map to valid Arrow types: `Utf8`, `Float64`, `Int64`, `Int32`.
- **`p_timestamp` awareness:** Design rationale explicitly distinguishes between application `timestamp` (when event occurred) and Parseable's `p_timestamp` (when ingested), recommending `timestamp` for SLI queries.
- **Flat structure rationale:** Correctly explains that Parseable uses DataFusion (Arrow-backed columnar engine) where nested JSON requires runtime flattening, while flat fields map directly to Arrow columns with native predicate pushdown.
- **Stream creation API:** Uses the correct `PUT /api/v1/logstream/{stream-name}` endpoint.

### Go Implementation (4/5)

The Go code is well-structured:

- `PaymentLogEvent` struct with JSON tags matching the schema exactly
- Type-safe enums for `Level`, `Operation`, and `Status`
- `HashPII()` function with normalization (lowercase + trim)
- `MaskCardNumber()` function handling multiple card number formats
- `Emit()` function with JSON marshaling and stderr fallback on error
- Nullable fields correctly use `*string` pointers (nil = JSON null)

Deduction: The response was truncated before the example usage function and the SLO/SLI framework section (DataFusion SQL queries for availability and latency SLOs). With a higher max_tokens setting, this section would likely have been complete.

### Design Rationale (5/5)

The ASCII-art design decisions box covers 5 key architectural choices:

1. **Flat structure** -- DataFusion/Arrow performance rationale with concrete avoid/use examples
2. **Static schema mode** -- Type safety at ingestion (malformed data rejected, not silently ingested)
3. **PII handling** -- App-layer hashing with explanation of why card_last_four is truncated not hashed
4. **timestamp vs p_timestamp** -- When to use each for SLI accuracy vs. ingestion lag monitoring
5. **Nullable strategy** -- Only legitimately absent fields are nullable; all identity/context fields are NOT NULL

## Truncation Impact

The response was truncated at 4,096 output tokens. The Go implementation's `ExampleChargeSuccess()` function was cut mid-field. The SLO/SLI framework section (DataFusion SQL queries for burn rate alerting, availability and latency calculations) was not rendered.

Despite the truncation, the completed portions -- the full 24-field schema definition, design rationale, and Go implementation (struct + 3 helper functions) -- represent the most valuable and difficult-to-produce parts of the response. The SLO queries follow naturally from the schema design and could be generated in a follow-up prompt. A max_tokens setting of 8192 would have captured the full response.

## Parseable-Specific Observations

- The flat schema design is optimized for DataFusion columnar performance in Parseable
- Static schema mode prevents schema drift, protecting SLO query reliability
- The `correlation_id` field enables cross-stream joins in Parseable across multiple log streams
- `retry_count` field enables distinguishing organic failures from retry storms in SLI calculations
