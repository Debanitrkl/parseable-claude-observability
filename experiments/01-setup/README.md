# Experiment 01: Setup and Verification

## Overview

This experiment verifies that the Parseable + OTel Demo stack is running correctly and that telemetry data is flowing into Parseable log streams.

## Steps

### 1. Start Parseable

```bash
docker run -p 8000:8000 \
  parseable/parseable:latest \
  parseable local-store
```

### 2. Start the OTel Demo

```bash
git clone https://github.com/open-telemetry/opentelemetry-demo.git
cd opentelemetry-demo
docker compose up -d
```

### 3. Configure OTel Collector

Update the collector config to export to Parseable. See `../../config/otel-collector-config.yaml` for the full configuration.

### 4. Verify Data Flow

```bash
# Check Parseable is running
curl -s http://localhost:8000/api/v1/liveness

# List log streams (should show streams after OTel Demo sends data)
curl -s http://localhost:8000/api/v1/logstream \
  -u parseable:parseable | jq .

# Check a specific log stream has data
curl -s "http://localhost:8000/api/v1/query" \
  -u parseable:parseable \
  -H "Content-Type: application/json" \
  -d '{
    "query": "SELECT COUNT(*) as total FROM \"otel-logs\"",
    "startTime": "now-1h",
    "endTime": "now"
  }' | jq .
```

### 5. Open Prism UI

Navigate to `http://localhost:8000` in your browser.

- Default username: `parseable`
- Default password: `parseable`

You should see log streams in the left sidebar. Click on any stream to explore the data.

## Verification Checklist

- [ ] Parseable responds on port 8000
- [ ] OTel Demo services are running (check with `docker compose ps`)
- [ ] At least one log stream appears in Parseable
- [ ] SQL queries return data in the Prism UI SQL editor
- [ ] `p_timestamp` field is present on ingested records

## Troubleshooting

**No log streams appearing:**
- Verify the OTel Collector config has the Parseable exporter
- Check collector logs: `docker compose logs otelcol`
- Ensure `host.docker.internal` resolves (or use the Parseable container's IP)

**Authentication errors:**
- Default credentials are `parseable` / `parseable`
- The Base64-encoded auth header is: `cGFyc2VhYmxlOnBhcnNlYWJsZQ==`

**Port conflicts:**
- Parseable uses port 8000 by default
- The OTel Demo uses various ports (check their `docker-compose.yaml`)
