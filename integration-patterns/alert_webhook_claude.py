#!/usr/bin/env python3
"""
Pattern 1: Parseable Alert -> Webhook -> Claude -> Slack

A Flask application that receives alert webhooks from Parseable,
gathers context from the affected log stream, sends everything to
Claude for analysis, and posts the resulting analysis to a Slack
channel via incoming webhook.

Setup:
    pip install flask anthropic httpx

    export PARSEABLE_URL=http://localhost:8000
    export PARSEABLE_AUTH=parseable:parseable
    export ANTHROPIC_API_KEY=sk-ant-...
    export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...

    python integration-patterns/alert_webhook_claude.py

Configure Parseable to send alert webhooks to http://<this-host>:5001/webhook

Parseable Alert Webhook Payload (example):
    {
        "alert_name": "HighErrorRate",
        "stream": "otel-logs",
        "message": "Error rate exceeded 5% in the last 5 minutes",
        "severity": "critical",
        "timestamp": "2026-01-15T14:32:00Z"
    }
"""

import json
import logging
import os
import sys
import textwrap
from datetime import datetime, timezone

try:
    import anthropic
    import httpx
    from flask import Flask, jsonify, request
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install flask anthropic httpx")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PARSEABLE_URL = os.environ.get("PARSEABLE_URL", "http://localhost:8000")
PARSEABLE_AUTH = os.environ.get("PARSEABLE_AUTH", "parseable:parseable")
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")
CONTEXT_WINDOW_MINUTES = int(os.environ.get("CONTEXT_WINDOW_MINUTES", "10"))
CONTEXT_LOG_LIMIT = int(os.environ.get("CONTEXT_LOG_LIMIT", "100"))
CLAUDE_MODEL = os.environ.get("CLAUDE_MODEL", "claude-opus-4-6")

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Parseable helpers
# ---------------------------------------------------------------------------

def _parseable_auth_tuple() -> tuple[str, str]:
    """Split PARSEABLE_AUTH into (user, password)."""
    parts = PARSEABLE_AUTH.split(":", 1)
    return (parts[0], parts[1]) if len(parts) == 2 else (parts[0], "")


def query_parseable(sql: str, start_time: str, end_time: str) -> list[dict]:
    """Execute a DataFusion SQL query against the Parseable REST API."""
    auth = _parseable_auth_tuple()
    payload = {
        "query": sql,
        "startTime": start_time,
        "endTime": end_time,
    }
    with httpx.Client(timeout=30) as client:
        resp = client.post(
            f"{PARSEABLE_URL}/api/v1/query",
            json=payload,
            auth=auth,
        )
        resp.raise_for_status()
        return resp.json()


def fetch_context_logs(stream: str, minutes: int = CONTEXT_WINDOW_MINUTES) -> list[dict]:
    """Fetch recent logs from the affected stream for context."""
    sql = (
        f'SELECT * FROM "{stream}" '
        f"WHERE p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
        f"ORDER BY p_timestamp DESC LIMIT {CONTEXT_LOG_LIMIT}"
    )
    now = datetime.now(timezone.utc)
    end_time = now.strftime("%Y-%m-%dT%H:%M:%S+00:00")
    # Approximate start time
    start_time = (
        datetime(now.year, now.month, now.day, tzinfo=timezone.utc)
        .strftime("%Y-%m-%dT00:00:00+00:00")
    )
    try:
        return query_parseable(sql, start_time, end_time)
    except Exception as exc:
        logger.error("Failed to fetch context logs from Parseable: %s", exc)
        return []


def fetch_error_summary(stream: str, minutes: int = CONTEXT_WINDOW_MINUTES) -> list[dict]:
    """Get error counts grouped by message for the recent window."""
    sql = (
        f'SELECT message, COUNT(*) AS count '
        f'FROM "{stream}" '
        f"WHERE level IN ('error', 'ERROR') "
        f"AND p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
        f"GROUP BY message ORDER BY count DESC LIMIT 20"
    )
    now = datetime.now(timezone.utc)
    end_time = now.strftime("%Y-%m-%dT%H:%M:%S+00:00")
    start_time = now.strftime("%Y-%m-%dT00:00:00+00:00")
    try:
        return query_parseable(sql, start_time, end_time)
    except Exception as exc:
        logger.error("Failed to fetch error summary: %s", exc)
        return []


# ---------------------------------------------------------------------------
# Claude analysis
# ---------------------------------------------------------------------------

def analyze_with_claude(alert: dict, context_logs: list[dict], error_summary: list[dict]) -> str:
    """Send alert + context to Claude and return the analysis text."""
    if not ANTHROPIC_API_KEY:
        return "(ANTHROPIC_API_KEY not set -- skipping Claude analysis)"

    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

    prompt = textwrap.dedent(f"""\
        You are an expert SRE. An alert has fired from our observability platform (Parseable).
        Analyze the alert and the surrounding log context to determine:

        1. **Root Cause**: What is most likely causing this alert?
        2. **Impact**: What services/users are affected?
        3. **Severity Assessment**: Is this critical, warning, or informational?
        4. **Recommended Actions**: What should the on-call engineer do right now?
        5. **Related Patterns**: Are there any correlated issues visible in the logs?

        ## Alert Details
        ```json
        {json.dumps(alert, indent=2)}
        ```

        ## Error Summary (last {CONTEXT_WINDOW_MINUTES} minutes)
        ```json
        {json.dumps(error_summary, indent=2)}
        ```

        ## Recent Logs (last {CONTEXT_WINDOW_MINUTES} minutes, up to {CONTEXT_LOG_LIMIT} entries)
        ```json
        {json.dumps(context_logs[:50], indent=2, default=str)}
        ```

        Provide a concise, actionable analysis. Use markdown formatting.
    """)

    response = client.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=2048,
        messages=[{"role": "user", "content": prompt}],
    )

    text = ""
    for block in response.content:
        if block.type == "text":
            text += block.text
    return text


# ---------------------------------------------------------------------------
# Slack notification
# ---------------------------------------------------------------------------

def post_to_slack(alert: dict, analysis: str) -> bool:
    """Post the analysis to a Slack incoming webhook."""
    if not SLACK_WEBHOOK_URL:
        logger.warning("SLACK_WEBHOOK_URL not set -- skipping Slack notification")
        return False

    alert_name = alert.get("alert_name", "Unknown Alert")
    severity = alert.get("severity", "unknown")
    stream = alert.get("stream", "unknown")

    severity_emoji = {
        "critical": ":red_circle:",
        "warning": ":large_yellow_circle:",
        "info": ":large_blue_circle:",
    }.get(severity.lower(), ":white_circle:")

    slack_payload = {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"{severity_emoji} Alert: {alert_name}",
                },
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Stream:*\n{stream}"},
                    {"type": "mrkdwn", "text": f"*Severity:*\n{severity}"},
                ],
            },
            {"type": "divider"},
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Claude Analysis:*\n{analysis[:2900]}",
                },
            },
        ],
    }

    try:
        with httpx.Client(timeout=10) as client:
            resp = client.post(SLACK_WEBHOOK_URL, json=slack_payload)
            resp.raise_for_status()
            logger.info("Slack notification sent successfully")
            return True
    except Exception as exc:
        logger.error("Failed to post to Slack: %s", exc)
        return False


# ---------------------------------------------------------------------------
# Flask routes
# ---------------------------------------------------------------------------

@app.route("/webhook", methods=["POST"])
def handle_webhook():
    """Receive a Parseable alert webhook, analyze with Claude, post to Slack."""
    alert = request.get_json(force=True)
    logger.info("Received alert webhook: %s", json.dumps(alert, default=str))

    stream = alert.get("stream", "")
    if not stream:
        logger.warning("Alert has no 'stream' field -- using 'otel-logs' as default")
        stream = "otel-logs"

    # Gather context from Parseable
    logger.info("Fetching context logs from stream '%s'...", stream)
    context_logs = fetch_context_logs(stream)
    error_summary = fetch_error_summary(stream)
    logger.info(
        "Context: %d log entries, %d error groups",
        len(context_logs),
        len(error_summary),
    )

    # Analyze with Claude
    logger.info("Sending to Claude (%s) for analysis...", CLAUDE_MODEL)
    analysis = analyze_with_claude(alert, context_logs, error_summary)
    logger.info("Claude analysis complete (%d chars)", len(analysis))

    # Post to Slack
    post_to_slack(alert, analysis)

    return jsonify({
        "status": "processed",
        "alert_name": alert.get("alert_name", ""),
        "analysis_length": len(analysis),
        "context_logs_count": len(context_logs),
    })


@app.route("/health", methods=["GET"])
def health():
    """Simple health check endpoint."""
    return jsonify({"status": "ok"})


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if not ANTHROPIC_API_KEY:
        logger.warning(
            "ANTHROPIC_API_KEY not set. Claude analysis will be skipped. "
            "Set it with: export ANTHROPIC_API_KEY=sk-ant-..."
        )
    if not SLACK_WEBHOOK_URL:
        logger.warning(
            "SLACK_WEBHOOK_URL not set. Slack notifications will be skipped. "
            "Set it with: export SLACK_WEBHOOK_URL=https://hooks.slack.com/..."
        )

    port = int(os.environ.get("PORT", "5001"))
    logger.info("Starting alert webhook server on port %d", port)
    logger.info("Parseable URL: %s", PARSEABLE_URL)
    logger.info("Claude model: %s", CLAUDE_MODEL)
    app.run(host="0.0.0.0", port=port, debug=False)
