#!/usr/bin/bash
set -e

# Source bashio library functions
if [[ -f /usr/lib/bashio/bashio.sh ]]; then
    source /usr/lib/bashio/bashio.sh
else
    echo "ERROR: bashio library not found"
    exit 1
fi

# Get configuration from Home Assistant
KANIDM_URL=$(bashio::config 'kanidm_url')
KANIDM_USERNAME=$(bashio::config 'kanidm_username')
KANIDM_PASSWORD=$(bashio::config 'kanidm_password')
ORIGIN=$(bashio::config 'origin')
ACCEPT_INVALID_CERTS=$(bashio::config 'accept_invalid_certs')

# Validate required fields
if [ -z "$KANIDM_URL" ]; then
    bashio::log.fatal "kanidm_url is required!"
    bashio::log.fatal "Please configure the Kanidm instance URL"
    exit 1
fi

if [ -z "$KANIDM_PASSWORD" ]; then
    bashio::log.fatal "kanidm_password is required!"
    bashio::log.fatal "Please set the idm_admin password from your Kanidm addon logs"
    exit 1
fi

bashio::log.info "Starting Kanidm OAuth2 Manager..."
bashio::log.info "Connecting to: ${KANIDM_URL}"
bashio::log.info "Username: ${KANIDM_USERNAME}"

# Export environment variables for the kanidm-oauth2-manager application
export KANIDM_BASE_URL="${KANIDM_URL}"
export KANIDM_USERNAME="${KANIDM_USERNAME}"
export KANIDM_PASSWORD="${KANIDM_PASSWORD}"

# Set ORIGIN for the application (required for some features)
# This should be where users access the manager (via ingress or direct port)
export ORIGIN="${ORIGIN}"

# Configure TLS certificate validation based on user setting
if bashio::var.true "${ACCEPT_INVALID_CERTS}"; then
    export NODE_TLS_REJECT_UNAUTHORIZED=0
    bashio::log.warning "TLS certificate validation disabled (accepting self-signed certificates)"
else
    export NODE_TLS_REJECT_UNAUTHORIZED=1
    bashio::log.info "TLS certificate validation enabled (requires valid certificates)"
fi

bashio::log.info "Manager UI starting on port 3000..."
bashio::log.info "Access via Home Assistant sidebar or http://homeassistant.local:3000"

# Start the application using Bun runtime
cd /app
exec bun --smol run ./build/index.js
