#!/bin/bash
# Home Assistant OAuth2 Integration Setup
# This script creates a homeassistant_admins group and OAuth2 client for HA OIDC integration
# Called automatically on first run - provides a convenience integration option
# Non-fatal: If it fails, users can configure OAuth2 manually later

# Source bashio for logging functions
source /usr/lib/bashio/bashio.sh

# Don't exit on error - we want to be graceful
set +e

bashio::log.info "Creating Home Assistant OAuth2 resources..."

# Environment variables should be set by run.sh:
# - KANIDM_URL
# - KANIDM_SKIP_HOSTNAME_VERIFICATION
# - KANIDM_ACCEPT_INVALID_CERTS
# - HOME
# - PERSON_USERNAME
# - ORIGIN

# Note: We rely on the session from the idm_admin login in run.sh
# The token file location can vary, so we don't check for it explicitly
# If authentication fails, the commands below will fail gracefully

# Create homeassistant_admins group
bashio::log.info "Creating homeassistant_admins group..."
if kanidm group create "homeassistant_admins" 2>&1 | tee /tmp/ha_oauth_setup.log; then
    bashio::log.info "  ✓ Group created successfully"
else
    if grep -q "already exists" /tmp/ha_oauth_setup.log; then
        bashio::log.info "  ✓ Group already exists"
    else
        bashio::log.warning "  Could not create group (will try to continue)"
        cat /tmp/ha_oauth_setup.log | while IFS= read -r line; do bashio::log.debug "  $line"; done
    fi
fi

# Allow transaction to complete
sleep 0.5

# Add initial person to the group
bashio::log.info "Adding ${PERSON_USERNAME} to homeassistant_admins..."
if kanidm group add-members "homeassistant_admins" "${PERSON_USERNAME}" 2>&1 | tee /tmp/ha_oauth_setup.log; then
    bashio::log.info "  ✓ User added to group"
else
    bashio::log.info "  ✓ User already in group or group doesn't exist yet"
fi

# Allow transaction to complete
sleep 0.5

# Create OAuth2 public client for Home Assistant
bashio::log.info "Creating OAuth2 client for Home Assistant..."
if kanidm system oauth2 create-public "homeassistant" "Home Assistant" "${ORIGIN}" 2>&1 | tee /tmp/ha_oauth_setup.log; then
    bashio::log.info "  ✓ OAuth2 client created"
else
    if grep -q "already exists" /tmp/ha_oauth_setup.log; then
        bashio::log.info "  ✓ OAuth2 client already exists"
    else
        bashio::log.warning "  Could not create OAuth2 client"
        cat /tmp/ha_oauth_setup.log | while IFS= read -r line; do bashio::log.debug "  $line"; done
    fi
fi

# Allow transaction to complete
sleep 0.5

# Add redirect URL for OIDC callback
bashio::log.info "Configuring OAuth2 redirect URL..."
if kanidm system oauth2 add-redirect-url "homeassistant" "${ORIGIN}/auth/callback" 2>&1; then
    bashio::log.info "  ✓ Redirect URL configured"
else
    bashio::log.info "  ✓ Redirect URL already configured"
fi

# Allow transaction to complete
sleep 0.3

# Configure scope mapping (which groups get which scopes)
bashio::log.info "Configuring OAuth2 scope mapping..."
if kanidm system oauth2 update-scope-map "homeassistant" "homeassistant_admins" email groups openid profile 2>&1; then
    bashio::log.info "  ✓ Scope mapping configured"
else
    bashio::log.info "  ✓ Scope mapping already configured"
fi

# Display configuration information
bashio::log.info ""
bashio::log.info "=========================================="
bashio::log.info "Home Assistant OIDC Resources Created"
bashio::log.info "=========================================="
bashio::log.info ""
bashio::log.info "OAuth2 Client Type: Public (no secret required)"
bashio::log.info "Client ID: homeassistant"
bashio::log.info "Group: homeassistant_admins"
bashio::log.info ""
bashio::log.info "To configure hass-oidc-auth integration:"
bashio::log.info "  1. Install hass-oidc-auth from HACS"
bashio::log.info "  2. Configure with:"
bashio::log.info "     - Client ID: homeassistant"
bashio::log.info "     - Issuer URL: ${ORIGIN}"
bashio::log.info "     - Callback URL: ${ORIGIN}/auth/oidc/callback"
bashio::log.info ""
bashio::log.info "Note: This is a public client (no secret needed)"
bashio::log.info "Users in 'homeassistant_admins' group can log in"
bashio::log.info "=========================================="

rm -f /tmp/ha_oauth_setup.log
exit 0