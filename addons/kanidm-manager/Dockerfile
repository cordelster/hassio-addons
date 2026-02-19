ARG BUILD_FROM
FROM ghcr.io/cordelster/kanidm-oauth2-manager:0.0.3

# Install bashio, nginx, and dependencies for Home Assistant addon integration
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    curl \
    jq \
    ca-certificates \
    nginx \
    && curl -J -L -o /tmp/bashio.tar.gz \
    "https://github.com/hassio-addons/bashio/archive/refs/tags/v0.16.2.tar.gz" \
    && mkdir -p /tmp/bashio \
    && tar zxvf /tmp/bashio.tar.gz --strip 1 -C /tmp/bashio \
    && mv /tmp/bashio/lib /usr/lib/bashio \
    && rm -rf /tmp/bashio* \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy run script and nginx config template
COPY --chmod=755 run.sh /run.sh
COPY nginx.conf.tmpl /etc/nginx/nginx.conf.tmpl

# Labels for Home Assistant
LABEL io.hass.version="1.0.0" \
      io.hass.type="addon" \
      io.hass.arch="arm64|aarch64|amd64"

# Override both entrypoint and command to use our script
ENTRYPOINT []
CMD ["/run.sh"]
