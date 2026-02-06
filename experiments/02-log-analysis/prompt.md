# Prompt: Log Analysis

```
You are an SRE analyzing application logs from a microservices system. Below are
200 JSON-formatted log lines from the last 30 minutes. Analyze these logs and:

1. Identify anomalous patterns and error clusters
2. For each anomaly, explain the likely root cause
3. Prioritize findings by severity (critical / warning / info)
4. Note any patterns that suggest cascading failures

Output your analysis as structured JSON with fields: anomalies[], each containing
{description, severity, affected_service, time_range, evidence_count, root_cause_hypothesis}.

[Paste the contents of sample_data.json here]
```

## Notes

- The prompt asks for structured JSON output, which makes automated evaluation easier
- The model should be able to handle 200 log lines within its context window (~45K tokens)
- For follow-up analysis, you can include database schema information to improve root cause identification
