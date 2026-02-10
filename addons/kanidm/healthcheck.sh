#!/bin/bash
set -eo pipefail

# Healthcheck for Kanidm server
# Exit 0 = healthy, Exit 1 = unhealthy

TIMEOUT=3
MAX_RETRIES=2
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if timeout ${TIMEOUT} curl -f -k -s https://localhost:4869/status > /dev/null 2>&1; then
        exit 0
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 1
done

exit 1
