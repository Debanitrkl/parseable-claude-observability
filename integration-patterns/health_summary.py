#!/usr/bin/env python3
"""
Pattern 3: Periodic Health Summaries

Runs saved SQL queries against key Parseable log streams on a configurable
interval, feeds the results to Claude (Sonnet 4.5 for cost efficiency),
generates a health summary in Markdown, and optionally posts it to Slack.

Usage:
    python integration-patterns/health_summary.py
    python integration-patterns/health_summary.py --interval 30 --once
    python integration-patterns/health_summary.py --streams otel-logs,traces --slack

Requires:
    pip install anthropic httpx

Environment variables:
    PARSEABLE_URL       - Parseable base URL (default: http://localhost:8000)
    PARSEABLE_AUTH      - user:password  (default: parseable:parseable)
    ANTHROPIC_API_KEY   - Claude API key
    SLACK_WEBHOOK_URL   - Slack incoming webhook URL (optional)
"""

import argparse
import json
import logging
import os
import sys
import textwrap
import time
from datetime import datetime, timedelta, timezone

try:
    import anthropic
    import httpx
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install anthropic httpx")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PARSEABLE_URL = os.environ.get("PARSEABLE_URL", "http://localhost:8000")
PARSEABLE_AUTH = os.environ.get("PARSEABLE_AUTH", "parseable:parseable")
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")

# Use Sonnet 4.5 for cost efficiency on periodic summaries
DEFAULT_MODEL = "claude-sonnet-4-5-20250929"
DEFAULT_INTERVAL_MINUTES = 15
DEFAULT_STREAMS = ["otel-logs", "traces"]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Parseable queries
# ---------------------------------------------------------------------------

def _auth_tuple() -> tuple[str, str]:
    parts = PARSEABLE_AUTH.split(":", 1)
    return (parts[0], parts[1]) if len(parts) == 2 else (parts[0], "")


def _time_range(minutes: int) -> tuple[str, str]:
    now = datetime.now(timezone.utc)
    start = now - timedelta(minutes=minutes)
    fmt = "%Y-%m-%dT%H:%M:%S+00:00"
    return start.strftime(fmt), now.strftime(fmt)


def query_parseable(sql: str, minutes: int) -> list[dict]:
    """Execute a DataFusion SQL query against Parseable."""
    start_time, end_time = _time_range(minutes)
    payload = {
        "query": sql,
        "startTime": start_time,
        "endTime": end_time,
    }
    with httpx.Client(timeout=30) as client:
        resp = client.post(
            f"{PARSEABLE_URL}/api/v1/query",
            json=payload,
            auth=_auth_tuple(),
        )
        resp.raise_for_status()
        return resp.json()


# Saved health-check SQL queries (DataFusion syntax, using p_timestamp)
HEALTH_QUERIES = {
    "log_volume": {
        "description": "Log volume by level in the last interval",
        "sql": (
            'SELECT level, COUNT(*) AS count '
            'FROM "{stream}" '
            "WHERE p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
            "GROUP BY level ORDER BY count DESC"
        ),
    },
    "error_rate": {
        "description": "Error rate per minute",
        "sql": (
            "SELECT DATE_TRUNC('minute', p_timestamp) AS minute_bucket, "
            "COUNT(*) AS total, "
            "COUNT(CASE WHEN level IN ('error', 'ERROR') THEN 1 END) AS errors "
            'FROM "{stream}" '
            "WHERE p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
            "GROUP BY minute_bucket ORDER BY minute_bucket ASC"
        ),
    },
    "top_errors": {
        "description": "Top error messages",
        "sql": (
            "SELECT message, COUNT(*) AS count "
            'FROM "{stream}" '
            "WHERE level IN ('error', 'ERROR', 'Error') "
            "AND p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
            "GROUP BY message ORDER BY count DESC LIMIT 10"
        ),
    },
    "slow_operations": {
        "description": "Warnings and slow operations",
        "sql": (
            "SELECT message, COUNT(*) AS count "
            'FROM "{stream}" '
            "WHERE level IN ('warn', 'WARN', 'warning', 'WARNING') "
            "AND p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
            "GROUP BY message ORDER BY count DESC LIMIT 10"
        ),
    },
    "service_health": {
        "description": "Records per service",
        "sql": (
            "SELECT service_name, level, COUNT(*) AS count "
            'FROM "{stream}" '
            "WHERE p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
            "AND service_name IS NOT NULL "
            "GROUP BY service_name, level ORDER BY count DESC"
        ),
    },
}


def run_health_queries(
    stream: str,
    minutes: int,
) -> dict[str, dict]:
    """Run all health queries for a stream and return results keyed by query name."""
    results = {}
    for name, qdef in HEALTH_QUERIES.items():
        sql = qdef["sql"].format(stream=stream, minutes=minutes)
        try:
            rows = query_parseable(sql, minutes)
            results[name] = {
                "description": qdef["description"],
                "data": rows,
                "record_count": len(rows),
            }
        except Exception as exc:
            logger.warning("Query '%s' failed for stream '%s': %s", name, stream, exc)
            results[name] = {
                "description": qdef["description"],
                "data": [],
                "error": str(exc),
            }
    return results


# ---------------------------------------------------------------------------
# Claude analysis
# ---------------------------------------------------------------------------

def generate_health_summary(
    all_stream_results: dict[str, dict[str, dict]],
    minutes: int,
    model: str = DEFAULT_MODEL,
) -> str:
    """Send health query results to Claude and get a markdown summary."""
    if not ANTHROPIC_API_KEY:
        return _fallback_summary(all_stream_results, minutes)

    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

    prompt = textwrap.dedent(f"""\
        You are an SRE producing a periodic health summary for our platform.
        Below are the results of automated health queries run against our Parseable
        log streams for the last {minutes} minutes.

        For each stream, analyze the data and produce a concise health report in Markdown.
        Include:
        1. **Overall Status**: Healthy / Degraded / Critical (with a one-line reason)
        2. **Key Metrics**: Log volume, error rate percentage, top errors
        3. **Trends**: Is the error rate increasing, stable, or decreasing?
        4. **Alerts**: Anything that needs immediate attention
        5. **Recommendations**: Brief, actionable next steps if any issues are found

        Keep the summary concise (under 500 words total).

        ## Health Query Results

        ```json
        {json.dumps(all_stream_results, indent=2, default=str)}
        ```
    """)

    response = client.messages.create(
        model=model,
        max_tokens=1500,
        messages=[{"role": "user", "content": prompt}],
    )

    text = ""
    for block in response.content:
        if block.type == "text":
            text += block.text

    logger.info(
        "Claude summary generated: %d chars, %d input tokens, %d output tokens",
        len(text),
        response.usage.input_tokens,
        response.usage.output_tokens,
    )
    return text


def _fallback_summary(
    all_stream_results: dict[str, dict[str, dict]],
    minutes: int,
) -> str:
    """Generate a basic summary without Claude (when API key is not set)."""
    lines = [f"# Health Summary (last {minutes} minutes)\n"]
    lines.append(f"_Generated at {datetime.now(timezone.utc).isoformat()}_\n")
    lines.append("_(Claude analysis unavailable -- ANTHROPIC_API_KEY not set)_\n")

    for stream, queries in all_stream_results.items():
        lines.append(f"## Stream: {stream}\n")
        for qname, qresult in queries.items():
            desc = qresult.get("description", qname)
            count = qresult.get("record_count", 0)
            lines.append(f"- **{desc}**: {count} result rows")
            if qresult.get("error"):
                lines.append(f"  (query error: {qresult['error']})")
        lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Slack posting
# ---------------------------------------------------------------------------

def post_summary_to_slack(summary: str) -> bool:
    """Post the health summary to Slack."""
    if not SLACK_WEBHOOK_URL:
        logger.info("SLACK_WEBHOOK_URL not set -- skipping Slack post")
        return False

    payload = {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "Platform Health Summary",
                },
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": summary[:2900],
                },
            },
        ],
    }

    try:
        with httpx.Client(timeout=10) as client:
            resp = client.post(SLACK_WEBHOOK_URL, json=payload)
            resp.raise_for_status()
            logger.info("Health summary posted to Slack")
            return True
    except Exception as exc:
        logger.error("Failed to post to Slack: %s", exc)
        return False


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def save_summary(summary: str, output_dir: str = "results/health-summaries") -> str:
    """Save the summary to a markdown file and return the file path."""
    os.makedirs(output_dir, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    filepath = os.path.join(output_dir, f"health_{timestamp}.md")
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(summary)
    return filepath


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def run_once(
    streams: list[str],
    minutes: int,
    model: str,
    post_slack: bool,
) -> str:
    """Run one cycle of health queries + Claude summary."""
    logger.info(
        "Running health check: streams=%s, window=%d min, model=%s",
        streams,
        minutes,
        model,
    )

    all_results: dict[str, dict[str, dict]] = {}
    for stream in streams:
        logger.info("Querying stream '%s'...", stream)
        all_results[stream] = run_health_queries(stream, minutes)

    logger.info("Generating health summary with Claude...")
    summary = generate_health_summary(all_results, minutes, model)

    filepath = save_summary(summary)
    logger.info("Summary saved to %s", filepath)

    if post_slack:
        post_summary_to_slack(summary)

    print("\n" + summary + "\n")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate periodic health summaries from Parseable data using Claude.",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=DEFAULT_INTERVAL_MINUTES,
        help=f"Interval between summaries in minutes (default: {DEFAULT_INTERVAL_MINUTES})",
    )
    parser.add_argument(
        "--streams",
        type=str,
        default=",".join(DEFAULT_STREAMS),
        help=f"Comma-separated list of log streams (default: {','.join(DEFAULT_STREAMS)})",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=DEFAULT_MODEL,
        help=f"Claude model for summaries (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Run once and exit (do not loop)",
    )
    parser.add_argument(
        "--slack",
        action="store_true",
        help="Post summaries to Slack (requires SLACK_WEBHOOK_URL)",
    )

    args = parser.parse_args()
    streams = [s.strip() for s in args.streams.split(",") if s.strip()]

    if not ANTHROPIC_API_KEY:
        logger.warning(
            "ANTHROPIC_API_KEY not set. Summaries will use a basic fallback format."
        )

    if args.once:
        run_once(streams, args.interval, args.model, args.slack)
        return

    logger.info(
        "Starting health summary loop (every %d minutes). Press Ctrl+C to stop.",
        args.interval,
    )

    while True:
        try:
            run_once(streams, args.interval, args.model, args.slack)
        except KeyboardInterrupt:
            logger.info("Shutting down.")
            break
        except Exception as exc:
            logger.error("Health summary cycle failed: %s", exc)

        logger.info("Next run in %d minutes...", args.interval)
        try:
            time.sleep(args.interval * 60)
        except KeyboardInterrupt:
            logger.info("Shutting down.")
            break


if __name__ == "__main__":
    main()
