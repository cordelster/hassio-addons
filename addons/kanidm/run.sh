#!/usr/bin/with-contenv bashio
set -e
set -o pipefail

# ==========================================
# KANIDM HOME ASSISTANT ADDON - MAIN SCRIPT
# ==========================================
# This script orchestrates the startup of the Kanidm server.
# Most logic has been extracted to modular libraries in lib/
#
# See CLAUDE.md for architecture overview

# ==========================================
# SOURCE LIBRARY MODULES
# ==========================================

LIB_DIR="/usr/local/lib/kanidm"

# Core libraries
source "${LIB_DIR}/detect_state.sh"      # State detection, marker file management
source "${LIB_DIR}/version_mgmt.sh"      # Version comparison, upgrade validation
source "${LIB_DIR}/config_migration.sh"  # Config schema migrations

# Initialization modules
source "${LIB_DIR}/init_database.sh"     # Database startup, readiness checks
source "${LIB_DIR}/init_idm_admin.sh"    # idm_admin login with retry logic
source "${LIB_DIR}/init_person.sh"       # Person account creation

bashio::log.debug "✓ Library modules loaded"

# ==========================================
# CONFIGURATION PERSISTENCE
# ==========================================
# Restore options.json BEFORE bashio reads it
# This must happen FIRST, before any bashio::config calls

BACKUP_OPTIONS="/config/options.json.backup"
if [[ -f "${BACKUP_OPTIONS}" ]] && [[ -f "/config/.admin_initialized" ]]; then
  # This is a reinstall (admin_initialized exists) with a config backup
  # Check if current options.json is the default (domain will be empty string "")
  if grep -q '"domain": ""' /data/options.json 2>/dev/null; then
    echo "[INFO] Detected reinstall - restoring configuration from backup..."
    cp "${BACKUP_OPTIONS}" /data/options.json
    echo "[INFO] Configuration restored successfully"
  fi
fi

# ==========================================
# ERROR HANDLER
# ==========================================

error_handler() {
  local exit_code=$?
  local line_no=$1
  local command=$2

  # Ignore certain expected failures from bashio library
  # bashio uses 'read -r -d' which returns 1 at EOF - this is normal
  if [[ "${command}" =~ ^read[[:space:]]+-r[[:space:]]+-d ]]; then
    return 0
  fi

  bashio::log.error "Command '${command}' failed with exit code ${exit_code} at line ${line_no}."
}

trap 'error_handler ${LINENO} "$BASH_COMMAND"' ERR

# ==========================================
# INPUT VALIDATION FUNCTIONS
# ==========================================
# These functions validate user inputs to prevent:
# - Command injection attacks
# - Path traversal attacks
# - Configuration corruption
# - Invalid data causing runtime errors

# Validate domain name (RFC 1035/1123 compliant)
# Valid: example.com, sub.example.com, test-domain.local
# Invalid: -example.com, example-.com, .example.com, example..com
validate_domain() {
    local domain="$1"
    local field_name="${2:-domain}"

    # Check for empty domain
    if [[ -z "${domain}" ]]; then
        bashio::log.fatal "${field_name} cannot be empty"
        return 1
    fi

    # Check length (max 253 characters for FQDN)
    if [[ ${#domain} -gt 253 ]]; then
        bashio::log.fatal "${field_name} is too long (max 253 characters): ${domain}"
        return 1
    fi

    # RFC 1035/1123 validation: letters, numbers, hyphens, dots
    # Each label must start/end with alphanumeric, max 63 chars per label
    if [[ ! "${domain}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        bashio::log.fatal "Invalid ${field_name} format: ${domain}"
        bashio::log.fatal "Domain must contain only letters, numbers, hyphens, and dots"
        bashio::log.fatal "Each part must start and end with a letter or number"
        return 1
    fi

    # Check for consecutive dots
    if [[ "${domain}" =~ \.\. ]]; then
        bashio::log.fatal "Invalid ${field_name}: consecutive dots not allowed: ${domain}"
        return 1
    fi

    # Check doesn't start or end with dot or hyphen
    if [[ "${domain}" =~ ^[.-] ]] || [[ "${domain}" =~ [.-]$ ]]; then
        bashio::log.fatal "Invalid ${field_name}: cannot start or end with dot or hyphen: ${domain}"
        return 1
    fi

    bashio::log.debug "✓ ${field_name} validated: ${domain}"
    return 0
}

# Validate hostname (single label, RFC 1123)
# Valid: kanidm, idm-server, host123
# Invalid: -kanidm, kanidm-, kanidm.example.com
validate_hostname() {
    local hostname="$1"
    local field_name="${2:-hostname}"

    # Check for empty hostname
    if [[ -z "${hostname}" ]]; then
        bashio::log.fatal "${field_name} cannot be empty"
        return 1
    fi

    # Check length (max 63 characters for single label)
    if [[ ${#hostname} -gt 63 ]]; then
        bashio::log.fatal "${field_name} is too long (max 63 characters): ${hostname}"
        return 1
    fi

    # Single label: alphanumeric and hyphens only, must start/end with alphanumeric
    if [[ ! "${hostname}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        bashio::log.fatal "Invalid ${field_name} format: ${hostname}"
        bashio::log.fatal "Hostname must contain only letters, numbers, and hyphens"
        bashio::log.fatal "Must start and end with a letter or number"
        bashio::log.fatal "Cannot contain dots (use domain field for FQDN)"
        return 1
    fi

    bashio::log.debug "✓ ${field_name} validated: ${hostname}"
    return 0
}

# Validate username (Kanidm username format)
# Valid: admin, john.doe, user_123
# Invalid: -admin, user$, .user
validate_username() {
    local username="$1"
    local field_name="${2:-username}"

    # Check for empty username
    if [[ -z "${username}" ]]; then
        bashio::log.fatal "${field_name} cannot be empty"
        return 1
    fi

    # Check length (reasonable limits)
    if [[ ${#username} -lt 2 ]]; then
        bashio::log.fatal "${field_name} is too short (min 2 characters): ${username}"
        return 1
    fi

    if [[ ${#username} -gt 64 ]]; then
        bashio::log.fatal "${field_name} is too long (max 64 characters): ${username}"
        return 1
    fi

    # Alphanumeric, dots, underscores, hyphens - must start with alphanumeric
    if [[ ! "${username}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        bashio::log.fatal "Invalid ${field_name} format: ${username}"
        bashio::log.fatal "Username must start with a letter or number"
        bashio::log.fatal "Can contain letters, numbers, dots, underscores, and hyphens"
        return 1
    fi

    bashio::log.debug "✓ ${field_name} validated: ${username}"
    return 0
}

# Validate file path is within allowed directory (prevent path traversal)
# Valid: cert.pem, certs/mycert.pem
# Invalid: ../etc/passwd, /etc/passwd, ../../secrets
validate_safe_path() {
    local path="$1"
    local base_dir="$2"
    local field_name="${3:-path}"

    # Check for empty path
    if [[ -z "${path}" ]]; then
        return 0  # Empty paths are handled separately
    fi

    # Reject absolute paths (paths starting with /)
    if [[ "${path}" =~ ^/ ]]; then
        bashio::log.fatal "Invalid ${field_name}: absolute paths not allowed: ${path}"
        bashio::log.fatal "Use relative paths within ${base_dir}/"
        return 1
    fi

    # Build full path and resolve it
    local full_path="${base_dir}/${path}"

    # Check for path traversal attempts
    if [[ "${path}" =~ \.\. ]]; then
        bashio::log.fatal "Invalid ${field_name}: path traversal not allowed: ${path}"
        return 1
    fi

    # Verify resolved path stays within base directory
    # Note: realpath may not exist in all environments, so we do string checking
    if [[ ! "${full_path}" =~ ^${base_dir}/ ]]; then
        bashio::log.fatal "Invalid ${field_name}: path escapes ${base_dir}/: ${path}"
        return 1
    fi

    bashio::log.debug "✓ ${field_name} validated: ${path} (within ${base_dir}/)"
    return 0
}

# Validate URI format (for LDAP URIs)
# Valid: ldap://server:389, ldaps://server.example.com:636
# Invalid: javascript:alert(1), file:///etc/passwd
validate_uri() {
    local uri="$1"
    local field_name="${2:-URI}"

    # Check for empty URI
    if [[ -z "${uri}" ]]; then
        return 0  # Empty URIs handled separately
    fi

    # Only allow ldap:// and ldaps:// schemes
    if [[ ! "${uri}" =~ ^ldaps?:// ]]; then
        bashio::log.fatal "Invalid ${field_name}: must use ldap:// or ldaps:// scheme: ${uri}"
        return 1
    fi

    # Basic URI format validation (scheme://host:port)
    if [[ ! "${uri}" =~ ^ldaps?://[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(:[0-9]{1,5})?(/.*)?$ ]]; then
        bashio::log.fatal "Invalid ${field_name} format: ${uri}"
        bashio::log.fatal "Expected format: ldap://hostname:port or ldaps://hostname:port"
        return 1
    fi

    # Extract and validate port if present
    if [[ "${uri}" =~ :([0-9]+) ]]; then
        local port="${BASH_REMATCH[1]}"
        if [[ ${port} -lt 1 ]] || [[ ${port} -gt 65535 ]]; then
            bashio::log.fatal "Invalid ${field_name}: port out of range (1-65535): ${port}"
            return 1
        fi
    fi

    bashio::log.debug "✓ ${field_name} validated: ${uri}"
    return 0
}

# Validate cron schedule format
# Valid: "0 2 * * *", "*/15 * * * *", "0 0 1 * *"
# Invalid: "invalid", "99 99 99 99 99"
validate_cron_schedule() {
    local schedule="$1"
    local field_name="${2:-cron schedule}"

    # Check for empty schedule
    if [[ -z "${schedule}" ]]; then
        bashio::log.fatal "${field_name} cannot be empty"
        return 1
    fi

    # Cron format: 5 fields separated by spaces (or tabs)
    # minute hour day month weekday
    # Disable glob expansion temporarily to prevent * from matching files
    local old_opts=$(set +o)
    set -f
    local -a fields=($schedule)
    eval "$old_opts"

    if [[ ${#fields[@]} -ne 5 ]]; then
        bashio::log.fatal "Invalid ${field_name}: must have 5 fields (minute hour day month weekday): ${schedule}"
        bashio::log.fatal "Found ${#fields[@]} fields: ${fields[*]}"
        return 1
    fi

    # Validate each field allows numbers, *, /, ,, -
    for field in "${fields[@]}"; do
        if [[ ! "${field}" =~ ^[0-9*/,-]+$ ]]; then
            bashio::log.fatal "Invalid ${field_name}: field contains invalid characters: ${field}"
            return 1
        fi
    done

    bashio::log.debug "✓ ${field_name} validated: ${schedule}"
    return 0
}

# Validate integer within range
validate_integer() {
    local value="$1"
    local min="$2"
    local max="$3"
    local field_name="${4:-value}"

    # Check if it's a valid integer
    if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
        bashio::log.fatal "Invalid ${field_name}: must be a positive integer: ${value}"
        return 1
    fi

    # Check range
    if [[ ${value} -lt ${min} ]] || [[ ${value} -gt ${max} ]]; then
        bashio::log.fatal "Invalid ${field_name}: must be between ${min} and ${max}: ${value}"
        return 1
    fi

    bashio::log.debug "✓ ${field_name} validated: ${value}"
    return 0
}

bashio::log.info "Starting Kanidm addon..."

# ==========================================
# READ CONFIGURATION
# ==========================================

DOMAIN=$(bashio::config 'domain')
HOSTNAME=$(bashio::config 'hostname')
LOG_LEVEL=$(bashio::config 'log_level')
PERSON_USERNAME=$(bashio::config 'person_username')
PERSON_DISPLAYNAME=$(bashio::config 'person_displayname')
CERT_TYPE=$(bashio::config 'certificates.type')
CERT_CHAIN_PATH=$(bashio::config 'certificates.chain_path')
CERT_KEY_PATH=$(bashio::config 'certificates.key_path')
ENABLE_LDAP=$(bashio::config 'enable_ldap')
DB_FS_TYPE=$(bashio::config 'database.fs_type')
DB_ARC_SIZE=$(bashio::config 'database.arc_size')
ENABLE_BACKUP=$(bashio::config 'enable_backup')
BACKUP_SCHEDULE=$(bashio::config 'backup_schedule')
BACKUP_VERSIONS=$(bashio::config 'backup_versions')
ENABLE_LDAP_SYNC=$(bashio::config 'directory_sync.enabled')
ENABLE_REPLICATION=$(bashio::config 'replication.enabled')

# Backup current config for future reinstalls
cp /data/options.json "${BACKUP_OPTIONS}"

# Hardcoded internal ports (Docker best practice)
WEB_PORT=4869
LDAP_PORT=3636
REPL_PORT=8444

# Build origin URL from hostname.domain and port (FQDN)
ORIGIN="https://${HOSTNAME}.${DOMAIN}:${WEB_PORT}"

bashio::log.debug "Configuration: DOMAIN=${DOMAIN}, HOSTNAME=${HOSTNAME}, LOG_LEVEL=${LOG_LEVEL}"
bashio::log.debug "Built ORIGIN=${ORIGIN} (using hardcoded internal port ${WEB_PORT})"

# ==========================================
# VALIDATE CONFIGURATION
# ==========================================

bashio::log.info "Validating configuration inputs..."

# Validate domain
if [[ -z "${DOMAIN}" ]]; then
    bashio::log.fatal "Domain is required!"
    exit 1
fi
validate_domain "${DOMAIN}" "domain" || exit 1

# Validate hostname
if [[ -z "${HOSTNAME}" ]]; then
    bashio::log.fatal "Hostname is required!"
    exit 1
fi
validate_hostname "${HOSTNAME}" "hostname" || exit 1

# Validate person username
if [[ -z "${PERSON_USERNAME}" ]]; then
    bashio::log.fatal "Person username is required!"
    exit 1
fi
validate_username "${PERSON_USERNAME}" "person_username" || exit 1

# Validate person display name
if [[ -z "${PERSON_DISPLAYNAME}" ]]; then
    bashio::log.fatal "Person display name is required!"
    exit 1
fi
if [[ ${#PERSON_DISPLAYNAME} -lt 2 ]] || [[ ${#PERSON_DISPLAYNAME} -gt 128 ]]; then
    bashio::log.fatal "Person display name must be between 2 and 128 characters: ${PERSON_DISPLAYNAME}"
    exit 1
fi
bashio::log.debug "✓ person_displayname validated: ${PERSON_DISPLAYNAME}"

# Validate backup schedule (if backups enabled)
if [[ "${ENABLE_BACKUP}" == "true" ]]; then
    validate_cron_schedule "${BACKUP_SCHEDULE}" "backup_schedule" || exit 1
    validate_integer "${BACKUP_VERSIONS}" 1 365 "backup_versions" || exit 1
fi

# Validate database ARC size (if specified and non-zero)
if [[ -n "${DB_ARC_SIZE}" ]] && [[ "${DB_ARC_SIZE}" != "0" ]]; then
    validate_integer "${DB_ARC_SIZE}" 64 4096 "database.arc_size (MB)" || exit 1
fi

# Validate certificate paths (if using custom certificates)
if [[ "${CERT_TYPE}" == "custom" ]]; then
    if [[ -n "${CERT_CHAIN_PATH}" ]]; then
        validate_safe_path "${CERT_CHAIN_PATH}" "/ssl" "certificates.chain_path" || exit 1
    fi
    if [[ -n "${CERT_KEY_PATH}" ]]; then
        validate_safe_path "${CERT_KEY_PATH}" "/ssl" "certificates.key_path" || exit 1
    fi
fi

bashio::log.info "✓ Configuration validation complete"

# ==========================================
# DETECT INSTALLATION STATE & VERSION TRACKING
# ==========================================

bashio::log.info "Detecting installation state..."

# Detect state (FRESH_INSTALL, NORMAL_STARTUP, UPGRADE_REQUIRED)
INSTALL_STATE=$(detect_installation_state)
bashio::log.info "Installation state: ${INSTALL_STATE}"

# Handle different states
case "${INSTALL_STATE}" in
    FRESH_INSTALL)
        bashio::log.info "Fresh installation detected"
        FIRST_RUN=true
        ;;
    
    NORMAL_STARTUP)
        bashio::log.info "Normal startup - no version changes"
        FIRST_RUN=false
        ;;
    
    UPGRADE_REQUIRED)
        bashio::log.info "Upgrade detected - validating..."
        FIRST_RUN=false
        
        # Validate upgrade path (exits on version skip)
        validate_upgrade || exit 1
        
        # Run pending migrations from previous Kanidm version if version changed
        if check_kanidm_major_minor_change; then
            bashio::log.info "Kanidm version changed - running pending migrations from previous version..."
            run_pending_migrations_from_previous_version || {
                bashio::log.error "Failed to run pending migrations"
                exit 1
            }
            
            # Clear migration list for new Kanidm version
            clear_applied_migrations
        fi
        
        # Run config migrations for current version
        bashio::log.info "Running config migrations..."
        run_config_migrations || {
            bashio::log.error "Config migrations failed"
            exit 1
        }
        ;;

    *)
        bashio::log.fatal "Unknown installation state: ${INSTALL_STATE}"
        exit 1
        ;;
esac

# Display state information
show_state_info


# ==========================================
# GENERATE SERVER CONFIGURATION
# ==========================================

bashio::log.info "Generating server configuration files..."

# Storage Structure:
# /config (addon_config) - User-accessible, survives reinstall, backed up
#   ├── config/          - Server configuration files
#   ├── certs/           - TLS certificates
#   └── .admin_initialized - Initialization marker
# /data - Private addon data, backed up but deleted on uninstall
#   └── kanidm.db        - Database file (can be large)

# Create necessary directories
mkdir -p /config/config
mkdir -p /config/certs
mkdir -p /data
mkdir -p /run/kanidmd

bashio::log.debug "Created directories - checking /config:"
ls -la /config/ 2>&1 | while IFS= read -r line; do bashio::log.debug "  $line"; done

bashio::log.info "Private data directory: /data (database only)"

# Create necessary directories
mkdir -p /config/config
mkdir -p /config/certs
mkdir -p /data
mkdir -p /run/kanidmd

bashio::log.info "Created directories - checking /config:"
ls -la /config/ 2>&1 | while IFS= read -r line; do bashio::log.info "  $line"; done

bashio::log.info "Checking /data:"
ls -la /data/ 2>&1 | while IFS= read -r line; do bashio::log.info "  $line"; done

# TLS Certificate Setup
bashio::log.info "Configuring TLS certificates (type: ${CERT_TYPE})..."

if [[ "${CERT_TYPE}" == "selfsigned" ]]; then
    # 🤳 Generate JamBoxKanidm SELFIE certificates with proper CA hierarchy
    bashio::log.info "Using JamBoxKanidm SELFIE certificates (homelab/testing only)"
    bashio::log.info "SELFIE = Self-signed, Experimental, Lab-use, Fun, Interior-network, Educational"

    # Source SELFIE certificate management library
    source /usr/local/lib/kanidm/cert_management.sh

    # Generate or verify SELFIE certificate chain
    # This creates: Root CA, Intermediate CA, Server cert, and chain files
    # Exports TLS_CHAIN and TLS_KEY for use below
    manage_selfie_certificates "${HOSTNAME}" "${DOMAIN}" "${IP_ADDRESS:-}"

    # TLS_CHAIN and TLS_KEY are now set by cert_management.sh
    # TLS_CHAIN="/ssl/JamBoxKanidm-SELFIE-FullChain.pem"
    # TLS_KEY="/ssl/JamBoxKanidm-SELFIE-Server.key"

elif [[ "${CERT_TYPE}" == "letsencrypt" ]]; then
    # Use Let's Encrypt addon certificates from /ssl/
    bashio::log.info "Using Let's Encrypt addon certificates from /ssl/"
    TLS_CHAIN="/ssl/fullchain.pem"
    TLS_KEY="/ssl/privkey.pem"

    # Validate that Let's Encrypt certificates exist
    if [[ ! -f "${TLS_CHAIN}" ]]; then
        bashio::log.fatal "Let's Encrypt certificate not found at ${TLS_CHAIN}"
        bashio::log.fatal "Make sure the Let's Encrypt addon is installed and configured"
        exit 1
    fi
    if [[ ! -f "${TLS_KEY}" ]]; then
        bashio::log.fatal "Let's Encrypt private key not found at ${TLS_KEY}"
        bashio::log.fatal "Make sure the Let's Encrypt addon is installed and configured"
        exit 1
    fi
    bashio::log.info "Let's Encrypt certificates found and validated"

elif [[ "${CERT_TYPE}" == "custom" ]]; then
    # Use custom certificate paths from /ssl/
    bashio::log.info "Using custom certificates from /ssl/"

    # Validate that custom paths are provided
    if [[ -z "${CERT_CHAIN_PATH}" ]]; then
        bashio::log.fatal "Custom certificate chain path is required when certificate_type is 'custom'"
        bashio::log.fatal "Please set cert_chain_path in addon configuration"
        exit 1
    fi
    if [[ -z "${CERT_KEY_PATH}" ]]; then
        bashio::log.fatal "Custom certificate key path is required when certificate_type is 'custom'"
        bashio::log.fatal "Please set cert_key_path in addon configuration"
        exit 1
    fi

    # Build full paths (paths in config are relative to /ssl/)
    TLS_CHAIN="/ssl/${CERT_CHAIN_PATH}"
    TLS_KEY="/ssl/${CERT_KEY_PATH}"

    # Validate that custom certificates exist
    if [[ ! -f "${TLS_CHAIN}" ]]; then
        bashio::log.fatal "Custom certificate not found at ${TLS_CHAIN}"
        bashio::log.fatal "Check that cert_chain_path '${CERT_CHAIN_PATH}' is correct"
        exit 1
    fi
    if [[ ! -f "${TLS_KEY}" ]]; then
        bashio::log.fatal "Custom private key not found at ${TLS_KEY}"
        bashio::log.fatal "Check that cert_key_path '${CERT_KEY_PATH}' is correct"
        exit 1
    fi
    bashio::log.info "Custom certificates found and validated"

else
    bashio::log.fatal "Invalid certificate_type: ${CERT_TYPE}"
    bashio::log.fatal "Valid options: selfsigned, letsencrypt, custom"
    exit 1
fi

bashio::log.info "TLS configured: chain=${TLS_CHAIN}, key=${TLS_KEY}"
bashio::log.debug "Certificate permissions:"
ls -l "${TLS_CHAIN}" "${TLS_KEY}" 2>&1 | while IFS= read -r line; do bashio::log.debug "  $line"; done

# Generate Kanidm configuration
bashio::log.info "Generating Kanidm configuration..."

# Start building the server.toml file
cat > /config/config/server.toml <<EOF
version ="2"
domain = "${DOMAIN}"
origin = "${ORIGIN}"
db_path = "/data/kanidm.db"
db_fs_type = "${DB_FS_TYPE}"
tls_chain = "${TLS_CHAIN}"
tls_key = "${TLS_KEY}"
bindaddress = "0.0.0.0:${WEB_PORT}"
log_level = "${LOG_LEVEL}"
EOF

# Add LDAP configuration if enabled
if [[ "${ENABLE_LDAP}" == "true" ]]; then
    bashio::log.info "LDAP is enabled - configuring LDAPS on port ${LDAP_PORT}"
    cat >> /config/config/server.toml <<EOF
ldapbindaddress = "0.0.0.0:${LDAP_PORT}"
EOF
else
    bashio::log.info "LDAP is disabled"
fi

# Add Replication configuration if enabled
if [[ "${ENABLE_REPLICATION}" == "true" ]]; then
    bashio::log.info "Replication is enabled - configuring replication..."

    # Build replication origin URL from hostname.domain and hardcoded port
    REPL_ORIGIN="repl://${HOSTNAME}.${DOMAIN}:${REPL_PORT}"

    cat >> /config/config/server.toml <<EOF

[replication]
origin = "${REPL_ORIGIN}"
bindaddress = "0.0.0.0:${REPL_PORT}"
EOF

    # Add replication partners
    partner_count=$(bashio::config 'replication.partners | length')
    if [ $partner_count -gt 0 ]; then
        bashio::log.info "Configuring ${partner_count} replication partner(s)..."
        for ((i=0; i<partner_count; i++)); do
            partner_origin=$(bashio::config "replication.partners[${i}].origin")
            partner_cert=$(bashio::config "replication.partners[${i}].certificate")
            partner_auto_refresh=$(bashio::config "replication.partners[${i}].automatic_refresh")

            if [[ -n "${partner_origin}" ]] && [[ -n "${partner_cert}" ]]; then
                bashio::log.info "Adding replication partner: ${partner_origin}"
                cat >> /config/config/server.toml <<EOF

[replication."${partner_origin}"]
type = "mutual-pull"
partner_cert = """${partner_cert}"""
EOF
                # Add automatic_refresh if enabled for this partner
                if [[ "${partner_auto_refresh}" == "true" ]]; then
                    bashio::log.info "  - Automatic refresh enabled for ${partner_origin} (this node acts as secondary)"
                    cat >> /config/config/server.toml <<EOF
automatic_refresh = true
EOF
                else
                    bashio::log.info "  - Automatic refresh disabled for ${partner_origin} (this node acts as primary)"
                fi
            else
                bashio::log.warning "Replication partner ${i} has missing origin or certificate, skipping"
            fi
        done
    else
        bashio::log.warning "Replication enabled but no partners configured"
    fi
else
    bashio::log.info "Replication is disabled"
fi

bashio::log.debug "Server configuration generated"

# Entry management migrations directory
# Place HJSON/JSON files here (e.g. 10-homeassistant.hjson) to provision
# OAuth2 clients, groups, and users declaratively on server startup.
MIGRATIONS_DIR="/config/kanidm/migrations.d"
mkdir -p "${MIGRATIONS_DIR}"
cat >> /config/config/server.toml <<EOF

migration_path = "${MIGRATIONS_DIR}"
EOF
bashio::log.info "Entry management: migrations directory = ${MIGRATIONS_DIR}"

# Directory Sync Configuration (LDAP and FreeIPA)
if [[ "${ENABLE_LDAP_SYNC}" == "true" ]]; then
    bashio::log.info "Directory Sync is enabled - configuring sync sources..."
    mkdir -p /config/sync

    # Function to generate LDAP/FreeIPA sync config file from array entry
    generate_sync_config() {
        local idx=$1
        local enabled=$(bashio::config "directory_sync.sources[${idx}].enabled")

        if [[ "${enabled}" != "true" ]]; then
            bashio::log.debug "Sync source ${idx} is disabled, skipping"
            return 0
        fi

        # Read common config values
        local name=$(bashio::config "directory_sync.sources[${idx}].name")
        local sync_type=$(bashio::config "directory_sync.sources[${idx}].sync_type")
        local sync_token=$(bashio::config "directory_sync.sources[${idx}].sync_token")
        local schedule=$(bashio::config "directory_sync.sources[${idx}].schedule")

        # Read LDAP-specific fields
        local ldap_uri=$(bashio::config "directory_sync.sources[${idx}].ldap_uri")
        local ldap_ca=$(bashio::config "directory_sync.sources[${idx}].ldap_ca")
        local ldap_sync_dn=$(bashio::config "directory_sync.sources[${idx}].ldap_sync_dn")
        local ldap_sync_pw=$(bashio::config "directory_sync.sources[${idx}].ldap_sync_pw")
        local ldap_sync_base_dn=$(bashio::config "directory_sync.sources[${idx}].ldap_sync_base_dn")
        local ldap_filter=$(bashio::config "directory_sync.sources[${idx}].ldap_filter")
        local person_objectclass=$(bashio::config "directory_sync.sources[${idx}].person_objectclass")
        local person_attr_id=$(bashio::config "directory_sync.sources[${idx}].person_attr_id")
        local person_attr_displayname=$(bashio::config "directory_sync.sources[${idx}].person_attr_displayname")
        local person_attr_mail=$(bashio::config "directory_sync.sources[${idx}].person_attr_mail")
        local group_objectclass=$(bashio::config "directory_sync.sources[${idx}].group_objectclass")
        local group_attr_name=$(bashio::config "directory_sync.sources[${idx}].group_attr_name")
        local group_attr_member=$(bashio::config "directory_sync.sources[${idx}].group_attr_member")

        # Read FreeIPA-specific fields
        local ipa_uri=$(bashio::config "directory_sync.sources[${idx}].ipa_uri")
        local ipa_ca=$(bashio::config "directory_sync.sources[${idx}].ipa_ca")
        local ipa_sync_dn=$(bashio::config "directory_sync.sources[${idx}].ipa_sync_dn")
        local ipa_sync_pw=$(bashio::config "directory_sync.sources[${idx}].ipa_sync_pw")
        local ipa_sync_base_dn=$(bashio::config "directory_sync.sources[${idx}].ipa_sync_base_dn")

        # Read FreeIPA advanced options
        local skip_invalid_password_formats=$(bashio::config "directory_sync.sources[${idx}].skip_invalid_password_formats")
        local sync_password_as_unix_password=$(bashio::config "directory_sync.sources[${idx}].sync_password_as_unix_password")
        local status_bind=$(bashio::config "directory_sync.sources[${idx}].status_bind")
        local exclude_entries=$(bashio::config "directory_sync.sources[${idx}].exclude_entries")
        local map_uuid=$(bashio::config "directory_sync.sources[${idx}].map_uuid")
        local map_name=$(bashio::config "directory_sync.sources[${idx}].map_name")
        local map_gidnumber=$(bashio::config "directory_sync.sources[${idx}].map_gidnumber")
        local map_uidnumber=$(bashio::config "directory_sync.sources[${idx}].map_uidnumber")

        # Validate common required fields
        if [[ -z "${name}" ]]; then
            bashio::log.error "Sync source ${idx}: name is required but empty"
            return 1
        fi
        if [[ -z "${sync_token}" ]]; then
            bashio::log.error "Sync source ${idx} (${name}): sync_token is required but empty"
            return 1
        fi
        if [[ -z "${sync_type}" ]]; then
            bashio::log.error "Sync source ${idx} (${name}): sync_type is required but empty"
            return 1
        fi

        # Validate type-specific required fields
        if [[ "${sync_type}" == "ldap" ]]; then
            if [[ -z "${ldap_uri}" ]]; then
                bashio::log.error "LDAP sync source ${idx} (${name}): ldap_uri is required but empty"
                return 1
            fi
            # Validate LDAP URI format
            if ! validate_uri "${ldap_uri}" "ldap_uri for sync source '${name}'"; then
                bashio::log.error "LDAP sync source ${idx} (${name}): invalid ldap_uri"
                return 1
            fi
            if [[ -z "${ldap_sync_dn}" ]]; then
                bashio::log.error "LDAP sync source ${idx} (${name}): ldap_sync_dn is required but empty"
                return 1
            fi
            if [[ -z "${ldap_sync_pw}" ]]; then
                bashio::log.error "LDAP sync source ${idx} (${name}): ldap_sync_pw is required but empty"
                return 1
            fi
            if [[ -z "${ldap_sync_base_dn}" ]]; then
                bashio::log.error "LDAP sync source ${idx} (${name}): ldap_sync_base_dn is required but empty"
                return 1
            fi
        elif [[ "${sync_type}" == "ipa" ]]; then
            if [[ -z "${ipa_uri}" ]]; then
                bashio::log.error "FreeIPA sync source ${idx} (${name}): ipa_uri is required but empty"
                return 1
            fi
            # Validate IPA URI format
            if ! validate_uri "${ipa_uri}" "ipa_uri for sync source '${name}'"; then
                bashio::log.error "FreeIPA sync source ${idx} (${name}): invalid ipa_uri"
                return 1
            fi
            if [[ -z "${ipa_sync_dn}" ]]; then
                bashio::log.error "FreeIPA sync source ${idx} (${name}): ipa_sync_dn is required but empty"
                return 1
            fi
            if [[ -z "${ipa_sync_pw}" ]]; then
                bashio::log.error "FreeIPA sync source ${idx} (${name}): ipa_sync_pw is required but empty"
                return 1
            fi
            if [[ -z "${ipa_sync_base_dn}" ]]; then
                bashio::log.error "FreeIPA sync source ${idx} (${name}): ipa_sync_base_dn is required but empty"
                return 1
            fi
        else
            bashio::log.error "Sync source ${idx} (${name}): invalid sync_type '${sync_type}' (must be 'ldap' or 'ipa')"
            return 1
        fi

        # Route to appropriate config generator based on type
        if [[ "${sync_type}" == "ldap" ]]; then
            # Handle LDAP CA certificate path
            local ca_path=""
            if [[ -n "${ldap_ca}" ]]; then
                # If absolute path, use as-is; otherwise treat as relative to /ssl/
                if [[ "${ldap_ca}" == /* ]]; then
                    ca_path="${ldap_ca}"
                else
                    # Validate safe path before using
                    if ! validate_safe_path "${ldap_ca}" "/ssl" "ldap_ca for sync source '${name}'"; then
                        bashio::log.error "LDAP sync source ${idx} (${name}): invalid CA certificate path"
                        return 1
                    fi
                    ca_path="/ssl/${ldap_ca}"
                fi
                if [[ ! -f "${ca_path}" ]]; then
                    bashio::log.error "LDAP sync source ${idx} (${name}): CA certificate not found at ${ca_path}"
                    return 1
                fi
            else
                bashio::log.warning "LDAP sync source ${idx} (${name}): No CA certificate specified - LDAPS may fail"
            fi

            bashio::log.info "Generating LDAP sync config for source ${idx}: ${name}"

            # Generate the ldap-sync config file
            cat > "/config/sync/ldap-sync-${name}.toml" <<EOF
[ldap_sync]
sync_token = "${sync_token}"
schedule = "${schedule}"
ldap_uri = "${ldap_uri}"
EOF

            # Add CA certificate if specified
            if [[ -n "${ca_path}" ]]; then
                echo "ldap_ca = \"${ca_path}\"" >> "/config/sync/ldap-sync-${name}.toml"
            fi

            # Continue with rest of LDAP config
            cat >> "/config/sync/ldap-sync-${name}.toml" <<EOF
ldap_sync_dn = "${ldap_sync_dn}"
ldap_sync_pw = "${ldap_sync_pw}"
ldap_sync_base_dn = "${ldap_sync_base_dn}"
ldap_filter = "${ldap_filter}"
person_objectclass = "${person_objectclass}"
person_attr_id = "${person_attr_id}"
person_attr_displayname = "${person_attr_displayname}"
person_attr_mail = "${person_attr_mail}"
group_objectclass = "${group_objectclass}"
group_attr_name = "${group_attr_name}"
group_attr_member = "${group_attr_member}"
EOF

            bashio::log.info "LDAP sync config generated: /config/sync/ldap-sync-${name}.toml"

        elif [[ "${sync_type}" == "ipa" ]]; then
            # Handle FreeIPA CA certificate path
            local ca_path=""
            if [[ -n "${ipa_ca}" ]]; then
                # If absolute path, use as-is; otherwise treat as relative to /ssl/
                if [[ "${ipa_ca}" == /* ]]; then
                    ca_path="${ipa_ca}"
                else
                    # Validate safe path before using
                    if ! validate_safe_path "${ipa_ca}" "/ssl" "ipa_ca for sync source '${name}'"; then
                        bashio::log.error "FreeIPA sync source ${idx} (${name}): invalid CA certificate path"
                        return 1
                    fi
                    ca_path="/ssl/${ipa_ca}"
                fi
                if [[ ! -f "${ca_path}" ]]; then
                    bashio::log.error "FreeIPA sync source ${idx} (${name}): CA certificate not found at ${ca_path}"
                    return 1
                fi
            else
                bashio::log.warning "FreeIPA sync source ${idx} (${name}): No CA certificate specified - LDAPS may fail"
            fi

            bashio::log.info "Generating FreeIPA sync config for source ${idx}: ${name}"

            # Generate the ipa-sync config file
            cat > "/config/sync/ipa-sync-${name}.toml" <<EOF
[ipa_sync]
sync_token = "${sync_token}"
schedule = "${schedule}"
ipa_uri = "${ipa_uri}"
EOF

            # Add CA certificate if specified
            if [[ -n "${ca_path}" ]]; then
                echo "ipa_ca = \"${ca_path}\"" >> "/config/sync/ipa-sync-${name}.toml"
            fi

            # Continue with rest of FreeIPA config
            cat >> "/config/sync/ipa-sync-${name}.toml" <<EOF
ipa_sync_dn = "${ipa_sync_dn}"
ipa_sync_pw = "${ipa_sync_pw}"
ipa_sync_base_dn = "${ipa_sync_base_dn}"
EOF

            # Add FreeIPA advanced options if enabled
            if [[ "${skip_invalid_password_formats}" == "true" ]]; then
                echo "skip_invalid_password_formats = true" >> "/config/sync/ipa-sync-${name}.toml"
            fi
            if [[ "${sync_password_as_unix_password}" == "true" ]]; then
                echo "sync_password_as_unix_password = true" >> "/config/sync/ipa-sync-${name}.toml"
            fi
            if [[ -n "${status_bind}" ]]; then
                echo "status_bind = \"${status_bind}\"" >> "/config/sync/ipa-sync-${name}.toml"
            fi

            # Add per-entry customization if provided (advanced feature)
            # Note: These expect comma-separated syncuuid:value pairs
            if [[ -n "${exclude_entries}" ]]; then
                echo "" >> "/config/sync/ipa-sync-${name}.toml"
                echo "# Per-entry exclusions (syncuuid)" >> "/config/sync/ipa-sync-${name}.toml"
                echo "exclude = [${exclude_entries}]" >> "/config/sync/ipa-sync-${name}.toml"
            fi
            if [[ -n "${map_uuid}" ]]; then
                echo "" >> "/config/sync/ipa-sync-${name}.toml"
                echo "# UUID remapping (syncuuid:new_uuid)" >> "/config/sync/ipa-sync-${name}.toml"
                echo "map_uuid = [${map_uuid}]" >> "/config/sync/ipa-sync-${name}.toml"
            fi
            if [[ -n "${map_name}" ]]; then
                echo "map_name = [${map_name}]" >> "/config/sync/ipa-sync-${name}.toml"
            fi
            if [[ -n "${map_gidnumber}" ]]; then
                echo "map_gidnumber = [${map_gidnumber}]" >> "/config/sync/ipa-sync-${name}.toml"
            fi
            if [[ -n "${map_uidnumber}" ]]; then
                echo "map_uidnumber = [${map_uidnumber}]" >> "/config/sync/ipa-sync-${name}.toml"
            fi

            bashio::log.info "FreeIPA sync config generated: /config/sync/ipa-sync-${name}.toml"
        fi

        return 0
    }

    # Get array length and generate configs for all sources
    SYNC_CONFIG_ERRORS=0
    source_count=$(bashio::config 'directory_sync.sources | length')

    for ((i=0; i<source_count; i++)); do
        if ! generate_sync_config $i; then
            SYNC_CONFIG_ERRORS=$((SYNC_CONFIG_ERRORS + 1))
        fi
    done

    if [ $SYNC_CONFIG_ERRORS -gt 0 ]; then
        bashio::log.error "Failed to generate ${SYNC_CONFIG_ERRORS} directory sync configuration(s)"
        bashio::log.error "Directory sync will not be started due to configuration errors"
        ENABLE_LDAP_SYNC="false"
    else
        bashio::log.info "Directory sync configuration completed successfully"
    fi
else
    bashio::log.info "Directory Sync is disabled"
fi

# Check if this is first run (admin account needs recovery)
bashio::log.info "Checking for first-run marker file: /config/.admin_initialized"
bashio::log.info "Checking for database file: /data/kanidm.db"

if [[ -f /data/kanidm.db ]]; then
    bashio::log.info "Database file EXISTS"
    ls -lh /data/kanidm.db 2>&1 | while IFS= read -r line; do bashio::log.info "  $line"; done
else
    bashio::log.info "Database file DOES NOT EXIST"
fi

# ==========================================
# START KANIDM SERVER & INITIALIZE DATABASE
# ==========================================

bashio::log.info "Starting Kanidm server (running as root for volume access)..."
bashio::log.info ""
bashio::log.info "=========================================="
bashio::log.info "EXPECTED WARNINGS FROM KANIDM"
bashio::log.info "=========================================="
bashio::log.info "You will see warnings from kanidm about file"
bashio::log.info "permissions and ownership. These are expected"
bashio::log.info "due to Home Assistant's volume mount system and"
bashio::log.info "are SAFE to ignore."
bashio::log.info "=========================================="
bashio::log.info ""

# Initialize database using modular function
if ! init_database "/config/config/server.toml" "$WEB_PORT" "$FIRST_RUN"; then
    bashio::log.fatal "Failed to initialize database"
    exit 1
fi

# KANIDM_PID is set by init_database
bashio::log.info "Kanidm server running (PID: ${KANIDM_PID})"

# ==========================================
# FIRST RUN: INITIALIZE ACCOUNTS
# ==========================================

if [ "$FIRST_RUN" = true ]; then
    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info "FIRST RUN INITIALIZATION"
    bashio::log.info "=========================================="
    
    # ADMIN_PASSWORD and IDM_ADMIN_PASSWORD are exported by init_database
    
    # Initialize idm_admin session (with retry logic for expect authentication)
    bashio::log.info ""
    bashio::log.info "Creating user accounts..."
    
    if ! init_idm_admin "https://localhost:${WEB_PORT}" "${IDM_ADMIN_PASSWORD}" "/root" 3; then
        bashio::log.fatal "Failed to initialize idm_admin session"
        kill "$KANIDM_PID" 2>/dev/null || true
        exit 1
    fi
    
    # Initialize person account
    if ! init_person "${PERSON_USERNAME}" "${PERSON_DISPLAYNAME}" 86400; then
        bashio::log.fatal "Failed to initialize person account"
        kill "$KANIDM_PID" 2>/dev/null || true
        exit 1
    fi
    
    # ==========================================
    # HOME ASSISTANT OAUTH2 GROUP (First Run Only)
    # ==========================================
    
    bashio::log.info ""
    bashio::log.info "Setting up Home Assistant OAuth2 integration..."

    # ==========================================
    # Detect Home Assistant HTTPS Configuration
    # ==========================================

    bashio::log.info "Detecting Home Assistant connection scheme..."
    if curl -sk https://homeassistant:8123 >/dev/null 2>&1; then
        HA_SCHEME="https"
        bashio::log.info "  ✓ Home Assistant using HTTPS"
    else
        HA_SCHEME="http"
        bashio::log.info "  ✓ Home Assistant using HTTP"
    fi

    # ==========================================
    # Get Dynamic Addon Hostname
    # ==========================================

    bashio::log.info "Retrieving addon hostname from Supervisor..."
    ADDON_HOSTNAME=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        http://supervisor/addons/self/info 2>/dev/null | jq -r '.data.hostname // "local-kanidm"')
    bashio::log.info "  ✓ Addon hostname: ${ADDON_HOSTNAME}"

    # ==========================================
    # Build OAuth2 URLs
    # ==========================================

    # Kanidm acts as the OIDC Provider (Issuer)
    KANIDM_ORIGIN="https://${ADDON_HOSTNAME}:${WEB_PORT}"

    # Home Assistant acts as the OIDC Client (Relying Party)
    HA_ORIGIN="${HA_SCHEME}://homeassistant:8123"

    bashio::log.info "OAuth2 configuration:"
    bashio::log.info "  Kanidm (Issuer):        ${KANIDM_ORIGIN}"
    bashio::log.info "  Home Assistant (Client): ${HA_ORIGIN}"
    bashio::log.info "  Callback URL:            ${HA_ORIGIN}/auth/oidc/callback"

    # ==========================================
    # Export Variables for ha_group.sh
    # ==========================================

    # Export variables needed by ha_group.sh
    export PERSON_USERNAME="${PERSON_USERNAME}"
    export KANIDM_ORIGIN="${KANIDM_ORIGIN}"
    export HA_ORIGIN="${HA_ORIGIN}"
    export ORIGIN="${KANIDM_ORIGIN}"  # Backward compatibility
    export HOME="/root"
    export KANIDM_URL="https://localhost:${WEB_PORT}"
    export KANIDM_SKIP_HOSTNAME_VERIFICATION="true"
    export KANIDM_ACCEPT_INVALID_CERTS="true"
    
    # Run the setup script (non-fatal - just a convenience feature)
    if /usr/local/lib/kanidm/ha_group.sh; then
        bashio::log.info "✓ Home Assistant OAuth2 integration available"
    else
        bashio::log.warning "Home Assistant OAuth2 setup encountered issues (non-fatal)"
        bashio::log.warning "You can configure OAuth2 manually later if needed"
    fi
    
    # ==========================================
    # MARK FIRST RUN COMPLETE
    # ==========================================
    
    # Initialize marker file with version tracking
    init_marker_file || {
        bashio::log.error "Failed to initialize marker file"
        kill "$KANIDM_PID" 2>/dev/null || true
        exit 1
    }
    
    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info "FIRST RUN INITIALIZATION COMPLETE!"
    bashio::log.info "=========================================="
    
else
    # Not first run - update marker file
    bashio::log.info "Updating installation marker..."
    update_marker_file || {
        bashio::log.warning "Failed to update marker file (non-fatal)"
    }
fi

bashio::log.debug "DEBUG: Exited first run block, proceeding to setup LDAP sync cron..."

# Setup Directory Sync cron jobs (LDAP and FreeIPA)
if [[ "${ENABLE_LDAP_SYNC}" == "true" ]]; then
    bashio::log.info "Setting up directory sync cron jobs..."

    # Install cron if not already installed
    if ! command -v crontab &> /dev/null; then
        bashio::log.info "Installing cron..."
        apk add --no-cache cronie
    fi

    # Create cron directory for logs
    mkdir -p /var/log/kanidm-sync

    # Clear existing crontab
    crontab -r 2>/dev/null || true

    # Build crontab with entries for each enabled sync source
    CRON_ENTRIES=0
    source_count=$(bashio::config 'directory_sync.sources | length')

    for ((i=0; i<source_count; i++)); do
        enabled=$(bashio::config "directory_sync.sources[${i}].enabled")
        if [[ "${enabled}" == "true" ]]; then
            name=$(bashio::config "directory_sync.sources[${i}].name")
            sync_type=$(bashio::config "directory_sync.sources[${i}].sync_type")

            if [[ "${sync_type}" == "ldap" ]] && [[ -f "/config/sync/ldap-sync-${name}.toml" ]]; then
                # Add cron entry for LDAP sync source
                bashio::log.info "Adding cron job for LDAP sync source: ${name}"
                (crontab -l 2>/dev/null || true; echo "*/10 * * * * /usr/local/bin/kanidm-sync -c /config/sync/ldap-sync-${name}.toml >> /var/log/kanidm-sync/ldap-${name}.log 2>&1") | crontab -
                CRON_ENTRIES=$((CRON_ENTRIES + 1))

            elif [[ "${sync_type}" == "ipa" ]] && [[ -f "/config/sync/ipa-sync-${name}.toml" ]]; then
                # Add cron entry for FreeIPA sync source
                bashio::log.info "Adding cron job for FreeIPA sync source: ${name}"
                (crontab -l 2>/dev/null || true; echo "*/10 * * * * /usr/local/bin/kanidm-ipa-sync -c /config/sync/ipa-sync-${name}.toml >> /var/log/kanidm-sync/ipa-${name}.log 2>&1") | crontab -
                CRON_ENTRIES=$((CRON_ENTRIES + 1))
            fi
        fi
    done

    if [ $CRON_ENTRIES -gt 0 ]; then
        # Start cron daemon
        bashio::log.info "Starting cron daemon for ${CRON_ENTRIES} directory sync source(s)..."
        crond -b -l 2
        bashio::log.info "Directory sync cron jobs configured and running"
        bashio::log.info "Sync logs available in /var/log/kanidm-sync/"
    else
        bashio::log.warning "Directory sync enabled but no sources are configured"
    fi
else
    bashio::log.debug "Directory sync disabled, skipping cron setup"
fi

bashio::log.debug "DEBUG: Proceeding to setup automatic backups..."

# Setup automatic database backups
if [[ "${ENABLE_BACKUP}" == "true" ]]; then
    bashio::log.info "Setting up automatic database backups..."

    # Create backup directory in /config (addon_config - survives reinstall and included in HA backups)
    mkdir -p /config/backups
    bashio::log.info "Backup directory created: /config/backups/"

    # Create backup script
    cat > /usr/local/bin/backup_kanidm.sh <<'BACKUP_SCRIPT'
#!/bin/bash
set -e

# Configuration
BACKUP_DIR="/config/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/kanidm_backup_${TIMESTAMP}.json"
BACKUP_VERSIONS=${1:-7}
LOG_TAG="kanidm-backup"

# Log function for consistent logging
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a /var/log/kanidm-backup.log
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a /var/log/kanidm-backup.log >&2
}

log_info "Starting Kanidm database backup..."

# Check if server is running
if ! curl -f -k -s https://localhost:4869/status > /dev/null 2>&1; then
    log_error "Kanidm server is not responding - backup aborted"
    exit 1
fi

# Perform online backup (JSON format - includes full database export)
log_info "Creating backup: ${BACKUP_FILE}"
if kanidmd database backup -c /config/config/server.toml "${BACKUP_FILE}" 2>&1 | tee -a /var/log/kanidm-backup.log; then
    log_info "Backup created successfully"

    # Verify backup file exists and has content
    if [[ -f "${BACKUP_FILE}" ]] && [[ -s "${BACKUP_FILE}" ]]; then
        BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        log_info "Backup size: ${BACKUP_SIZE}"
    else
        log_error "Backup file is empty or does not exist"
        exit 1
    fi
else
    log_error "Backup command failed"
    exit 1
fi

# Rotate old backups - keep only the most recent N versions
log_info "Rotating old backups (keeping ${BACKUP_VERSIONS} versions)..."
DELETED_COUNT=0
for old_backup in $(ls -t ${BACKUP_DIR}/kanidm_backup_*.json 2>/dev/null | tail -n +$((BACKUP_VERSIONS + 1))); do
    log_info "Deleting old backup: $(basename ${old_backup})"
    rm "${old_backup}"
    DELETED_COUNT=$((DELETED_COUNT + 1))
done

if [[ ${DELETED_COUNT} -gt 0 ]]; then
    log_info "Deleted ${DELETED_COUNT} old backup(s)"
else
    log_info "No old backups to delete"
fi

# Display current backup inventory
CURRENT_BACKUPS=$(ls -1 ${BACKUP_DIR}/kanidm_backup_*.json 2>/dev/null | wc -l)
log_info "Current backup count: ${CURRENT_BACKUPS}/${BACKUP_VERSIONS}"
log_info "Backup completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
BACKUP_SCRIPT

    chmod +x /usr/local/bin/backup_kanidm.sh
    bashio::log.info "Backup script created: /usr/local/bin/backup_kanidm.sh"

    # Ensure cron is installed
    if ! command -v crond &> /dev/null; then
        bashio::log.info "Installing cron..."
        apk add --no-cache cronie
    fi

    # Add backup cron job - write to Alpine's standard crontab location
    bashio::log.info "Configuring cron schedule: ${BACKUP_SCHEDULE}"
    CRON_FILE="/etc/crontabs/root"
    # Check if backup job already exists
    if [ -f "${CRON_FILE}" ]; then
        if ! grep -q "backup_kanidm.sh" "${CRON_FILE}" 2>/dev/null; then
            echo "${BACKUP_SCHEDULE} /usr/local/bin/backup_kanidm.sh ${BACKUP_VERSIONS} >> /var/log/kanidm-backup.log 2>&1" >> "${CRON_FILE}"
            bashio::log.info "Cron schedule added to existing crontab"
        else
            bashio::log.info "Backup cron job already exists"
        fi
    else
        echo "${BACKUP_SCHEDULE} /usr/local/bin/backup_kanidm.sh ${BACKUP_VERSIONS} >> /var/log/kanidm-backup.log 2>&1" > "${CRON_FILE}"
        bashio::log.info "Cron schedule configured successfully"
    fi

    # Ensure cron is running (may have been started by directory sync earlier)
    if ! pgrep crond > /dev/null; then
        bashio::log.info "Starting cron daemon for scheduled backups..."
        crond -b -l 2
    fi

    bashio::log.info "=========================================="
    bashio::log.info "AUTOMATIC BACKUPS CONFIGURED"
    bashio::log.info "=========================================="
    bashio::log.info "Schedule: ${BACKUP_SCHEDULE} (10 PM daily by default)"
    bashio::log.info "Location: /config/backups/"
    bashio::log.info "Retention: ${BACKUP_VERSIONS} versions"
    bashio::log.info "Format: JSON (kanidm_backup_YYYYMMDD_HHMMSS.json)"
    bashio::log.info ""
    bashio::log.info "Backups are stored in addon_config and will be"
    bashio::log.info "included in Home Assistant's automatic backups."
    bashio::log.info "=========================================="
else
    bashio::log.info "Automatic backups are disabled (enable_backup: false)"
fi

bashio::log.debug "DEBUG: Proceeding to bring server to foreground..."

# Bring server process to foreground
bashio::log.info "Kanidm running - bringing to foreground..."
bashio::log.info "Server PID: $KANIDM_PID"
wait $KANIDM_PID
