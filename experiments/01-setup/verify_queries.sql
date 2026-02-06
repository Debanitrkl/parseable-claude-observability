-- Verification queries for Parseable + OTel Demo setup
-- Run these in Parseable's SQL editor (Prism UI) to confirm data is flowing

-- 1. Count total records in the logs stream
SELECT COUNT(*) AS total_records
FROM "otel-logs";

-- 2. Check which services are sending logs
SELECT service_name, COUNT(*) AS log_count
FROM "otel-logs"
GROUP BY service_name
ORDER BY log_count DESC;

-- 3. Verify p_timestamp is present and recent
SELECT MIN(p_timestamp) AS earliest,
       MAX(p_timestamp) AS latest,
       COUNT(*) AS total
FROM "otel-logs"
WHERE p_timestamp > NOW() - INTERVAL '1 hour';

-- 4. Check trace data is flowing
SELECT COUNT(*) AS total_spans
FROM "traces";

-- 5. List unique trace services
SELECT service_name, COUNT(*) AS span_count
FROM "traces"
GROUP BY service_name
ORDER BY span_count DESC;

-- 6. Verify log levels are being captured
SELECT level, COUNT(*) AS count
FROM "otel-logs"
GROUP BY level
ORDER BY count DESC;

-- 7. Sample recent error logs
SELECT service_name, level, message, p_timestamp
FROM "otel-logs"
WHERE level = 'error'
ORDER BY p_timestamp DESC
LIMIT 10;
