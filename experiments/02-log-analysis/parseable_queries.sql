-- Parseable SQL queries for extracting log analysis data
-- Run these in Parseable's SQL editor (Prism UI)

-- 1. Export recent error and warning logs from checkout service
SELECT *
FROM "checkout"
WHERE level IN ('error', 'warn')
  AND p_timestamp > NOW() - INTERVAL '30 minutes'
ORDER BY p_timestamp ASC
LIMIT 200;

-- 2. Export all logs (including debug) from payment service for anomaly detection
SELECT *
FROM "payment"
WHERE p_timestamp > NOW() - INTERVAL '30 minutes'
ORDER BY p_timestamp ASC
LIMIT 200;

-- 3. Check for timeout patterns
SELECT message, level, service_name, p_timestamp
FROM "checkout"
WHERE message LIKE '%timeout%'
  AND p_timestamp > NOW() - INTERVAL '30 minutes'
ORDER BY p_timestamp ASC;

-- 4. Check error frequency over time (1-minute buckets)
SELECT
    DATE_TRUNC('minute', p_timestamp) AS minute_bucket,
    level,
    COUNT(*) AS count
FROM "checkout"
WHERE p_timestamp > NOW() - INTERVAL '30 minutes'
GROUP BY minute_bucket, level
ORDER BY minute_bucket ASC;

-- 5. Get logs from recommendation service (for OOM detection)
SELECT *
FROM "recommendation"
WHERE p_timestamp > NOW() - INTERVAL '30 minutes'
ORDER BY p_timestamp ASC;
