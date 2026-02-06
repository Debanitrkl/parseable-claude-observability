-- Experiment 08: Schema + SLO Design - Parseable Monitoring Queries
-- All queries use DataFusion SQL syntax compatible with Parseable.

-- =============================================================================
-- STREAM CREATION
-- =============================================================================

-- Create the payment log stream via Parseable API (curl command)
-- Uses static schema mode to enforce field types at ingestion time.
--
-- curl -X PUT "http://parseable:8000/api/v1/logstream/payment_logs" \
--   -H "Authorization: Basic <base64-credentials>" \
--   -H "Content-Type: application/json" \
--   -H "X-P-Static-Schema-Flag: true" \
--   -d '{
--     "fields": [
--       {"name": "timestamp", "data_type": "Utf8"},
--       {"name": "level", "data_type": "Utf8"},
--       {"name": "service", "data_type": "Utf8"},
--       {"name": "version", "data_type": "Utf8"},
--       {"name": "environment", "data_type": "Utf8"},
--       {"name": "host", "data_type": "Utf8"},
--       {"name": "trace_id", "data_type": "Utf8"},
--       {"name": "span_id", "data_type": "Utf8"},
--       {"name": "correlation_id", "data_type": "Utf8"},
--       {"name": "operation", "data_type": "Utf8"},
--       {"name": "status", "data_type": "Utf8"},
--       {"name": "duration_ms", "data_type": "Float64"},
--       {"name": "amount_cents", "data_type": "Int64"},
--       {"name": "currency", "data_type": "Utf8"},
--       {"name": "customer_id_hash", "data_type": "Utf8"},
--       {"name": "card_last_four", "data_type": "Utf8"},
--       {"name": "card_brand", "data_type": "Utf8"},
--       {"name": "gateway", "data_type": "Utf8"},
--       {"name": "gateway_response_code", "data_type": "Utf8"},
--       {"name": "error_code", "data_type": "Utf8"},
--       {"name": "error_message", "data_type": "Utf8"},
--       {"name": "idempotency_key", "data_type": "Utf8"},
--       {"name": "message", "data_type": "Utf8"}
--     ]
--   }'

-- =============================================================================
-- SLI: AVAILABILITY
-- =============================================================================

-- 2. Availability SLI - 30-day rolling window
--    Target: 99.95% of payment requests return non-error response
--    "success" and "invalid" are counted as good (invalid = client error, not service error)
SELECT
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE status IN ('success', 'invalid')) AS good_requests,
    COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS bad_requests,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE status IN ('success', 'invalid')) AS FLOAT)
        / CAST(COUNT(*) AS FLOAT) * 100, 4
    ) AS availability_pct,
    CASE
        WHEN CAST(COUNT(*) FILTER (WHERE status IN ('success', 'invalid')) AS FLOAT)
             / CAST(COUNT(*) AS FLOAT) >= 0.9995
        THEN 'WITHIN_BUDGET'
        ELSE 'BUDGET_EXCEEDED'
    END AS slo_status
FROM
    payment_logs
WHERE
    operation IN ('charge', 'refund', 'payout')
    AND p_timestamp > NOW() - INTERVAL '30 days';

-- 3. Availability SLI - hourly breakdown for dashboarding
SELECT
    DATE_TRUNC('hour', p_timestamp) AS hour,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE status IN ('success', 'invalid')) AS good_requests,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE status IN ('success', 'invalid')) AS FLOAT)
        / CAST(COUNT(*) AS FLOAT) * 100, 4
    ) AS availability_pct
FROM
    payment_logs
WHERE
    operation IN ('charge', 'refund', 'payout')
    AND p_timestamp > NOW() - INTERVAL '7 days'
GROUP BY
    DATE_TRUNC('hour', p_timestamp)
ORDER BY
    hour DESC;

-- =============================================================================
-- SLI: LATENCY
-- =============================================================================

-- 4. Latency SLI - p99 for charge operations
--    Target: 99th percentile under 500ms
SELECT
    COUNT(*) AS total_charges,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.50), 2) AS p50_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.90), 2) AS p90_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.95), 2) AS p95_ms,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.99), 2) AS p99_ms,
    CASE
        WHEN APPROX_PERCENTILE_CONT(duration_ms, 0.99) <= 500
        THEN 'WITHIN_SLO'
        ELSE 'SLO_BREACHED'
    END AS latency_slo_status
FROM
    payment_logs
WHERE
    operation = 'charge'
    AND status = 'success'
    AND p_timestamp > NOW() - INTERVAL '30 days';

-- 5. Latency SLI - hourly p99 trend for charge operations
SELECT
    DATE_TRUNC('hour', p_timestamp) AS hour,
    COUNT(*) AS charge_count,
    ROUND(APPROX_PERCENTILE_CONT(duration_ms, 0.99), 2) AS p99_ms
FROM
    payment_logs
WHERE
    operation = 'charge'
    AND status = 'success'
    AND p_timestamp > NOW() - INTERVAL '7 days'
GROUP BY
    DATE_TRUNC('hour', p_timestamp)
ORDER BY
    hour DESC;

-- =============================================================================
-- ERROR BUDGET BURN RATE
-- =============================================================================

-- 6. Error budget burn rate - multi-window alerting
--    Uses Google SRE multi-window, multi-burn-rate approach:
--      Fast burn: 14.4x budget consumption rate over 1-hour window
--      Slow burn: 6x budget consumption rate over 6-hour window
--
--    For 99.95% SLO, error budget = 0.05% of requests can fail
--    Fast burn threshold: error_rate > 0.05% * 14.4 = 0.72% over 1 hour
--    Slow burn threshold: error_rate > 0.05% * 6 = 0.30% over 6 hours

-- Fast burn (1-hour window, 14.4x threshold)
SELECT
    'fast_burn_1h' AS alert_window,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS error_count,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS FLOAT)
        / CAST(COUNT(*) AS FLOAT) * 100, 4
    ) AS error_rate_pct,
    CASE
        WHEN CAST(COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS FLOAT)
             / CAST(COUNT(*) AS FLOAT) * 100 > 0.72
        THEN 'ALERT_FIRING'
        ELSE 'OK'
    END AS alert_status
FROM
    payment_logs
WHERE
    operation IN ('charge', 'refund', 'payout')
    AND p_timestamp > NOW() - INTERVAL '1 hour';

-- Fast burn (5-minute confirmation window)
SELECT
    'fast_burn_5m' AS alert_window,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS error_count,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS FLOAT)
        / CAST(COUNT(*) AS FLOAT) * 100, 4
    ) AS error_rate_pct,
    CASE
        WHEN CAST(COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS FLOAT)
             / CAST(COUNT(*) AS FLOAT) * 100 > 0.72
        THEN 'ALERT_CONFIRMED'
        ELSE 'OK'
    END AS alert_status
FROM
    payment_logs
WHERE
    operation IN ('charge', 'refund', 'payout')
    AND p_timestamp > NOW() - INTERVAL '5 minutes';

-- Slow burn (6-hour window, 6x threshold)
SELECT
    'slow_burn_6h' AS alert_window,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS error_count,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS FLOAT)
        / CAST(COUNT(*) AS FLOAT) * 100, 4
    ) AS error_rate_pct,
    CASE
        WHEN CAST(COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS FLOAT)
             / CAST(COUNT(*) AS FLOAT) * 100 > 0.30
        THEN 'ALERT_FIRING'
        ELSE 'OK'
    END AS alert_status
FROM
    payment_logs
WHERE
    operation IN ('charge', 'refund', 'payout')
    AND p_timestamp > NOW() - INTERVAL '6 hours';

-- Slow burn (30-minute confirmation window)
SELECT
    'slow_burn_30m' AS alert_window,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS error_count,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS FLOAT)
        / CAST(COUNT(*) AS FLOAT) * 100, 4
    ) AS error_rate_pct,
    CASE
        WHEN CAST(COUNT(*) FILTER (WHERE status IN ('failure', 'timeout')) AS FLOAT)
             / CAST(COUNT(*) AS FLOAT) * 100 > 0.30
        THEN 'ALERT_CONFIRMED'
        ELSE 'OK'
    END AS alert_status
FROM
    payment_logs
WHERE
    operation IN ('charge', 'refund', 'payout')
    AND p_timestamp > NOW() - INTERVAL '30 minutes';

-- =============================================================================
-- OPERATIONAL QUERIES
-- =============================================================================

-- 7. Error breakdown by type and gateway
SELECT
    gateway,
    error_code,
    COUNT(*) AS error_count,
    ROUND(AVG(duration_ms), 2) AS avg_duration_ms
FROM
    payment_logs
WHERE
    status IN ('failure', 'timeout')
    AND p_timestamp > NOW() - INTERVAL '1 hour'
GROUP BY
    gateway, error_code
ORDER BY
    error_count DESC;

-- 8. Correlate logs with traces - find all logs for a specific trace
SELECT
    p_timestamp,
    level,
    operation,
    status,
    duration_ms,
    error_code,
    error_message,
    span_id,
    message
FROM
    payment_logs
WHERE
    trace_id = '4bf92f3577b34da6a3ce929d0e0e4736'
ORDER BY
    p_timestamp ASC;

-- 9. High-value transaction monitoring
SELECT
    p_timestamp,
    operation,
    status,
    amount_cents,
    currency,
    duration_ms,
    gateway,
    correlation_id,
    trace_id
FROM
    payment_logs
WHERE
    amount_cents > 100000
    AND p_timestamp > NOW() - INTERVAL '24 hours'
ORDER BY
    amount_cents DESC
LIMIT 50;

-- 10. Timeout pattern detection - identify gateway degradation
SELECT
    gateway,
    DATE_TRUNC('minute', p_timestamp) AS minute,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE status = 'timeout') AS timeout_count,
    ROUND(
        CAST(COUNT(*) FILTER (WHERE status = 'timeout') AS FLOAT)
        / CAST(COUNT(*) AS FLOAT) * 100, 2
    ) AS timeout_rate_pct
FROM
    payment_logs
WHERE
    operation = 'charge'
    AND p_timestamp > NOW() - INTERVAL '1 hour'
GROUP BY
    gateway, DATE_TRUNC('minute', p_timestamp)
HAVING
    COUNT(*) FILTER (WHERE status = 'timeout') > 0
ORDER BY
    minute DESC, timeout_rate_pct DESC;
