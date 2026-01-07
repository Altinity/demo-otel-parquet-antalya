# ClickHouse + OTLP Logs

Ingest OpenTelemetry logs via OTLP/HTTP and query them with ClickHouse.

## Architecture

```
OTLP/HTTP -> otlp2parquet -> S3 (rustfs) -> ClickHouse
                         |
                   ice-rest-catalog (Iceberg)
```

## Quick Start

```bash
docker compose up -d
```

Services:
- **otlp2parquet**: `localhost:4318` - OTLP/HTTP ingestion
- **ClickHouse**: `localhost:8123`
- **rustfs console**: `localhost:9001` - S3 web UI (rustfsuser/rustfspassword)
- **ice-rest-catalog**: `localhost:5001` - Iceberg REST catalog

## Send Test Logs

```bash
curl -X POST http://localhost:4318/v1/logs \
  -H "Content-Type: application/json" \
  -d '{
    "resourceLogs": [{
      "resource": {
        "attributes": [{"key": "service.name", "value": {"stringValue": "my-app"}}]
      },
      "scopeLogs": [{
        "scope": {"name": "my-scope"},
        "logRecords": [{
          "timeUnixNano": "'$(date +%s)'000000000",
          "severityText": "INFO",
          "body": {"stringValue": "Hello from my-app!"}
        }]
      }]
    }]
  }'
```

Logs are batched and flushed every 10 seconds (or 200k rows / 128MB).

## Query Logs

Wait ~10 seconds for the batch to flush, then query:

```bash
# Using curl
curl "http://localhost:8123/" --data-binary "SELECT * FROM otel_logs FORMAT Pretty"

# Using clickhouse client
clickhouse client --query "SELECT ServiceName, SeverityText, Body, Timestamp FROM otel_logs"
```

`otel_logs` is a view set up to query the parquet files in the rustfs bucket.

@TODO: Make this work with rest-ice-catalog

### Available Columns

| Column | Type | Description |
|--------|------|-------------|
| Timestamp | DateTime64(6) | Log timestamp |
| ServiceName | String | service.name resource attribute |
| SeverityText | String | Log level (INFO, WARN, ERROR, etc.) |
| SeverityNumber | Int32 | Numeric severity |
| Body | String | Log message |
| TraceId | String | Trace ID (if present) |
| SpanId | String | Span ID (if present) |
| ResourceAttributes | Map(String, String) | Resource attributes |
| LogAttributes | Map(String, String) | Log attributes |
| ScopeName | String | Instrumentation scope name |

### Example Queries

```sql
-- Recent logs
SELECT Timestamp, ServiceName, SeverityText, Body
FROM otel_logs
ORDER BY Timestamp DESC
LIMIT 10;

-- Error count by service
SELECT ServiceName, count() as errors
FROM otel_logs
WHERE SeverityText IN ('ERROR', 'FATAL')
GROUP BY ServiceName;

-- Logs for a specific trace
SELECT * FROM otel_logs WHERE TraceId = 'abc123';
```

## Configuration

### OpenTelemetry SDK

Configure your app's OTLP exporter:

```yaml
# environment variables
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/json
```

### OpenTelemetry Collector

```yaml
exporters:
  otlphttp:
    endpoint: http://localhost:4318
    tls:
      insecure: true

service:
  pipelines:
    logs:
      exporters: [otlphttp]
```

## Cleanup

```bash
# Stop services
docker compose down

# Remove all data
docker compose down -v
rm -rf ./data
```
