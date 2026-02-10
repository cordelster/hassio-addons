ARG BUILD_FROM
FROM ${BUILD_FROM}

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Kanidm from Alpine edge/testing with version pinning
ARG KANIDM_VERSION=1.8.5-r1
RUN apk add --no-cache \
    kanidm=${KANIDM_VERSION} \
    kanidm-server=${KANIDM_VERSION} \
    openssl=~3.1 \
    ca-certificates \
    curl=~8.14 \
    expect \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
    && rm -rf /var/cache/apk/* /tmp/* /root/.cache

# Create directory structure with proper permissions
RUN mkdir -p \
    /data \
    /config/config \
    /config/certs \
    /config/backups \
    /config/sync \
    /run/kanidmd \
    /var/log/kanidm-sync \
    && chmod 755 /data /config \
    && chmod 750 /config/certs \
    && chmod 700 /config/backups

# Declare volumes for documentation and optimization
VOLUME ["/data", "/config"]

# Copy health check script
COPY --chmod=755 healthcheck.sh /usr/local/bin/healthcheck.sh

# Copy run script (do this last for better caching)
COPY --chmod=755 run.sh /run.sh

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

# Run
CMD ["/run.sh"]
