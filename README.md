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

| # | Experiment | Type | Score |
|---|-----------|------|-------|
| 1 | Setup & Verification | -- | -- |
| 2 | Log Analysis | Live | 3/3 anomalies, 0 false positives |
| 3 | Query Generation | Live | 2/3 first attempt, 3/3 after correction |
| 4 | Alert Correlation | Scenario | Correct root cause + grouping |
| 5 | Incident RCA | Live | Correct diagnosis (high confidence) |
| 6 | Trace Analysis | Live | Full tree reconstruction, correct critical path |
| 7 | OTel Instrumentation | Live | Correct instrumentation with minor redundancy |
| 8 | Schema + SLO Design | Scenario | Production-quality schema + SLI framework |
| 9 | Runbook + Copilot | Scenario | Correct multi-turn triage |

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
| **Keystone** | Parseable's built-in AI assistant for natural language queries |
| **`p_timestamp`** | Auto-added timestamp field on every ingested record |
| **DataFusion SQL** | PostgreSQL-compatible SQL engine used by Parseable |
| **OTLP ingestion** | Native OpenTelemetry Protocol HTTP endpoint on port 8000 |

## SQL Syntax Reference (DataFusion)

All SQL queries in this repository use DataFusion syntax (PostgreSQL-compatible):

| Function | DataFusion Syntax | Notes |
|----------|------------------|-------|
| Percentile | `APPROX_PERCENTILE_CONT(col, 0.99)` | Approximate percentile |
| Count | `COUNT(*)` | Standard SQL count |
| Time interval | `NOW() - INTERVAL '1 hour'` | Quoted interval value |
| Timestamp field | `p_timestamp` | Auto-added by Parseable |
| String match | `col LIKE '%pattern%'` | Standard SQL LIKE |
| Conditional count | `COUNT(*) FILTER (WHERE condition)` | DataFusion filter clause |

## Cost Estimates

| Experiment | Input Tokens | Output Tokens | Estimated Cost |
|------------|-------------|---------------|----------------|
| Log analysis (200 lines) | ~45,000 | ~2,000 | ~$0.75 |
| SQL generation (3 queries) | ~3,000 | ~1,500 | ~$0.10 |
| Alert correlation (18 alerts) | ~5,000 | ~3,000 | ~$0.20 |
| Incident RCA (multi-signal) | ~25,000 | ~4,000 | ~$0.55 |
| Trace analysis (28 spans) | ~15,000 | ~3,000 | ~$0.35 |
| OTel instrumentation | ~2,000 | ~3,000 | ~$0.12 |
| **Total (all experiments)** | **~95,000** | **~19,500** | **~$2.07** |

## License

MIT License. See [LICENSE](LICENSE) for details.

## Related Links

- [Parseable](https://www.parseable.com) - The observability backend used in all experiments
- [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/) - The microservices application
- [Claude API Documentation](https://docs.anthropic.com) - Anthropic's API docs
- [Blog Post](https://www.parseable.com/blog/opus-4-6-observability) - The full write-up with analysis
