# ClickHouse + OTLP Logs

Ingest OpenTelemetry logs via OTLP/HTTP and query them with ClickHouse.

## Architecture

```
OTLP/HTTP -> otlp2parquet -> S3 (rustfs) -> ice CLI -> ClickHouse
                                    |            |
                              parquet files  ice-rest-catalog (Iceberg)
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
- **log-sync**: Automatically syncs parquet files to Iceberg (every 60s by default)

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

## Automatic Sync

The **log-sync** service automatically registers new parquet files with Iceberg every 60 seconds (configurable via `LOG_SYNC_INTERVAL` env var).

Just send logs and query - no manual registration needed!

### Manual Registration (Optional)

If you need to manually register files:

```bash
# List parquet files
docker run --rm --network demo-otel-parquet-antalya_default --entrypoint="" minio/mc sh -c "
mc alias set local http://rustfs:9000 rustfsuser rustfspassword >/dev/null 2>&1
mc find local/bucket1/logs --name '*.parquet'
"

# Create namespace (first time only)
docker compose run --rm ice create-namespace otel

# Insert files using HTTP URLs (use http://rustfs:9000/bucket1/... instead of s3://bucket1/...)
docker compose run --rm ice insert -p --skip-duplicates otel.logs \
  "http://rustfs:9000/bucket1/logs/my-app/year=2026/month=01/day=12/hour=16/file.parquet"
```

## Query Logs

Query the Iceberg table from ClickHouse:

```bash
# Using curl
curl "http://localhost:8123/" --data-binary "SELECT * FROM ice.\`otel.logs\` FORMAT Pretty"

# Using clickhouse client
clickhouse client --query "SELECT ServiceName, SeverityText, Body, Timestamp FROM ice.\`otel.logs\`"
```

The `ice` database is configured as a DataLakeCatalog pointing to ice-rest-catalog.

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
FROM ice.`otel.logs`
ORDER BY Timestamp DESC
LIMIT 10;

-- Error count by service
SELECT ServiceName, count() as errors
FROM ice.`otel.logs`
WHERE SeverityText IN ('ERROR', 'FATAL')
GROUP BY ServiceName;

-- Logs for a specific trace
SELECT * FROM ice.`otel.logs` WHERE TraceId = 'abc123';
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
