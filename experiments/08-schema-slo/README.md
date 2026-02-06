# Experiment 08: Schema + SLO Design

**Type:** Scenario-Based
**Model:** Claude Opus 4.6

## Overview

This experiment evaluates Claude's ability to design a structured logging schema suitable for Parseable log stream ingestion, and to define an SLO/SLI framework with monitoring queries using DataFusion SQL.

## Scenario

A Go-based payment service needs structured logging with the following considerations:

- Logs are ingested into a Parseable log stream
- Schema must support distributed tracing correlation (trace_id, span_id)
- PII fields must be hashed before ingestion
- Fields should be flattened for optimal DataFusion query performance
- Parseable's static schema mode should be considered for enforcing structure
- SLO monitoring uses SQL queries run against the Parseable log stream

## Evaluation Criteria

| Criterion                | Weight | Description                                                    |
|--------------------------|--------|----------------------------------------------------------------|
| Schema design            | 25%    | Field naming, types, trace context inclusion                   |
| PII handling             | 15%    | Hashing sensitive fields before log emission                   |
| Parseable compatibility  | 20%    | Awareness of static vs dynamic schema modes, p_timestamp       |
| SLO/SLI framework        | 25%    | Correct availability and latency SLI definitions               |
| Monitoring queries       | 15%    | Valid DataFusion SQL for SLO burn rate and alerting             |

## Files

- `prompt.md` - The scenario prompt given to Claude
- `sample_data.json` - Example log events and designed schema
- `parseable_queries.sql` - SQL queries for SLO monitoring
- `evaluation.md` - Detailed evaluation of Claude's response
