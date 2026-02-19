#!/usr/bin/bash
set -e

# Source bashio library functions
if [[ -f /usr/lib/bashio/bashio.sh ]]; then
    source /usr/lib/bashio/bashio.sh
else
    echo "ERROR: bashio library not found"
    exit 1
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
KANIDM_URL=$(bashio::config 'kanidm_url')
KANIDM_USERNAME=$(bashio::config 'kanidm_username')
KANIDM_PASSWORD=$(bashio::config 'kanidm_password')
ORIGIN=$(bashio::config 'origin')
ACCEPT_INVALID_CERTS=$(bashio::config 'tls.accept_invalid_certs')
CA_CERT_PATH=$(bashio::config 'tls.ca_cert_path' 2>/dev/null || echo "")

# ---------------------------------------------------------------------------
# Validate required fields
# ---------------------------------------------------------------------------
if [ -z "$KANIDM_URL" ]; then
    bashio::log.fatal "kanidm_url is required - please configure the Kanidm instance URL"
    exit 1
fi

if [ -z "$KANIDM_PASSWORD" ]; then
    bashio::log.fatal "kanidm_password is required - set the idm_admin password from your Kanidm addon logs"
    exit 1
fi

bashio::log.info "Kanidm URL : ${KANIDM_URL}"
bashio::log.info "Username   : ${KANIDM_USERNAME}"

# ---------------------------------------------------------------------------
# TLS configuration and validation
#
# Priority:
#   1. CA cert path provided and valid  → strict TLS with that CA
#   2. accept_invalid_certs = true      → disable TLS validation (insecure)
#   3. Neither                          → strict TLS (system CAs only)
#
# Common mistakes caught here:
#   - Path set but file missing
#   - File is a server/leaf cert, not a CA cert
#   - CA cert cannot verify the Kanidm server cert (incomplete chain)
# ---------------------------------------------------------------------------

validate_ca_cert() {
    local cert_path="$1"

    # Check it is actually a CA cert (not a leaf/server cert)
    local is_ca
    is_ca=$(openssl x509 -in "${cert_path}" -noout -purpose 2>/dev/null \
        | grep "SSL server CA" | grep -c "Yes" || true)
    if [ "${is_ca}" -eq 0 ]; then
        bashio::log.error "TLS: ${cert_path} is NOT a CA certificate (SSL server CA: No)"
        bashio::log.error "TLS: You must provide a CA/intermediate cert, not a server/leaf cert"
        bashio::log.error "TLS: Check the cert subject with: openssl x509 -in ${cert_path} -noout -subject"
        return 1
    fi

    # Extract hostname from kanidm_url for chain verification
    local kanidm_host
    kanidm_host=$(echo "${KANIDM_URL}" | sed 's|https\?://||' | cut -d: -f1)
    local kanidm_port
    kanidm_port=$(echo "${KANIDM_URL}" | sed 's|.*:||')
    # Default port if not specified
    [ "${kanidm_port}" = "${KANIDM_URL}" ] && kanidm_port=443

    # Try to verify the Kanidm server cert against the provided CA
    bashio::log.info "TLS: Verifying chain: ${cert_path} → ${kanidm_host}:${kanidm_port}"
    local server_cert
    server_cert=$(openssl s_client -connect "${kanidm_host}:${kanidm_port}" \
        -showcerts 2>/dev/null | openssl x509 2>/dev/null)

    if [ -z "${server_cert}" ]; then
        bashio::log.warning "TLS: Could not retrieve server cert from ${kanidm_host}:${kanidm_port} to verify chain"
        bashio::log.warning "TLS: Proceeding with provided CA cert unverified"
        return 0
    fi

    local verify_result
    verify_result=$(echo "${server_cert}" | openssl verify -CAfile "${cert_path}" 2>&1 || true)
    if echo "${verify_result}" | grep -q "OK"; then
        bashio::log.info "TLS: Chain verified OK - ${cert_path} trusts ${kanidm_host}"
        return 0
    else
        # Extract the specific error
        local verify_error
        verify_error=$(echo "${verify_result}" | grep "error\|unable" | head -1)
        bashio::log.error "TLS: Chain verification FAILED: ${verify_error}"

        # Give specific guidance based on error type
        if echo "${verify_error}" | grep -q "unable to get issuer"; then
            local issuer
            issuer=$(openssl x509 -in "${cert_path}" -noout -issuer 2>/dev/null | sed 's/issuer=//')
            bashio::log.error "TLS: The CA cert itself is not self-signed - it needs its own issuer:"
            bashio::log.error "TLS:   Missing: ${issuer}"
            bashio::log.error "TLS: You need a bundle: cat <root-ca.crt> ${cert_path} > /ssl/chain-bundle.crt"
            bashio::log.error "TLS: Then set tls.ca_cert_path to /ssl/chain-bundle.crt"
        elif echo "${verify_error}" | grep -q "self signed\|self-signed"; then
            bashio::log.error "TLS: Server uses a self-signed cert not covered by your CA"
        fi
        return 1
    fi
}

TLS_OK=false

if [ -n "${CA_CERT_PATH}" ]; then
    # Path was configured - validate it
    if [ ! -f "${CA_CERT_PATH}" ]; then
        bashio::log.error "TLS: CA cert file not found: ${CA_CERT_PATH}"
        bashio::log.error "TLS: Check the path exists in /ssl/ - available files:"
        ls /ssl/ 2>/dev/null | while read -r f; do
            bashio::log.error "TLS:   /ssl/${f}"
        done
    else
        if validate_ca_cert "${CA_CERT_PATH}"; then
            export NODE_EXTRA_CA_CERTS="${CA_CERT_PATH}"
            export NODE_TLS_REJECT_UNAUTHORIZED=1
            bashio::log.info "TLS: Mode: strict (CA cert: ${CA_CERT_PATH})"
            TLS_OK=true
        else
            bashio::log.warning "TLS: CA cert validation failed - see errors above"
            bashio::log.warning "TLS: Clear tls.ca_cert_path and set tls.accept_invalid_certs: true to bypass"
        fi
    fi
fi

if [ "${TLS_OK}" = "false" ]; then
    if bashio::var.true "${ACCEPT_INVALID_CERTS}"; then
        export NODE_TLS_REJECT_UNAUTHORIZED=0
        bashio::log.warning "TLS: Mode: INSECURE (accept_invalid_certs=true - validation disabled)"
        if [ -n "${CA_CERT_PATH}" ]; then
            bashio::log.warning "TLS: Note: tls.ca_cert_path was set but invalid - clear it once PKI is resolved"
        fi
        TLS_OK=true
    else
        export NODE_TLS_REJECT_UNAUTHORIZED=1
        bashio::log.info "TLS: Mode: strict (system CAs only - no custom CA cert)"
        TLS_OK=true
    fi
fi

# ---------------------------------------------------------------------------
# Export app environment
# ---------------------------------------------------------------------------
export KANIDM_BASE_URL="${KANIDM_URL}"
export KANIDM_USERNAME="${KANIDM_USERNAME}"
export KANIDM_PASSWORD="${KANIDM_PASSWORD}"
export ORIGIN="${ORIGIN}"

# ---------------------------------------------------------------------------
# Ingress path detection
#
# HA ingress serves the addon under /api/hassio_ingress/{token}/.
# The SvelteKit app makes absolute-path fetch calls (e.g. fetch("/api/kani"))
# which resolve against the browser origin - stripping the ingress prefix and
# hitting the HA frontend (404) instead of the addon.
#
# Fix: nginx on port 3000 strips the ingress prefix before forwarding to Bun
# on port 3001, and injects a fetch() monkey-patch into the HTML so the
# browser also prepends the prefix before sending requests.
# ---------------------------------------------------------------------------
bashio::log.info "Starting Kanidm Manager..."

INGRESS_PREFIX=""
if [ -z "${SUPERVISOR_TOKEN:-}" ]; then
    bashio::log.warning "Ingress: SUPERVISOR_TOKEN not set - cannot query Supervisor API"
else
    SUPERVISOR_RESPONSE=$(curl -sf \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        http://supervisor/addons/self/info 2>/dev/null || true)

    if [ -z "${SUPERVISOR_RESPONSE}" ]; then
        bashio::log.warning "Ingress: Supervisor API returned no response"
    else
        # Supervisor API shape varies by version:
        #   newer: { "ingress_entry": "..." }
        #   older: { "data": { "ingress_entry": "..." }, "result": "ok" }
        INGRESS_RAW=$(echo "${SUPERVISOR_RESPONSE}" | \
            jq -r '.ingress_entry // .data.ingress_entry // empty' 2>/dev/null || true)
        INGRESS_PREFIX="${INGRESS_RAW%/}"
        if [ -z "${INGRESS_PREFIX}" ]; then
            bashio::log.warning "Ingress: No ingress_entry in Supervisor response"
            bashio::log.warning "Ingress: API keys returned: $(echo "${SUPERVISOR_RESPONSE}" | jq -r 'keys[]' 2>/dev/null | tr '\n' ' ' || true)"
        fi
    fi
fi

if [ -n "${INGRESS_PREFIX}" ]; then
    bashio::log.info "Ingress: path prefix = ${INGRESS_PREFIX}"
    bashio::log.info "Ingress: UI accessible via HA sidebar (authentication enforced by HA)"
else
    bashio::log.warning "⚠️  Ingress: sidebar not detected - addon may be running without HA ingress"
    bashio::log.warning "⚠️  Ingress: if you enabled port 3000 in Network settings, it has NO auth protection"
    bashio::log.warning "🚨🔓 SECURITY: Anyone on your network can reach Kanidm Manager on port 3000."
    bashio::log.warning "🚨🔓 SECURITY: To secure access, disable port 3000 in addon Settings → Network"
    bashio::log.warning "🚨🔓 SECURITY: and enable 'Show in sidebar' to use HA-authenticated ingress."
fi

# ---------------------------------------------------------------------------
# nginx config generation
# ---------------------------------------------------------------------------
mkdir -p /tmp/nginx_client_body /tmp/nginx_proxy /tmp/nginx_fastcgi \
         /tmp/nginx_uwsgi /tmp/nginx_scgi

if [ -n "${INGRESS_PREFIX}" ]; then
    sed "s|INGRESS_PREFIX|${INGRESS_PREFIX}|g" /etc/nginx/nginx.conf.tmpl > /tmp/nginx.conf
else
    cat > /tmp/nginx.conf << 'NGINXEOF'
worker_processes 1;
error_log /proc/1/fd/2 warn;
pid /tmp/nginx.pid;
events { worker_connections 64; }
http {
    access_log off;
    client_max_body_size 10M;
    client_body_temp_path /tmp/nginx_client_body;
    proxy_temp_path       /tmp/nginx_proxy;
    fastcgi_temp_path     /tmp/nginx_fastcgi;
    uwsgi_temp_path       /tmp/nginx_uwsgi;
    scgi_temp_path        /tmp/nginx_scgi;
    server {
        listen 3000;
        server_name _;
        location / {
            proxy_pass http://127.0.0.1:3001;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
NGINXEOF
fi

nginx -c /tmp/nginx.conf
bashio::log.info "nginx: started (port 3000 → Bun port 3001)"

# ---------------------------------------------------------------------------
# Start application
# ---------------------------------------------------------------------------
export PORT=3001
bashio::log.info "Bun: starting on port 3001..."
cd /app
exec bun --smol run ./build/index.js
