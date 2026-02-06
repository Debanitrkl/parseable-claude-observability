# Prompt: OTel Instrumentation for Flask Service

## System Context

You are an expert in OpenTelemetry instrumentation for Python services.

## Prompt

Add OpenTelemetry instrumentation to this Flask service. Include tracing with proper semantic conventions, context propagation for the outgoing HTTP call, and appropriate span attributes. Configure the OTLP HTTP exporter to send traces to Parseable.

**Requirements:**
- Use `opentelemetry-instrumentation-flask` for auto-instrumenting Flask routes
- Use `opentelemetry-instrumentation-requests` for propagating context on outgoing HTTP calls
- Set resource attributes: `service.name`, `service.version`, `deployment.environment`
- Configure OTLP/HTTP exporter endpoint as `http://parseable:8000/v1/traces`
- Add custom span attributes where meaningful

## Input Service Code

```python
# app.py - Bare Flask service (no instrumentation)
import requests
from flask import Flask, jsonify, request

app = Flask(__name__)

PAYMENT_SERVICE_URL = "http://payment-service:5001"


@app.route("/health")
def health():
    return jsonify({"status": "healthy"})


@app.route("/process", methods=["POST"])
def process_order():
    data = request.get_json()
    order_id = data.get("order_id")
    amount = data.get("amount")

    # Validate
    if not order_id or not amount:
        return jsonify({"error": "missing order_id or amount"}), 400

    # Call payment service
    resp = requests.post(
        f"{PAYMENT_SERVICE_URL}/charge",
        json={"order_id": order_id, "amount": amount},
        timeout=5,
    )

    if resp.status_code != 200:
        return jsonify({"error": "payment failed"}), 502

    return jsonify({"order_id": order_id, "status": "processed"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

## Expected Dependency Additions (requirements.txt)

```
flask
requests
opentelemetry-api
opentelemetry-sdk
opentelemetry-exporter-otlp-proto-http
opentelemetry-instrumentation-flask
opentelemetry-instrumentation-requests
```
