-- Parseable SQL queries for extracting log analysis data
-- Run these in Parseable's SQL editor (Prism UI)
-- Stream: astronomy-shop-logs (OpenTelemetry demo app)

-- 1. Export recent error and warning logs from checkout service
SELECT *
FROM "astronomy-shop-logs"
WHERE severity_text IN ('ERROR', 'WARN')
  AND "service.name" = 'checkout-service'
  AND p_timestamp > NOW() - INTERVAL '30 minutes'
ORDER BY p_timestamp ASC
LIMIT 200;

-- 2. Export all logs (including debug) from payment service for anomaly detection
SELECT *
FROM "astronomy-shop-logs"
WHERE "service.name" = 'payment-service'
  AND p_timestamp > NOW() - INTERVAL '30 minutes'
ORDER BY p_timestamp ASC
LIMIT 200;

-- 3. Check for timeout patterns
SELECT body, severity_text, "service.name", p_timestamp
FROM "astronomy-shop-logs"
WHERE body LIKE '%timeout%'
  AND "service.name" = 'checkout-service'
  AND p_timestamp > NOW() - INTERVAL '30 minutes'
ORDER BY p_timestamp ASC;

-- 4. Check error frequency over time (1-minute buckets)
SELECT
    DATE_TRUNC('minute', p_timestamp) AS minute_bucket,
    severity_text,
    COUNT(*) AS count
FROM "astronomy-shop-logs"
WHERE "service.name" = 'checkout-service'
  AND p_timestamp > NOW() - INTERVAL '30 minutes'
GROUP BY minute_bucket, severity_text
ORDER BY minute_bucket ASC;

-- 5. Get logs from recommendation service (for OOM detection)
SELECT *
FROM "astronomy-shop-logs"
WHERE "service.name" = 'recommendation-service'
  AND p_timestamp > NOW() - INTERVAL '30 minutes'
ORDER BY p_timestamp ASC;
