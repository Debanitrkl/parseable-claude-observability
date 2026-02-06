# Parseable + Claude Opus 4.6: Observability Co-pilot Experiments

Companion repository for the blog post: **[Using Claude Opus 4.6 as an Observability Co-pilot with Parseable](https://www.parseable.com/blog/opus-4-6-observability)**

This repository contains all prompts, sample data, evaluation criteria, SQL queries, and configuration files needed to reproduce every experiment described in the blog post.

## Architecture

```
OTel Demo Services (10+ microservices)
    -> OpenTelemetry Collector
        -> Parseable (OTLP HTTP ingestion on port 8000)
            -> Logs stored as log streams (one per service)
            -> Traces stored as log stream data
            -> Metrics queryable via DataFusion SQL
```

## Prerequisites

- Docker and Docker Compose
- [Parseable](https://github.com/parseablehq/parseable) (runs via Docker)
- [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo)
- Claude API key (from [Anthropic Console](https://console.anthropic.com))
- Python 3.10+ (for integration scripts)
- `curl` and `jq` for API interactions

## Quick Start

```bash
# 1. Start Parseable
docker run -p 8000:8000 \
  parseable/parseable:latest \
  parseable local-store

# 2. Clone and start OTel Demo with Parseable as backend
git clone https://github.com/open-telemetry/opentelemetry-demo.git
cd opentelemetry-demo

# 3. Copy our collector config overlay
cp ../config/otel-collector-config.yaml src/otelcollector/otelcol-config-extras.yaml

# 4. Start the demo
docker compose up -d

# 5. Open Parseable Prism UI
open http://localhost:8000
# Default credentials: parseable / parseable
```

## Repository Structure

```
.
├── README.md
├── config/
│   ├── otel-collector-config.yaml    # OTel Collector config for Parseable
│   └── docker-compose.override.yaml  # Docker Compose overlay for Parseable
├── experiments/
│   ├── 01-setup/                     # Stack deployment and verification
│   ├── 02-log-analysis/              # Log pattern recognition (200 log lines)
│   ├── 03-query-generation/          # DataFusion SQL + PromQL generation
│   ├── 04-alert-correlation/         # Alert storm analysis (18 alerts)
│   ├── 05-incident-rca/              # Multi-signal root cause analysis
│   ├── 06-trace-analysis/            # Distributed trace reconstruction
│   ├── 07-otel-instrumentation/      # OTel instrumentation assistance
│   ├── 08-schema-slo/                # Log stream schema + SLO design
│   └── 09-runbook-copilot/           # Runbook generation + on-call copilot
├── scripts/
│   ├── run_experiment.py             # Run any experiment against Claude API
│   ├── export_parseable_data.sh      # Export data from Parseable log streams
│   └── verify_setup.sh              # Verify Parseable + OTel Demo are running
└── integration-patterns/
    ├── alert_webhook_claude.py       # Pattern 1: Alert -> Claude -> Slack
    ├── parseable_context_builder.py  # Gather context from Parseable for Claude
    └── health_summary.py            # Pattern 3: Periodic AI health summaries
```

## Experiments

Each experiment directory contains:

| File | Description |
|------|-------------|
| `README.md` | Experiment overview, type, and evaluation criteria |
| `prompt.md` | Exact prompt sent to Claude Opus 4.6 |
| `sample_data.json` | Input data (logs, traces, alerts, metrics) |
| `expected_output.md` | What we expected / ground truth |
| `evaluation.md` | Scoring rubric and results |
| `parseable_queries.sql` | SQL queries to reproduce data extraction from Parseable |

### Experiment Summary

| # | Experiment | Type | Score | Cost | Notes |
|---|-----------|------|-------|------|-------|
| 1 | Setup & Verification | -- | -- | -- | Stack deployment |
| 2 | Log Analysis | Live | 13/13 | $2.11 | 9 anomalies (3 crit, 3 warn, 3 info) + 2 cascading patterns, 0 false positives |
| 3 | Query Generation | Live | 9/9 (3/3 first attempt) | $0.40 | All 3 queries correct on first attempt using real schema |
| 4 | Alert Correlation | Scenario | 3.00/3.00 | $0.35 | 4-group decomposition, correct root cause, full causal chain (truncated at max_tokens) |
| 5 | Incident RCA | Scenario | 3.00/3.00 | $0.42 | CPU throttling root cause identified with 99% confidence, 7-step failure chain |
| 6 | Trace Analysis | Live | 3.00/3.00 | $0.63 | 33 spans across 5 services, deduplication handled, 2800:1 client-server gap found |
| 7 | OTel Instrumentation | Live | 4.5/5 | $0.24 | Correct instrumentation + context propagation, minor custom span redundancy |
| 8 | Schema + SLO Design | Scenario | 4.5/5 | $0.35 | 24-field schema + Go impl + PII handling (truncated at max_tokens) |
| 9 | Runbook + Copilot | Scenario | -- | -- | Not yet evaluated |

## Running Experiments

### Option 1: Manual (recommended for learning)

1. Deploy the stack (see Quick Start above)
2. Navigate to an experiment directory (e.g., `experiments/02-log-analysis/`)
3. Read the `README.md` for context
4. Load the sample data into Parseable (or use the provided SQL queries)
5. Copy the prompt from `prompt.md`
6. Send to Claude via the API or [Claude.ai](https://claude.ai)
7. Compare against `expected_output.md` and `evaluation.md`

### Option 2: Scripted

```bash
# Set your API key
export ANTHROPIC_API_KEY=your-key-here

# Run a specific experiment
python scripts/run_experiment.py --experiment 02-log-analysis

# Run all experiments
python scripts/run_experiment.py --all
```

## Key Parseable Concepts

| Term | Description |
|------|-------------|
| **Log stream** | A named collection of log data in Parseable (similar to a table) |
| **Prism UI** | Parseable's web-based UI for querying and visualization |
| **Keystone** (available in Parseable Cloud and Enterprise editions) | Parseable's AI orchestration layer -- uses LLMs (Claude, GPT-4, Bedrock) with built-in schema awareness to answer natural language queries via three internal agents (Intent, SQL, Visualization) |
| **`p_timestamp`** | Auto-added timestamp field on every ingested record |
| **DataFusion** | Apache Arrow's SQL query engine that powers Parseable's query layer |
| **OTLP ingestion** | Native OpenTelemetry Protocol HTTP endpoint on port 8000 |

## SQL Syntax Reference (PostgreSQL-compatible)

All SQL queries in this repository use PostgreSQL-compatible SQL, executed by Parseable's DataFusion query engine:

| Function | SQL Syntax | Notes |
|----------|------------------|-------|
| Percentile | `APPROX_PERCENTILE_CONT(col, 0.99)` | Approximate percentile |
| Count | `COUNT(*)` | Standard SQL count |
| Time interval | `NOW() - INTERVAL '1 hour'` | Quoted interval value |
| Timestamp field | `p_timestamp` | Auto-added by Parseable |
| String match | `col LIKE '%pattern%'` | Standard SQL LIKE |
| Conditional count | `COUNT(*) FILTER (WHERE condition)` | DataFusion filter clause |

## Actual Costs (Claude Opus 4.6)

| Experiment | Input Tokens | Output Tokens | Cost | Latency |
|------------|-------------|---------------|------|---------|
| 02: Log analysis | 126,451 | 2,870 | $2.11 | 68s |
| 03: SQL generation (3 queries) | 18,679 | 1,656 | $0.40 | 31s |
| 04: Alert correlation (18 alerts) | 3,109 | 4,096 | $0.35 | 80s |
| 05: Incident RCA (multi-signal) | 8,167 | 3,935 | $0.42 | 82s |
| 06: Trace analysis (33 spans) | 24,376 | 3,513 | $0.63 | 65s |
| 07: OTel instrumentation | 2,788 | 2,704 | $0.24 | 35s |
| 08: Schema + SLO design | 2,873 | 4,096 | $0.35 | 60s |
| **Total (7 experiments)** | **186,443** | **22,870** | **$4.50** | **~7 min** |

## License

MIT License. See [LICENSE](LICENSE) for details.

## Related Links

- [Parseable](https://www.parseable.com) - The observability backend used in all experiments
- [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/) - The microservices application
- [Claude API Documentation](https://docs.anthropic.com) - Anthropic's API docs
- [Blog Post](https://www.parseable.com/blog/opus-4-6-observability) - The full write-up with analysis
