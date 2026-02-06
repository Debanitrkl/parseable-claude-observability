#!/usr/bin/env bash
#
# Verify that the Parseable + OTel Demo environment is running correctly.
#
# Checks:
#   1. Parseable is reachable (liveness endpoint)
#   2. Log streams exist
#   3. Data is flowing (record counts > 0)
#   4. OTel Demo containers are running (docker compose ps)
#
# Usage:
#   ./scripts/verify_setup.sh
#
# Environment variables:
#   PARSEABLE_URL   - Parseable base URL (default: http://localhost:8000)
#   PARSEABLE_AUTH  - user:password  (default: parseable:parseable)
#

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PARSEABLE_URL="${PARSEABLE_URL:-http://localhost:8000}"
PARSEABLE_AUTH="${PARSEABLE_AUTH:-parseable:parseable}"

PASS=0
FAIL=0
WARN=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

pass() {
    PASS=$((PASS + 1))
    echo -e "  ${GREEN}[PASS]${NC} $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}[FAIL]${NC} $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "         ${YELLOW}Tip:${NC} $2"
    fi
}

warn() {
    WARN=$((WARN + 1))
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

separator() {
    echo ""
    echo "-----------------------------------------------------------"
    echo "  $1"
    echo "-----------------------------------------------------------"
}

# ---------------------------------------------------------------------------
# Check 1: Parseable liveness
# ---------------------------------------------------------------------------
separator "Parseable Health"

LIVENESS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${PARSEABLE_URL}/api/v1/liveness" 2>/dev/null || echo "000")

if [[ "$LIVENESS_CODE" == "200" ]]; then
    pass "Parseable is running at ${PARSEABLE_URL}"
else
    fail "Parseable is not reachable at ${PARSEABLE_URL} (HTTP ${LIVENESS_CODE})" \
         "Start Parseable with: docker run -p 8000:8000 parseable/parseable:latest parseable local-store"
fi

# ---------------------------------------------------------------------------
# Check 2: Authentication
# ---------------------------------------------------------------------------
AUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${PARSEABLE_AUTH}" \
    "${PARSEABLE_URL}/api/v1/logstream" 2>/dev/null || echo "000")

if [[ "$AUTH_CODE" == "200" ]]; then
    pass "Parseable authentication successful"
elif [[ "$AUTH_CODE" == "401" ]]; then
    fail "Parseable authentication failed (HTTP 401)" \
         "Check PARSEABLE_AUTH env var (current: ${PARSEABLE_AUTH%%:*}:***)"
else
    fail "Cannot list log streams (HTTP ${AUTH_CODE})" \
         "Ensure Parseable is fully started and accepting connections."
fi

# ---------------------------------------------------------------------------
# Check 3: Log streams
# ---------------------------------------------------------------------------
separator "Log Streams"

if [[ "$AUTH_CODE" == "200" ]]; then
    STREAMS_JSON=$(curl -s -u "${PARSEABLE_AUTH}" "${PARSEABLE_URL}/api/v1/logstream" 2>/dev/null)

    if command -v jq &>/dev/null; then
        STREAM_COUNT=$(echo "$STREAMS_JSON" | jq 'length' 2>/dev/null || echo "0")
        STREAM_NAMES=$(echo "$STREAMS_JSON" | jq -r '.[].name' 2>/dev/null || echo "")
    else
        # Rough count without jq
        STREAM_COUNT=$(echo "$STREAMS_JSON" | tr ',' '\n' | grep -c '"name"' || echo "0")
        STREAM_NAMES="(install jq for stream names)"
    fi

    if [[ "$STREAM_COUNT" -gt 0 ]]; then
        pass "Found ${STREAM_COUNT} log stream(s)"
        for s in $STREAM_NAMES; do
            echo "         - $s"
        done
    else
        fail "No log streams found" \
             "Ensure the OTel Collector is configured to send data to Parseable."
    fi

    # Check for expected streams from OTel Demo
    for EXPECTED in "otel-logs" "traces"; do
        if echo "$STREAM_NAMES" | grep -q "^${EXPECTED}$"; then
            pass "Expected stream '${EXPECTED}' exists"
        else
            warn "Expected stream '${EXPECTED}' not found (may use a different name)"
        fi
    done
else
    warn "Skipping stream check (authentication failed)"
fi

# ---------------------------------------------------------------------------
# Check 4: Data flowing
# ---------------------------------------------------------------------------
separator "Data Flow"

if [[ "$AUTH_CODE" == "200" ]] && [[ -n "$STREAM_NAMES" ]] && command -v jq &>/dev/null; then
    for STREAM in $STREAM_NAMES; do
        # Query recent 5-minute window
        QUERY="SELECT COUNT(*) AS cnt FROM \"${STREAM}\" WHERE p_timestamp > NOW() - INTERVAL '5 minutes'"
        RESULT=$(curl -s -X POST "${PARSEABLE_URL}/api/v1/query" \
            -u "${PARSEABLE_AUTH}" \
            -H "Content-Type: application/json" \
            -d "{\"query\": \"${QUERY}\", \"startTime\": \"$(date -u -v-5M +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null || date -u -d "5 minutes ago" +"%Y-%m-%dT%H:%M:%S+00:00")\", \"endTime\": \"$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")\"}" 2>/dev/null)

        COUNT=$(echo "$RESULT" | jq '.[0].cnt // 0' 2>/dev/null || echo "0")

        if [[ "$COUNT" -gt 0 ]]; then
            pass "Stream '${STREAM}' has ${COUNT} records in last 5 minutes"
        else
            warn "Stream '${STREAM}' has no records in last 5 minutes (may be idle)"
        fi
    done
else
    if ! command -v jq &>/dev/null; then
        warn "Skipping data flow check (jq not installed)"
    else
        warn "Skipping data flow check (no streams available)"
    fi
fi

# ---------------------------------------------------------------------------
# Check 5: OTel Demo (Docker Compose)
# ---------------------------------------------------------------------------
separator "OTel Demo Containers"

if command -v docker &>/dev/null; then
    # Try to detect running OTel Demo containers
    OTEL_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i "otel\|opentelemetry" || true)

    if [[ -n "$OTEL_CONTAINERS" ]]; then
        OTEL_COUNT=$(echo "$OTEL_CONTAINERS" | wc -l | tr -d ' ')
        pass "Found ${OTEL_COUNT} OTel Demo container(s) running"
        echo "$OTEL_CONTAINERS" | while read -r name; do
            echo "         - $name"
        done
    else
        # Also check via docker compose
        COMPOSE_CONTAINERS=$(docker compose ps --format '{{.Name}}' 2>/dev/null || true)
        if [[ -n "$COMPOSE_CONTAINERS" ]]; then
            COMPOSE_COUNT=$(echo "$COMPOSE_CONTAINERS" | wc -l | tr -d ' ')
            pass "Found ${COMPOSE_COUNT} container(s) via docker compose"
        else
            fail "No OTel Demo containers detected" \
                 "Start the OTel Demo with: cd opentelemetry-demo && docker compose up -d"
        fi
    fi

    # Check for the OTel Collector specifically
    COLLECTOR=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i "otelcol\|otel-col\|collector" || true)
    if [[ -n "$COLLECTOR" ]]; then
        pass "OTel Collector container is running ($COLLECTOR)"
    else
        warn "OTel Collector container not found (may use a different name)"
    fi
else
    warn "Docker not found -- skipping container checks"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==========================================================="
echo "  Setup Verification Summary"
echo "==========================================================="
echo -e "  ${GREEN}Passed: ${PASS}${NC}"
if [[ $WARN -gt 0 ]]; then
    echo -e "  ${YELLOW}Warnings: ${WARN}${NC}"
fi
if [[ $FAIL -gt 0 ]]; then
    echo -e "  ${RED}Failed: ${FAIL}${NC}"
fi
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "  Some checks failed. Review the tips above and try again."
    echo ""
    echo "  Quick start:"
    echo "    1. Start Parseable:"
    echo "       docker run -p 8000:8000 parseable/parseable:latest parseable local-store"
    echo ""
    echo "    2. Start OTel Demo with Parseable overlay:"
    echo "       cd opentelemetry-demo"
    echo "       docker compose -f docker-compose.yaml -f docker-compose.override.yaml up -d"
    echo ""
    exit 1
elif [[ $WARN -gt 0 ]]; then
    echo "  Setup looks mostly good. Review warnings if any features are not working."
    exit 0
else
    echo "  All checks passed. Your environment is ready."
    exit 0
fi
