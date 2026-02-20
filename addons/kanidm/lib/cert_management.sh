#!/bin/bash
# JamBoxKanidm SELFIE Certificate Management
# 🤳 Taking SELFIEs: Self-signed, Experimental, Lab-use, Fun, Interior-network, Educational
#
# This library manages the complete certificate lifecycle for Kanidm addon:
# - Root CA generation (trust anchor)
# - Intermediate CA generation (best practice)
# - Server certificate generation (with dynamic SANs)
# - Chain file creation for users and Kanidm
#
# Files created:
#   /data/certs/JamBoxKanidm-SELFIE-RootCA.{key,crt}
#   /data/certs/JamBoxKanidm-SELFIE-IntermediateCA.{key,crt}
#   /ssl/JamBoxKanidm-SELFIE-Server.{key,crt}
#   /ssl/JamBoxKanidm-SELFIE-CA-Chain.pem         (USERS IMPORT THIS!)
#   /ssl/JamBoxKanidm-SELFIE-FullChain.pem        (KANIDM USES THIS!)

set -e

# Source bashio for logging (only if not already sourced)
if [ -z "${BASHIO_VERSION:-}" ]; then
    source /usr/lib/bashio/bashio.sh
fi

# Certificate paths
CA_DIR="/data/certs"
SSL_DIR="/ssl"

ROOT_CA_KEY="${CA_DIR}/JamBoxKanidm-SELFIE-RootCA.key"
ROOT_CA_CRT="${CA_DIR}/JamBoxKanidm-SELFIE-RootCA.crt"
INTERMEDIATE_CA_KEY="${CA_DIR}/JamBoxKanidm-SELFIE-IntermediateCA.key"
INTERMEDIATE_CA_CRT="${CA_DIR}/JamBoxKanidm-SELFIE-IntermediateCA.crt"

SERVER_KEY="${SSL_DIR}/JamBoxKanidm-SELFIE-Server.key"
SERVER_CRT="${SSL_DIR}/JamBoxKanidm-SELFIE-Server.crt"
CA_CHAIN="${SSL_DIR}/JamBoxKanidm-SELFIE-CA-Chain.pem"
FULL_CHAIN="${SSL_DIR}/JamBoxKanidm-SELFIE-FullChain.pem"

# ============================================
# Generate Root CA (One-Time)
# ============================================
generate_root_ca() {
    bashio::log.info "🤳 Taking a ROOT CA SELFIE..."

    # Generate Root CA private key (4096-bit RSA)
    openssl genrsa -out "${ROOT_CA_KEY}" 4096 2>/dev/null
    chmod 400 "${ROOT_CA_KEY}"

    # Generate Root CA certificate (self-signed, 10 years)
    openssl req -x509 -new -nodes \
        -key "${ROOT_CA_KEY}" \
        -sha256 -days 3650 \
        -out "${ROOT_CA_CRT}" \
        -subj "/CN=JamBox Kanidm SELFIE Root CA/O=JamBox Homelab/C=US" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        2>/dev/null

    chmod 644 "${ROOT_CA_CRT}"

    bashio::log.info "  ✓ Root CA SELFIE captured! (Valid 10 years)"
}

# ============================================
# Generate Intermediate CA (One-Time)
# ============================================
generate_intermediate_ca() {
    bashio::log.info "🤳 Taking an INTERMEDIATE CA SELFIE..."

    # Generate Intermediate CA private key (4096-bit RSA)
    openssl genrsa -out "${INTERMEDIATE_CA_KEY}" 4096 2>/dev/null
    chmod 400 "${INTERMEDIATE_CA_KEY}"

    # Generate Intermediate CA CSR
    openssl req -new \
        -key "${INTERMEDIATE_CA_KEY}" \
        -out /tmp/intermediate.csr \
        -subj "/CN=JamBox Kanidm SELFIE Intermediate CA/O=JamBox Homelab/C=US" \
        2>/dev/null

    # Sign Intermediate CA with Root CA (5 years)
    openssl x509 -req -in /tmp/intermediate.csr \
        -CA "${ROOT_CA_CRT}" \
        -CAkey "${ROOT_CA_KEY}" \
        -CAcreateserial \
        -out "${INTERMEDIATE_CA_CRT}" \
        -days 1825 -sha256 \
        -extfile <(cat <<EOF
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
EOF
) 2>/dev/null

    chmod 644 "${INTERMEDIATE_CA_CRT}"
    rm -f /tmp/intermediate.csr

    bashio::log.info "  ✓ Intermediate CA SELFIE captured! (Valid 5 years)"
}

# ============================================
# Generate Server Certificate (Renewable)
# ============================================
generate_server_certificate() {
    local hostname="$1"
    local domain="$2"
    local ip_address="$3"

    bashio::log.info "🤳 Taking a SERVER SELFIE..."

    # Get dynamic addon hostname from Supervisor
    local addon_hostname
    if command -v curl >/dev/null 2>&1 && [ -n "${SUPERVISOR_TOKEN:-}" ]; then
        addon_hostname=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
            http://supervisor/addons/self/info 2>/dev/null | jq -r '.data.hostname // empty')
    fi
    addon_hostname="${addon_hostname:-local-kanidm}"

    bashio::log.info "  Building SELFIE with multiple identities:"
    bashio::log.info "    - homeassistant (internal Docker network)"
    bashio::log.info "    - ${addon_hostname} (addon slug)"
    bashio::log.info "    - ${hostname}.${domain} (configured FQDN)"
    if [ -n "${ip_address}" ]; then
        bashio::log.info "    - ${ip_address} (IP address)"
    fi

    # Generate Server private key (4096-bit RSA)
    if ! openssl genrsa -out "${SERVER_KEY}" 4096; then
        bashio::log.error "🚨 Failed to generate server key at ${SERVER_KEY}"
        bashio::log.error "Check AppArmor profile allows writing to /ssl/"
        return 1
    fi
    chmod 400 "${SERVER_KEY}" 2>/dev/null || true

    # Build SAN list
    local san_list="DNS:homeassistant,DNS:${addon_hostname},DNS:local-kanidm,DNS:${hostname}.${domain}"
    if [ -n "${ip_address}" ]; then
        san_list="${san_list},IP:${ip_address}"
    fi

    # Generate Server CSR with SANs
    openssl req -new \
        -key "${SERVER_KEY}" \
        -out /tmp/server.csr \
        -subj "/CN=${hostname}.${domain}" \
        -addext "subjectAltName=${san_list}" \
        2>/dev/null

    # Sign Server certificate with Intermediate CA (1 year)
    openssl x509 -req -in /tmp/server.csr \
        -CA "${INTERMEDIATE_CA_CRT}" \
        -CAkey "${INTERMEDIATE_CA_KEY}" \
        -CAcreateserial \
        -out "${SERVER_CRT}" \
        -days 365 -sha256 \
        -copy_extensions copy \
        2>/dev/null

    chmod 644 "${SERVER_CRT}"
    rm -f /tmp/server.csr

    bashio::log.info "  ✓ Server SELFIE captured! (Valid 1 year)"
}

# ============================================
# Create Chain Files
# ============================================
create_chain_files() {
    bashio::log.info "📸 Assembling SELFIE album..."

    # Create CA Chain (Root + Intermediate) - USERS IMPORT THIS
    cat "${ROOT_CA_CRT}" "${INTERMEDIATE_CA_CRT}" > "${CA_CHAIN}"
    chmod 644 "${CA_CHAIN}"
    bashio::log.info "  ✓ CA-Chain.pem created (Root + Intermediate)"

    # Create Full Chain (Server + Intermediate) - KANIDM USES THIS
    cat "${SERVER_CRT}" "${INTERMEDIATE_CA_CRT}" > "${FULL_CHAIN}"
    chmod 644 "${FULL_CHAIN}"
    bashio::log.info "  ✓ FullChain.pem created (Server + Intermediate)"
}

# ============================================
# Check Certificate Expiration
# ============================================
check_certificate_expiration() {
    local cert_file="$1"
    local cert_name="$2"

    if [ ! -f "${cert_file}" ]; then
        return 1  # Certificate doesn't exist
    fi

    local expiry_date
    expiry_date=$(openssl x509 -in "${cert_file}" -noout -enddate 2>/dev/null | cut -d= -f2)

    local expiry_epoch
    # BusyBox date (Alpine) requires -D fmt -d datestring to parse non-epoch strings.
    # GNU date -d and BSD date -j are both unavailable/incompatible on BusyBox.
    expiry_epoch=$(date -D "%b %d %H:%M:%S %Y" -d "${expiry_date}" +%s 2>/dev/null)

    local current_epoch
    current_epoch=$(date +%s)

    local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))

    if [ ${days_left} -lt 30 ]; then
        bashio::log.warning "${cert_name} expires in ${days_left} days - renewal needed!"
        bashio::log.debug "🐛 Exp date: ${expiry_date} - Exp Epc: ${expiry_epoch} - Cur Epc: ${current_epoch}"
        return 1
    else
        bashio::log.debug "🐛 ${cert_name} valid for ${days_left} more days ✅"
        return 0
    fi
    
}

# ============================================
# Main Certificate Management Function
# ============================================
manage_selfie_certificates() {
    local hostname="$1"
    local domain="$2"
    local ip_address="${3:-}"

    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info "  🤳 JamBoxKanidm SELFIE Certificate Manager"
    bashio::log.info "=========================================="
    bashio::log.info ""

    # Ensure directories exist with proper permissions
    mkdir -p "${CA_DIR}"
    chmod 700 "${CA_DIR}" 2>/dev/null || true  # May fail if directory is read-only

    mkdir -p "${SSL_DIR}" 2>/dev/null || true  # /ssl is created by supervisor
    chmod 755 "${SSL_DIR}" 2>/dev/null || true  # May fail if directory is read-only

    # Check if Root CA exists
    if [ ! -f "${ROOT_CA_KEY}" ] || [ ! -f "${ROOT_CA_CRT}" ]; then
        bashio::log.info "No Root CA found - generating new SELFIE authority..."
        generate_root_ca
    else
        bashio::log.info "✓ Root CA already exists"
    fi

    # Check if Intermediate CA exists
    if [ ! -f "${INTERMEDIATE_CA_KEY}" ] || [ ! -f "${INTERMEDIATE_CA_CRT}" ]; then
        bashio::log.info "No Intermediate CA found - generating SELFIE intermediate..."
        generate_intermediate_ca
    else
        bashio::log.info "✓ Intermediate CA already exists"
    fi

    # Check if Server certificate exists and is valid
    local need_server_cert=false
    if [ ! -f "${SERVER_KEY}" ] || [ ! -f "${SERVER_CRT}" ]; then
        bashio::log.info "No Server certificate found - taking new SELFIE..."
        need_server_cert=true
    elif ! check_certificate_expiration "${SERVER_CRT}" "Server certificate"; then
        bashio::log.info "Server certificate expired or expiring soon - retaking SELFIE..."
        need_server_cert=true
    else
        bashio::log.info "✓ Server certificate is valid"
    fi

    if [ "${need_server_cert}" = true ]; then
        generate_server_certificate "${hostname}" "${domain}" "${ip_address}"
    fi

    # Always recreate chain files (they're cheap)
    create_chain_files

    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info " 🤳  SELFIE Photo Shoot Complete!"
    bashio::log.info "=========================================="
    bashio::log.info ""
    bashio::log.info "📸 Your JamBoxKanidm SELFIE certificates are ready!"
    bashio::log.info ""
    bashio::log.info "SELFIE = Self-signed, Experimental, Lab-use,"
    bashio::log.info "         Fun, Interior-network, Educational"
    bashio::log.info ""
    bashio::log.info "⚠️  HOMELAB USE ONLY - NOT FOR PRODUCTION ⚠️"
    bashio::log.info ""
    bashio::log.info "To trust your SELFIE on devices:"
    bashio::log.info "1. Download: ${CA_CHAIN}"
    bashio::log.info "2. Import to your OS/browser certificate store"
    bashio::log.info "3. Trust for 'Websites' or 'SSL/TLS'"
    bashio::log.info ""
    bashio::log.info "Certificate Details:"
    bashio::log.info "  Root CA:        Valid 10 years"
    bashio::log.info "  Intermediate:   Valid 5 years"
    bashio::log.info "  Server Cert:    Valid 1 year"
    bashio::log.info ""
    bashio::log.info "Files created:"
    bashio::log.info "  📁 ${CA_CHAIN}"
    bashio::log.info "     👆 IMPORT THIS FILE ON YOUR DEVICES!"
    bashio::log.info ""
    bashio::log.info "  📁 ${FULL_CHAIN}"
    bashio::log.info "     (Used by Kanidm server)"
    bashio::log.info ""
    bashio::log.info "  📁 ${SERVER_KEY}"
    bashio::log.info "     (Server private key - keep secret!)"
    bashio::log.info ""
    bashio::log.info "  🚧 Ready for production? Switch to Let's Encrypt:"
    bashio::log.info "   Set cert_type: letsencrypt in addon config"
    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info ""

    # Return paths for use by caller
    export TLS_CHAIN="${FULL_CHAIN}"
    export TLS_KEY="${SERVER_KEY}"
    export CA_CHAIN_FILE="${CA_CHAIN}"
}

# ============================================
# Verify Certificate Chain
# ============================================
verify_certificate_chain() {
    bashio::log.info "🔍 Verifying SELFIE certificate chain..."

    # Verify server cert against CA chain
    if openssl verify -CAfile "${CA_CHAIN}" "${SERVER_CRT}" >/dev/null 2>&1; then
        bashio::log.info "  ✓ Certificate chain is valid!"
        return 0
    else
        bashio::log.error "  ✗ Certificate chain verification failed!"
        openssl verify -CAfile "${CA_CHAIN}" "${SERVER_CRT}"
        return 1
    fi
}

# ============================================
# Display Certificate Information
# ============================================
show_certificate_info() {
    local cert_file="$1"

    bashio::log.info "Certificate Information:"
    bashio::log.info "$(openssl x509 -in "${cert_file}" -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null)"
}

# ============================================
# Cleanup Old SELFIE Certificates
# ============================================
cleanup_old_selfies() {
    bashio::log.info "Cleaning up old SELFIE certificates..."

    # Move to backup location
    local backup_dir="/config/backups/selfie-certs-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${backup_dir}"

    mv "${SSL_DIR}"/JamBoxKanidm-SELFIE-* "${backup_dir}/" 2>/dev/null || true

    bashio::log.info "  ✓ Old SELFIEs backed up to ${backup_dir}"
}

# If sourced, don't run anything
# If executed directly, show help
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    cat <<EOF
JamBox-Kanidm SELFIE Certificate Management Library

This library provides functions for managing self-signed certificates
with proper CA hierarchy for the Kanidm addon.

Functions:
  manage_selfie_certificates HOSTNAME DOMAIN [IP]  - Main function
  generate_root_ca                                  - Create Root CA
  generate_intermediate_ca                          - Create Intermediate CA
  generate_server_certificate HOSTNAME DOMAIN IP    - Create Server cert
  create_chain_files                                - Assemble chain files
  verify_certificate_chain                          - Verify chain validity
  check_certificate_expiration CERT_FILE NAME       - Check expiry
  show_certificate_info CERT_FILE                   - Display cert details
  cleanup_old_selfies                               - Backup old certs

Usage in run.sh:
  source /usr/local/lib/kanidm/cert_management.sh
  manage_selfie_certificates "\${HOSTNAME}" "\${DOMAIN}" "\${IP_ADDRESS}"
  # TLS_CHAIN and TLS_KEY are now exported

⚠️ Created with ❤️ on Valentine's Day 2026
🤳 Remember: SELFIE = Self-signed, Experimental, Lab-use,
              Fun, Interior-network, Educational!
⚠️ This is best effort to help those that find Certificates challenging and
  is a suitable, better than typical Cert deployment.
  Emoji to help highlight, this has it's limitations.
EOF
fi
