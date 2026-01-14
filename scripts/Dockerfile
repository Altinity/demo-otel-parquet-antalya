FROM altinity/ice:latest AS ice

FROM eclipse-temurin:21-jre

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Copy ice jar from ice image
COPY --from=ice /usr/local/bin/ice /app/ice.jar

# Install mc (minio client)
RUN curl -sSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc

COPY sync-logs.sh /app/sync-logs.sh
RUN chmod +x /app/sync-logs.sh

WORKDIR /app

# ice wrapper script
RUN printf '#!/bin/sh\njava -jar /app/ice.jar "$@"\n' > /usr/local/bin/ice && chmod +x /usr/local/bin/ice

ENTRYPOINT ["/app/sync-logs.sh"]
