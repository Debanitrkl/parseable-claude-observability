#!/usr/bin/env bash
#
# Export log data from Parseable for use with Claude experiments.
#
# Queries a Parseable log stream using DataFusion SQL and saves the result
# as a JSON file.
#
# Usage:
#   ./scripts/export_parseable_data.sh --stream otel-logs --minutes 30
#   ./scripts/export_parseable_data.sh --stream otel-logs --minutes 60 --limit 500 --output data/export.json
#
# Environment variables:
#   PARSEABLE_URL   - Parseable base URL (default: http://localhost:8000)
#   PARSEABLE_AUTH  - user:password  (default: parseable:parseable)
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
PARSEABLE_URL="${PARSEABLE_URL:-http://localhost:8000}"
PARSEABLE_AUTH="${PARSEABLE_AUTH:-parseable:parseable}"

STREAM=""
MINUTES=30
LIMIT=200
OUTPUT=""

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export log data from Parseable as JSON.

Options:
  --stream NAME     Log stream name (required)
  --minutes N       Look-back window in minutes (default: 30)
  --limit N         Maximum number of records (default: 200)
  --output FILE     Output file path (default: exports/<stream>_<timestamp>.json)
  -h, --help        Show this help message

Environment:
  PARSEABLE_URL     Parseable base URL   (default: http://localhost:8000)
  PARSEABLE_AUTH    user:password         (default: parseable:parseable)

Examples:
  $(basename "$0") --stream otel-logs --minutes 60
  $(basename "$0") --stream otel-logs --minutes 15 --limit 500 --output my_export.json
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stream)
            STREAM="$2"; shift 2 ;;
        --minutes)
            MINUTES="$2"; shift 2 ;;
        --limit)
            LIMIT="$2"; shift 2 ;;
        --output)
            OUTPUT="$2"; shift 2 ;;
        -h|--help)
            usage ;;
        *)
            echo "Error: unknown option '$1'"
            usage ;;
    esac
done

if [[ -z "$STREAM" ]]; then
    echo "Error: --stream is required."
    echo ""
    usage
fi

# ---------------------------------------------------------------------------
# Determine output path
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "$OUTPUT" ]]; then
    EXPORT_DIR="$REPO_ROOT/exports"
    mkdir -p "$EXPORT_DIR"
    TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
    OUTPUT="$EXPORT_DIR/${STREAM}_${TIMESTAMP}.json"
fi

# Ensure parent directory exists
mkdir -p "$(dirname "$OUTPUT")"

# ---------------------------------------------------------------------------
# Build SQL query (PostgreSQL-compatible)
# ---------------------------------------------------------------------------
SQL="SELECT * FROM \"${STREAM}\" WHERE p_timestamp > NOW() - INTERVAL '${MINUTES} minutes' ORDER BY p_timestamp ASC LIMIT ${LIMIT}"

echo "Parseable URL:  $PARSEABLE_URL"
echo "Stream:         $STREAM"
echo "Look-back:      ${MINUTES} minutes"
echo "Limit:          $LIMIT"
echo "Query:          $SQL"
echo ""

# ---------------------------------------------------------------------------
# Execute query via Parseable REST API
# ---------------------------------------------------------------------------
HTTP_CODE=$(curl -s -o "$OUTPUT" -w "%{http_code}" \
    -X POST "${PARSEABLE_URL}/api/v1/query" \
    -u "${PARSEABLE_AUTH}" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"${SQL}\", \"startTime\": \"$(date -u -v-${MINUTES}M +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null || date -u -d "${MINUTES} minutes ago" +"%Y-%m-%dT%H:%M:%S+00:00")\", \"endTime\": \"$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")\"}")

echo "HTTP status: $HTTP_CODE"

if [[ "$HTTP_CODE" -ne 200 ]]; then
    echo ""
    echo "Error: Parseable query failed (HTTP $HTTP_CODE)."
    echo "Response body:"
    cat "$OUTPUT"
    echo ""
    echo ""
    echo "Troubleshooting:"
    echo "  - Is Parseable running at ${PARSEABLE_URL}?"
    echo "  - Do the credentials match? (current: ${PARSEABLE_AUTH%%:*}:***)"
    echo "  - Does the stream '${STREAM}' exist?"
    echo "    Check with: curl -s -u ${PARSEABLE_AUTH} ${PARSEABLE_URL}/api/v1/logstream"
    rm -f "$OUTPUT"
    exit 1
fi

# ---------------------------------------------------------------------------
# Report results
# ---------------------------------------------------------------------------
# Count records (top-level JSON array)
if command -v jq &>/dev/null; then
    RECORD_COUNT=$(jq 'length' "$OUTPUT" 2>/dev/null || echo "unknown")
    FILE_SIZE=$(wc -c < "$OUTPUT" | tr -d ' ')
    echo "Records:     $RECORD_COUNT"
    echo "File size:   $FILE_SIZE bytes"
else
    FILE_SIZE=$(wc -c < "$OUTPUT" | tr -d ' ')
    echo "File size:   $FILE_SIZE bytes"
    echo "(install jq for record count)"
fi

echo "Saved to:    $OUTPUT"
echo ""
echo "Done. Use this file with run_experiment.py or as context for Claude."
