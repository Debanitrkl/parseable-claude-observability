# Experiment 09: Runbook + On-Call Copilot

**Type:** Scenario-Based (Multi-Turn Conversation)
**Model:** Claude Opus 4.6

## Overview

This experiment evaluates Claude's ability to act as an on-call copilot during an incident, generating diagnostic runbooks that combine Parseable SQL queries with infrastructure commands, and maintaining context across multiple conversation turns.

## Scenario

A `CheckoutDBPoolExhausted` alert fires during on-call hours. The engineer uses Claude as a copilot across three conversation turns:

1. **Turn 1:** Alert context provided. Claude generates a diagnostic runbook with Parseable SQL queries.
2. **Turn 2:** Engineer reports query results (18 idle-in-transaction connections, "context deadline exceeded" errors from payment service). Claude analyzes and suggests remediation.
3. **Turn 3:** Pool recovered after killing sessions. Issue started after yesterday's deploy. Claude helps find the problematic code.

## Key Features Evaluated

- Parseable SQL queries mixed with infrastructure commands (kubectl, psql)
- Multi-turn context maintenance
- Correct identification of transaction leak pattern
- Actionable remediation steps
- Mention of Keystone (available in Parseable Cloud and Enterprise editions) as the production interface for delivering copilot capabilities to on-call engineers

## Keystone: Production Interface for Copilot Workflows

In production, Parseable's Keystone (available in Parseable Cloud and Enterprise editions) is the primary interface for these copilot interactions. It runs the same LLM-powered reasoning tested here -- with built-in schema awareness and direct access to all log streams from the Prism UI. On-call engineers use Keystone to query logs and get AI-assisted analysis without switching between tools or constructing prompts manually.

## Files

- `prompt.md` - The 3-turn conversation prompt
- `sample_data.json` - Alert context and simulated query results
- `parseable_queries.sql` - Parseable SQL queries from the generated runbook
- `evaluation.md` - Detailed evaluation of Claude's response across all turns
