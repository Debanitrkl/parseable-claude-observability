"""
Parseable Context Builder

Helper module for gathering observability context from Parseable to feed
into Claude prompts. All queries use DataFusion SQL syntax via the
Parseable REST API.

Usage:
    from parseable_context_builder import ParseableContext

    ctx = ParseableContext(url="http://localhost:8000", auth=("parseable", "parseable"))

    # Recent logs
    logs = ctx.get_recent_logs("otel-logs", minutes=15)

    # Error summary
    errors = ctx.get_error_summary("otel-logs", minutes=30)

    # Full trace
    spans = ctx.get_trace_for_id("abc123")

    # Stream health stats
    stats = ctx.get_stream_stats("otel-logs")

    # Multi-stream incident context
    context = ctx.build_incident_context(["otel-logs", "traces"], minutes=15)

Requires:
    pip install httpx
"""

import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

try:
    import httpx
except ImportError:
    raise ImportError("httpx is required: pip install httpx")


@dataclass
class StreamStats:
    """Summary statistics for a Parseable log stream."""

    stream: str
    total_records: int = 0
    error_count: int = 0
    warn_count: int = 0
    first_event: str = ""
    last_event: str = ""
    distinct_services: list[str] = field(default_factory=list)


@dataclass
class IncidentContext:
    """Aggregated context from multiple streams for incident analysis."""

    streams: list[str] = field(default_factory=list)
    window_minutes: int = 0
    recent_logs: dict[str, list[dict]] = field(default_factory=dict)
    error_summaries: dict[str, list[dict]] = field(default_factory=dict)
    stream_stats: dict[str, StreamStats] = field(default_factory=dict)

    def to_prompt_text(self) -> str:
        """Format the incident context as text suitable for a Claude prompt."""
        sections = []
        sections.append(
            f"## Incident Context (last {self.window_minutes} minutes)\n"
        )

        for stream in self.streams:
            sections.append(f"### Stream: {stream}\n")

            stats = self.stream_stats.get(stream)
            if stats:
                sections.append(
                    f"- Total records: {stats.total_records}\n"
                    f"- Errors: {stats.error_count}\n"
                    f"- Warnings: {stats.warn_count}\n"
                    f"- Services: {', '.join(stats.distinct_services)}\n"
                )

            errors = self.error_summaries.get(stream, [])
            if errors:
                sections.append("\n**Error Summary:**\n```json\n")
                sections.append(json.dumps(errors, indent=2, default=str))
                sections.append("\n```\n")

            logs = self.recent_logs.get(stream, [])
            if logs:
                sections.append(
                    f"\n**Recent Logs ({len(logs)} entries):**\n```json\n"
                )
                sections.append(json.dumps(logs[:50], indent=2, default=str))
                sections.append("\n```\n")

        return "\n".join(sections)


class ParseableContext:
    """Client for building observability context from Parseable."""

    def __init__(
        self,
        url: str | None = None,
        auth: tuple[str, str] | None = None,
        timeout: int = 30,
    ):
        self.url = url or os.environ.get("PARSEABLE_URL", "http://localhost:8000")
        if auth:
            self.auth = auth
        else:
            auth_str = os.environ.get("PARSEABLE_AUTH", "parseable:parseable")
            parts = auth_str.split(":", 1)
            self.auth = (parts[0], parts[1]) if len(parts) == 2 else (parts[0], "")
        self.timeout = timeout

    def _query(self, sql: str, start_time: str, end_time: str) -> list[dict]:
        """Execute a DataFusion SQL query via the Parseable REST API."""
        payload = {
            "query": sql,
            "startTime": start_time,
            "endTime": end_time,
        }
        with httpx.Client(timeout=self.timeout) as client:
            resp = client.post(
                f"{self.url}/api/v1/query",
                json=payload,
                auth=self.auth,
            )
            resp.raise_for_status()
            return resp.json()

    def _time_range(self, minutes: int) -> tuple[str, str]:
        """Return (start_time, end_time) ISO strings for the given look-back window."""
        now = datetime.now(timezone.utc)
        start = now - timedelta(minutes=minutes)
        fmt = "%Y-%m-%dT%H:%M:%S+00:00"
        return start.strftime(fmt), now.strftime(fmt)

    # -----------------------------------------------------------------
    # Public API
    # -----------------------------------------------------------------

    def get_recent_logs(
        self,
        stream: str,
        minutes: int = 15,
        limit: int = 200,
    ) -> list[dict]:
        """Fetch recent log entries from a stream.

        Uses DataFusion SQL with p_timestamp for time filtering.
        Returns logs ordered by timestamp ascending.
        """
        sql = (
            f'SELECT * FROM "{stream}" '
            f"WHERE p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
            f"ORDER BY p_timestamp ASC "
            f"LIMIT {limit}"
        )
        start_time, end_time = self._time_range(minutes)
        return self._query(sql, start_time, end_time)

    def get_error_summary(
        self,
        stream: str,
        minutes: int = 15,
    ) -> list[dict]:
        """Get error counts grouped by message for the recent window.

        Returns rows with columns: message, count, sorted by count descending.
        """
        sql = (
            f"SELECT message, COUNT(*) AS count "
            f'FROM "{stream}" '
            f"WHERE level IN ('error', 'ERROR', 'Error') "
            f"AND p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
            f"GROUP BY message "
            f"ORDER BY count DESC "
            f"LIMIT 25"
        )
        start_time, end_time = self._time_range(minutes)
        return self._query(sql, start_time, end_time)

    def get_trace_for_id(
        self,
        trace_id: str,
        trace_stream: str = "traces",
    ) -> list[dict]:
        """Retrieve all spans for a given trace ID.

        Searches the traces stream for all entries matching the trace_id.
        Returns spans ordered by start time.
        """
        sql = (
            f'SELECT * FROM "{trace_stream}" '
            f"WHERE trace_id = '{trace_id}' "
            f"ORDER BY p_timestamp ASC"
        )
        # Use a wide time range for trace lookups
        now = datetime.now(timezone.utc)
        start = now - timedelta(hours=24)
        fmt = "%Y-%m-%dT%H:%M:%S+00:00"
        return self._query(sql, start.strftime(fmt), now.strftime(fmt))

    def get_stream_stats(
        self,
        stream: str,
        minutes: int = 15,
    ) -> StreamStats:
        """Gather summary statistics for a log stream.

        Returns record counts, error/warn counts, time range, and distinct services.
        """
        start_time, end_time = self._time_range(minutes)

        # Total, error, warn counts
        count_sql = (
            f"SELECT "
            f"COUNT(*) AS total, "
            f"COUNT(CASE WHEN level IN ('error', 'ERROR', 'Error') THEN 1 END) AS errors, "
            f"COUNT(CASE WHEN level IN ('warn', 'WARN', 'Warn', 'warning', 'WARNING') THEN 1 END) AS warns, "
            f"MIN(p_timestamp) AS first_event, "
            f"MAX(p_timestamp) AS last_event "
            f'FROM "{stream}" '
            f"WHERE p_timestamp > NOW() - INTERVAL '{minutes} minutes'"
        )
        try:
            rows = self._query(count_sql, start_time, end_time)
        except Exception:
            return StreamStats(stream=stream)

        stats = StreamStats(stream=stream)
        if rows:
            row = rows[0]
            stats.total_records = int(row.get("total", 0))
            stats.error_count = int(row.get("errors", 0))
            stats.warn_count = int(row.get("warns", 0))
            stats.first_event = str(row.get("first_event", ""))
            stats.last_event = str(row.get("last_event", ""))

        # Distinct services
        svc_sql = (
            f'SELECT DISTINCT service_name FROM "{stream}" '
            f"WHERE p_timestamp > NOW() - INTERVAL '{minutes} minutes' "
            f"AND service_name IS NOT NULL"
        )
        try:
            svc_rows = self._query(svc_sql, start_time, end_time)
            stats.distinct_services = [
                r["service_name"] for r in svc_rows if r.get("service_name")
            ]
        except Exception:
            pass

        return stats

    def build_incident_context(
        self,
        streams: list[str],
        minutes: int = 15,
    ) -> IncidentContext:
        """Build a comprehensive incident context from multiple log streams.

        Gathers recent logs, error summaries, and stream statistics for each
        stream, then packages them into an IncidentContext object that can be
        serialized into a Claude prompt.
        """
        context = IncidentContext(
            streams=list(streams),
            window_minutes=minutes,
        )

        for stream in streams:
            try:
                context.recent_logs[stream] = self.get_recent_logs(
                    stream, minutes=minutes
                )
            except Exception as exc:
                context.recent_logs[stream] = [
                    {"_error": f"Failed to fetch logs: {exc}"}
                ]

            try:
                context.error_summaries[stream] = self.get_error_summary(
                    stream, minutes=minutes
                )
            except Exception:
                context.error_summaries[stream] = []

            try:
                context.stream_stats[stream] = self.get_stream_stats(
                    stream, minutes=minutes
                )
            except Exception:
                context.stream_stats[stream] = StreamStats(stream=stream)

        return context

    def list_streams(self) -> list[str]:
        """List all available log streams in Parseable."""
        with httpx.Client(timeout=self.timeout) as client:
            resp = client.get(
                f"{self.url}/api/v1/logstream",
                auth=self.auth,
            )
            resp.raise_for_status()
            data = resp.json()
            return [s["name"] for s in data if "name" in s]
