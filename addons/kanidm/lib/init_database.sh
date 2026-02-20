#!/bin/bash
# lib/init_database.sh
# Database initialization, readiness checking, and admin account recovery

# Global variable for tracking Kanidm PID
KANIDM_PID=""

# ==========================================
# DATABASE STARTUP
# ==========================================

# Start Kanidm server in background
# Usage: start_kanidm_server <config_path>
# Returns: 0 on success, 1 on failure
# Sets: KANIDM_PID global variable
start_kanidm_server() {
    local config_path="$1"

    if [ -z "$config_path" ]; then
        bashio::log.error "Usage: start_kanidm_server <config_path>"
        return 1
    fi

    if [ ! -f "$config_path" ]; then
        bashio::log.error "Config file not found: ${config_path}"
        return 1
    fi

    bashio::log.info "Starting Kanidm server..."
    bashio::log.debug "  Config: ${config_path}"

    # Start server in background
    kanidmd server -c "$config_path" &
    KANIDM_PID=$!

    if [ -z "$KANIDM_PID" ]; then
        bashio::log.error "Failed to start Kanidm server"
        return 1
    fi

    bashio::log.debug "✓ Kanidm server started (PID: ${KANIDM_PID})"
    return 0
}

# ==========================================
# DATABASE READINESS CHECKS
# ==========================================

# Check if HTTP endpoint is ready
# Usage: wait_for_http_endpoint <port> [max_attempts]
# Returns: 0 if ready, 1 on timeout
wait_for_http_endpoint() {
    local port="$1"
    local max_attempts="${2:-30}"

    bashio::log.info "Waiting for Kanidm HTTP endpoint (port ${port})..."

    for i in $(seq 1 $max_attempts); do
        if curl -f -k -s "https://localhost:${port}/status" > /dev/null 2>&1; then
            bashio::log.info "✓ HTTP endpoint ready (attempt ${i}/${max_attempts})"
            return 0
        fi

        # Show progress every 5 seconds
        if [ $((i % 5)) -eq 0 ]; then
            bashio::log.debug "  Still waiting... (${i}/${max_attempts})"
        fi

        if [ $i -eq $max_attempts ]; then
            bashio::log.fatal "Kanidm HTTP endpoint failed to start within ${max_attempts} seconds"
            return 1
        fi

        sleep 1
    done

    return 1
}

# Check if database is operationally ready (can process requests)
# Usage: wait_for_database_operational <port> [max_attempts]
# Returns: 0 if ready, 1 on timeout
wait_for_database_operational() {
    local port="$1"
    local max_attempts="${2:-20}"

    bashio::log.info "Verifying database operational readiness..."

    for i in $(seq 1 $max_attempts); do
        # Query an endpoint - even 401 (unauthorized) means database is operational
        # We're not looking for success, just that the database can process requests
        local http_code
        http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "https://localhost:${port}/v1/schema" 2>/dev/null)

        # 200 = success, 401 = unauthorized (but database is working!), 403 = forbidden (also working)
        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "401" ]] || [[ "$http_code" == "403" ]]; then
            bashio::log.info "✓ Database operationally ready (HTTP ${http_code})"
            return 0
        fi

        # Show progress
        bashio::log.debug "  Database not ready yet (HTTP ${http_code}, attempt ${i}/${max_attempts})"

        if [ $i -eq $max_attempts ]; then
            bashio::log.fatal "Database failed to become operationally ready within ${max_attempts} seconds"
            return 1
        fi

        sleep 1
    done

    return 1
}

# Enhanced database readiness check with multiple layers
# Usage: wait_for_database_ready <port> [http_timeout] [db_timeout] [settle_seconds]
# Returns: 0 if ready, 1 on timeout
# Note: HTTP endpoint being ready ≠ database being ready for operations
wait_for_database_ready() {
    local port="$1"
    local max_http_attempts="${2:-30}"
    local max_db_attempts="${3:-20}"
    local settle_seconds="${4:-3}"

    if [ -z "$port" ]; then
        bashio::log.error "Usage: wait_for_database_ready <port> [http_timeout] [db_timeout] [settle_seconds]"
        return 1
    fi

    # Layer 1: HTTP endpoint readiness
    if ! wait_for_http_endpoint "$port" "$max_http_attempts"; then
        return 1
    fi

    # Layer 2: Database operational readiness
    if ! wait_for_database_operational "$port" "$max_db_attempts"; then
        return 1
    fi

    # Layer 3: Settling time for database to complete internal startup tasks
    # (index building, transaction log replay, etc.)
    bashio::log.info "Allowing database settling time (${settle_seconds}s)..."
    sleep "$settle_seconds"

    bashio::log.info "✓ Kanidm fully ready for operations"
    return 0
}

# ==========================================
# ADMIN ACCOUNT RECOVERY
# ==========================================

# Recover admin account password
# Usage: recover_admin_account <config_path> <account_name>
# Returns: 0 on success, 1 on failure
# Outputs: Prints password to stdout
recover_admin_account() {
    local config_path="$1"
    local account_name="$2"

    if [ -z "$config_path" ] || [ -z "$account_name" ]; then
        bashio::log.error "Usage: recover_admin_account <config_path> <account_name>"
        return 1
    fi

    bashio::log.debug "Recovering account: ${account_name}..."

    # Recover account and extract password from JSON
    # Kanidm 1.9.0+ uses 'scripting recover-account' which outputs JSON by default
    local account_json
    account_json=$(kanidmd scripting recover-account -c "$config_path" "$account_name" 2>&1)

    if [ $? -ne 0 ]; then
        bashio::log.error "Failed to recover account: ${account_name}"
        bashio::log.error "Output: ${account_json}"
        return 1
    fi

    # Extract password from JSON output: {"status":"ok","output":"<password>"}
    local password
    password=$(echo "$account_json" | sed -n 's/.*"output": *"\([^"]*\)".*/\1/p')

    if [ -z "$password" ]; then
        bashio::log.error "Failed to extract password for: ${account_name}"
        bashio::log.error "JSON output: ${account_json}"
        return 1
    fi

    bashio::log.debug "✓ Account ${account_name} recovered (password length: ${#password})"

    # Output password to stdout for capture
    echo "$password"
    return 0
}

# Initialize admin accounts (recover passwords)
# Usage: init_admin_accounts <config_path>
# Returns: 0 on success, 1 on failure
# Sets: ADMIN_PASSWORD and IDM_ADMIN_PASSWORD environment variables
# Displays: Admin account credentials to user
init_admin_accounts() {
    local config_path="$1"

    if [ -z "$config_path" ]; then
        bashio::log.error "Usage: init_admin_accounts <config_path>"
        return 1
    fi

    bashio::log.info "Initializing admin accounts..."

    # Recover admin account (for system configuration)
    ADMIN_PASSWORD=$(recover_admin_account "$config_path" "admin")
    if [ $? -ne 0 ] || [ -z "$ADMIN_PASSWORD" ]; then
        bashio::log.error "Failed to recover admin account"
        return 1
    fi

    # Recover idm_admin account (for user/group management)
    IDM_ADMIN_PASSWORD=$(recover_admin_account "$config_path" "idm_admin")
    if [ $? -ne 0 ] || [ -z "$IDM_ADMIN_PASSWORD" ]; then
        bashio::log.error "Failed to recover idm_admin account"
        return 1
    fi

    # Export for use by other scripts
    export ADMIN_PASSWORD
    export IDM_ADMIN_PASSWORD

    # Display credentials to user
    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info "Admin accounts initialized successfully!"
    bashio::log.info "=========================================="
    bashio::log.info ""
    bashio::log.info "SYSTEM ADMIN (for server configuration):"
    bashio::log.info "  Username: admin"
    bashio::log.info "  Password: ${ADMIN_PASSWORD}"
    bashio::log.info ""
    bashio::log.info "IDENTITY ADMIN (for user/group management):"
    bashio::log.info "  Username: idm_admin"
    bashio::log.info "  Password: ${IDM_ADMIN_PASSWORD}"
    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info "NOTE: These service accounts are for system"
    bashio::log.info "administration only. Use your person account"
    bashio::log.info "for normal operations."
    bashio::log.info "=========================================="

    return 0
}

# ==========================================
# MAIN INITIALIZATION FUNCTION
# ==========================================

# Initialize Kanidm database (start server, wait for ready, recover admin accounts)
# Usage: init_database <config_path> <port> [first_run]
# Returns: 0 on success, 1 on failure
# Side effects: Starts Kanidm server, sets KANIDM_PID, ADMIN_PASSWORD, IDM_ADMIN_PASSWORD
init_database() {
    local config_path="$1"
    local port="$2"
    local first_run="${3:-false}"

    # Validate parameters
    if [ -z "$config_path" ] || [ -z "$port" ]; then
        bashio::log.error "Usage: init_database <config_path> <port> [first_run]"
        return 1
    fi

    # Start Kanidm server
    if ! start_kanidm_server "$config_path"; then
        bashio::log.error "Failed to start Kanidm server"
        return 1
    fi

    # Wait for database to be ready
    if ! wait_for_database_ready "$port"; then
        bashio::log.error "Database failed to become ready"
        # Kill the server process
        if [ -n "$KANIDM_PID" ]; then
            bashio::log.info "Stopping Kanidm server (PID: ${KANIDM_PID})..."
            kill "$KANIDM_PID" 2>/dev/null || true
        fi
        return 1
    fi

    # Initialize admin accounts if first run
    if [ "$first_run" = "true" ]; then
        if ! init_admin_accounts "$config_path"; then
            bashio::log.error "Failed to initialize admin accounts"
            # Kill the server process
            if [ -n "$KANIDM_PID" ]; then
                bashio::log.info "Stopping Kanidm server (PID: ${KANIDM_PID})..."
                kill "$KANIDM_PID" 2>/dev/null || true
            fi
            return 1
        fi
    fi

    bashio::log.info "✓ Database initialized successfully"
    return 0
}

# Export functions
export -f start_kanidm_server
export -f wait_for_http_endpoint
export -f wait_for_database_operational
export -f wait_for_database_ready
export -f recover_admin_account
export -f init_admin_accounts
export -f init_database
