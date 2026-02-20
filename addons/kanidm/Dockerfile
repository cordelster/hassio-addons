ARG BUILD_FROM
FROM ${BUILD_FROM}

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Kanidm from Alpine edge/testing with version pinning
ARG KANIDM_VERSION=1.9.0-r0

RUN apk add --allow-untrusted \
    --repository=https://jambox-it.github.io/apk-repo/v3.23/JamBox \
    jambox-keys && apk update
    
RUN apk add --no-cache \
    kanidm=${KANIDM_VERSION} \
    kanidm-server=${KANIDM_VERSION} \
    kanidm-ldap-sync=${KANIDM_VERSION} \
    kanidm-ipa-sync=${KANIDM_VERSION} \
    kanidm-clients=${KANIDM_VERSION} \
    openssl=~3.5 \
    ca-certificates \
    curl=~8.17 \
    expect \
    --repository=https://jambox-it.github.io/apk-repo/edge/JamBox \
    && rm -rf /var/cache/apk/* /tmp/* /root/.cache

# Create directory structure with proper permissions
RUN mkdir -p \
    /data \
    /config/config \
    /config/certs \
    /config/backups \
    /config/migrations.d \
    /config/sync \
    /run/kanidmd \
    /var/log/kanidm-sync \
    /etc/kanidm \
    && chmod 755 /data /config \
    && chmod 750 /config/certs \
    && chmod 700 /config/backups \
    && chmod 750 /config/migrations.d \
    && chmod 755 /etc/kanidm

# Declare volumes for documentation and optimization
VOLUME ["/data", "/config"]

# Copy library modules
COPY lib/ /usr/local/lib/kanidm/
RUN chmod -R 755 /usr/local/lib/kanidm/

# Copy migration scripts
COPY migrations/ /usr/local/share/kanidm/migrations/
RUN chmod -R 755 /usr/local/share/kanidm/migrations/

# Copy helper scripts
COPY --chmod=755 healthcheck.sh /usr/local/bin/healthcheck.sh

# Copy run script (do this last for better caching)
COPY --chmod=755 run.sh /run.sh

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

# Run
CMD ["/run.sh"]
