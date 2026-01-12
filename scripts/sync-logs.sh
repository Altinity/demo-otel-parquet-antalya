#!/bin/sh
set -e

RUSTFS_ENDPOINT="${RUSTFS_ENDPOINT:-http://rustfs:9000}"
RUSTFS_BUCKET="${RUSTFS_BUCKET:-bucket1}"
RUSTFS_ACCESS_KEY="${RUSTFS_ACCESS_KEY:-rustfsuser}"
RUSTFS_SECRET_KEY="${RUSTFS_SECRET_KEY:-rustfspassword}"
ICE_CATALOG_URI="${ICE_CATALOG_URI:-http://ice-rest-catalog:5000}"
TABLE_NAME="${TABLE_NAME:-otel.logs}"
NAMESPACE="${TABLE_NAME%%.*}"
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"
STATE_FILE="${STATE_FILE:-/tmp/synced_files.txt}"

echo "=== OTEL Log Sync ==="
echo "Rustfs: $RUSTFS_ENDPOINT"
echo "Bucket: $RUSTFS_BUCKET"
echo "Namespace: $NAMESPACE"
echo "Table: $TABLE_NAME"
echo "Interval: ${SYNC_INTERVAL}s"

# Configure mc alias
mc alias set rustfs "$RUSTFS_ENDPOINT" "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" --api S3v4 >/dev/null 2>&1

# Initialize state file if it doesn't exist
touch "$STATE_FILE"

# Ensure namespace exists (will be created on first sync if needed)
ensure_namespace() {
    ice create-namespace "$NAMESPACE" 2>/dev/null || true
}

sync_files() {
    echo "[$(date -Iseconds)] Scanning for new parquet files..."

    # Find all parquet files
    ALL_FILES=$(mc find "rustfs/$RUSTFS_BUCKET/logs" --name '*.parquet' 2>/dev/null || true)

    if [ -z "$ALL_FILES" ]; then
        echo "[$(date -Iseconds)] No parquet files found"
        return
    fi

    # Filter out already processed files
    NEW_FILES=""
    for file in $ALL_FILES; do
        if ! grep -qxF "$file" "$STATE_FILE" 2>/dev/null; then
            NEW_FILES="$NEW_FILES $file"
        fi
    done

    # Trim leading space
    NEW_FILES=$(echo "$NEW_FILES" | sed 's/^ //')

    if [ -z "$NEW_FILES" ]; then
        echo "[$(date -Iseconds)] No new files to process"
        return
    fi

    FILE_COUNT=$(echo "$NEW_FILES" | wc -w | tr -d ' ')
    echo "[$(date -Iseconds)] Found $FILE_COUNT new parquet file(s)"

    # Ensure namespace exists before insert
    ensure_namespace

    # Convert to HTTP URLs and insert
    HTTP_URLS=$(echo "$NEW_FILES" | tr ' ' '\n' | sed "s|rustfs/$RUSTFS_BUCKET/|$RUSTFS_ENDPOINT/$RUSTFS_BUCKET/|g" | tr '\n' ' ')

    if ice insert -p "$TABLE_NAME" $HTTP_URLS 2>&1 | grep -v "^$"; then
        # Mark files as processed on success
        echo "$NEW_FILES" | tr ' ' '\n' >> "$STATE_FILE"
        echo "[$(date -Iseconds)] Sync complete - $FILE_COUNT file(s) added"
    else
        echo "[$(date -Iseconds)] Sync complete (with warnings)"
        # Still mark as processed to avoid retry loops
        echo "$NEW_FILES" | tr ' ' '\n' >> "$STATE_FILE"
    fi
}

# Initial sync
sync_files

# Loop forever
while true; do
    sleep "$SYNC_INTERVAL"
    sync_files
done
