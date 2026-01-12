# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a demo project for ingesting OpenTelemetry logs via OTLP/HTTP and querying them with ClickHouse using Iceberg tables stored in S3-compatible storage.

**Architecture:**
```
OTLP/HTTP -> otlp2parquet -> S3 (rustfs) -> ice CLI -> ClickHouse
                                    |            |
                              parquet files  ice-rest-catalog (Iceberg)
```

## Common Commands

```bash
# Start all services
docker compose up -d

# Stop services
docker compose down

# Stop and remove all data
docker compose down -v
rm -rf ./data

# Run ice CLI tool
devbox run ice <command>
# or directly:
docker compose run --rm ice "<command>"
```

## Services & Ports

| Service | Port | Description |
|---------|------|-------------|
| otlp2parquet | 4318 | OTLP/HTTP ingestion endpoint |
| ClickHouse HTTP | 8123 | Query interface |
| ClickHouse Native | 9000 | Native protocol |
| rustfs S3 | 8999 | S3 API (mapped from 9000) |
| rustfs Console | 9001 | Web UI (rustfsuser/rustfspassword) |
| ice-rest-catalog | 5001 | Iceberg REST catalog |

## Testing the Pipeline

### 1. Send test logs
```bash
curl -X POST http://localhost:4318/v1/logs \
  -H "Content-Type: application/json" \
  -d '{
    "resourceLogs": [{
      "resource": {
        "attributes": [{"key": "service.name", "value": {"stringValue": "test"}}]
      },
      "scopeLogs": [{
        "scope": {"name": "test"},
        "logRecords": [{
          "timeUnixNano": "'$(date +%s)'000000000",
          "severityText": "INFO",
          "body": {"stringValue": "Test message"}
        }]
      }]
    }]
  }'
```

### 2. Register parquet files with Iceberg (after ~10s flush)
```bash
# Copy parquet file locally (ice CLI can't access S3 directly for schema inference)
docker run --rm --network=demo-otel-parquet-antalya_default --entrypoint="" -v /tmp:/tmp minio/mc sh -c "
mc alias set local http://rustfs:9000 rustfsuser rustfspassword >/dev/null 2>&1
mc find local/bucket1/logs --name '*.parquet' | head -1 | xargs -I{} mc cp {} /tmp/sample.parquet
"

# Create namespace and insert (creates table on first insert with -p flag)
docker compose run --rm ice create-namespace otel
docker compose run --rm -v /tmp/sample.parquet:/app/sample.parquet ice insert -p otel.logs /app/sample.parquet
```

### 3. Query logs
```bash
curl "http://localhost:8123/" --data-binary "SELECT * FROM ice.\`otel.logs\` FORMAT Pretty"
```

## Development Environment

Uses devbox with:
- JDK 21 (headless)
- ClickHouse client

Initialize with `devbox shell`.
