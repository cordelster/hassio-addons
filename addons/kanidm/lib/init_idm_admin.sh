#!/bin/bash
# lib/init_idm_admin.sh
# Initialize idm_admin session with retry logic for expect-based authentication

# ==========================================
# CLIENT CONFIG SETUP
# ==========================================

# Create kanidm client configuration
# Usage: setup_kanidm_client_config
# Returns: 0 on success, 1 on failure
setup_kanidm_client_config() {
    local kanidm_url="$1"
    local home_dir="${2:-/root}"

    bashio::log.debug "Creating kanidm client config at /etc/kanidm/config..."

    # Create directories
    mkdir -p /etc/kanidm
    mkdir -p "${home_dir}/.cache/kanidm"
    chmod 755 "${home_dir}/.cache"
    chmod 755 "${home_dir}/.cache/kanidm"

    # Write config file
    cat > /etc/kanidm/config << EOF
uri = "${kanidm_url}"
verify_ca = false
verify_hostnames = false
EOF

    if [ $? -ne 0 ]; then
        bashio::log.error "Failed to create client config"
        return 1
    fi

    chmod 644 /etc/kanidm/config

    bashio::log.debug "✓ Client config created at /etc/kanidm/config"
    bashio::log.debug "  uri = ${kanidm_url}"
    bashio::log.debug "  Tokens will be stored in: ${home_dir}/.cache/kanidm/tokens"

    return 0
}

# ==========================================
# EXPECT-BASED LOGIN (SINGLE ATTEMPT)
# ==========================================

# Attempt single login via expect
# Usage: try_idm_admin_login <kanidm_url> <password> <home_dir>
# Returns: 0 on success, 1 on failure
try_idm_admin_login() {
    local kanidm_url="$1"
    local idm_admin_password="$2"
    local home_dir="${3:-/root}"

    bashio::log.debug "Attempting idm_admin login..."
    bashio::log.debug "  Token cache directory: ${home_dir}/.cache/kanidm"

    # Run expect login
    local expect_output
    expect_output=$(expect -d << EOF
set timeout 15
set env(HOME) "${home_dir}"
exp_internal 1
spawn kanidm login -H ${kanidm_url} --accept-invalid-certs --skip-hostname-verification -D idm_admin
expect "Enter password:"
send "${idm_admin_password}\r"

# Wait for completion with full debug output
expect {
    -re "Login Success" {
        puts "\nLOGIN_SUCCESSFUL"
    }
    eof {
        puts "\nEOF_RECEIVED"
    }
    timeout {
        puts "\nLOGIN_TIMEOUT"
    }
}
EOF
)
    local expect_exit_code=$?

    bashio::log.debug "Expect completed with exit code: ${expect_exit_code}"

    # Check exit code
    if [ ${expect_exit_code} -ne 0 ]; then
        bashio::log.debug "Expect login failed"
        bashio::log.debug "Expect output: ${expect_output}"
        return 1
    fi

    # Check if expect output indicates success
    if echo "${expect_output}" | grep -q "LOGIN_SUCCESSFUL"; then
        bashio::log.debug "✓ Expect reported LOGIN_SUCCESSFUL"
        return 0
    elif echo "${expect_output}" | grep -q "LOGIN_TIMEOUT"; then
        bashio::log.debug "✗ Expect login timed out"
        return 1
    elif echo "${expect_output}" | grep -q "EOF_RECEIVED"; then
        bashio::log.debug "✗ Expect received EOF (process ended unexpectedly)"
        return 1
    else
        # Unexpected output - assume failure
        bashio::log.debug "✗ Unexpected expect output - assuming failure"
        bashio::log.debug "Expect output: ${expect_output}"
        return 1
    fi
}

# ==========================================
# RETRY WRAPPER FOR LOGIN
# ==========================================

# Login as idm_admin with retry logic
# Usage: init_idm_admin_session <kanidm_url> <password> [home_dir] [max_attempts]
# Returns: 0 on success, 1 on failure
# Side effects: Sets up client config, creates session token
init_idm_admin_session() {
    local kanidm_url="$1"
    local idm_admin_password="$2"
    local home_dir="${3:-/root}"
    local max_attempts="${4:-3}"

    bashio::log.info "Logging in as idm_admin..."

    # Setup environment variables for kanidm CLI
    export HOME="${home_dir}"
    export KANIDM_URL="${kanidm_url}"
    export KANIDM_SKIP_HOSTNAME_VERIFICATION=true
    export KANIDM_ACCEPT_INVALID_CERTS=true

    bashio::log.debug "Environment variables:"
    bashio::log.debug "  HOME=${HOME}"
    bashio::log.debug "  KANIDM_URL=${KANIDM_URL}"

    # Create client config
    if ! setup_kanidm_client_config "$kanidm_url" "$home_dir"; then
        bashio::log.error "Failed to setup client config"
        return 1
    fi

    # Retry login attempts
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        bashio::log.debug "Login attempt ${attempt}/${max_attempts}..."

        if try_idm_admin_login "$kanidm_url" "$idm_admin_password" "$home_dir"; then
            bashio::log.info "Successfully logged in as idm_admin (attempt ${attempt}/${max_attempts})"

            # CRITICAL: Allow session/token to be fully established before next operation
            # Session creation happens asynchronously on the server side
            # Under load, this can take longer than 1s
            bashio::log.debug "Waiting for session establishment..."
            sleep 2

            return 0
        fi

        # Login failed, prepare for retry
        attempt=$((attempt + 1))

        if [ $attempt -le $max_attempts ]; then
            bashio::log.warning "Login attempt ${attempt-1} failed, retrying in 2 seconds..."
            sleep 2
        fi
    done

    # All attempts failed
    bashio::log.error "Failed to login as idm_admin after ${max_attempts} attempts"
    return 1
}

# ==========================================
# AUTHENTICATION POLICY CONFIGURATION
# ==========================================

# Configure authentication policy to allow password-only login
# Usage: configure_auth_policy
# Returns: 0 on success (non-fatal on failure)
configure_auth_policy() {
    bashio::log.info "Configuring authentication policy to allow password-only login..."

    bashio::log.debug "Environment check:"
    bashio::log.debug "  HOME=${HOME}"
    bashio::log.debug "  KANIDM_URL=${KANIDM_URL}"
    bashio::log.debug "  Token file exists: $([ -f ${HOME}/.cache/kanidm/tokens ] && echo 'yes' || echo 'NO')"

    # NOTE: The account-policy command syntax may have changed in newer Kanidm versions
    # This command often fails but is not critical - user creation still works
    local policy_output
    if policy_output=$(kanidm group account-policy credential-type-minimum idm_all_accounts any 2>&1); then
        bashio::log.info "✓ Configured password-only login policy"
        bashio::log.debug "Policy output: ${policy_output}"
        return 0
    else
        bashio::log.debug "Could not modify authentication policy (non-critical)"
        bashio::log.debug "Policy command output: ${policy_output}"
        return 0  # Non-fatal
    fi
}

# ==========================================
# MAIN INITIALIZATION FUNCTION
# ==========================================

# Initialize idm_admin session and configure authentication
# Usage: init_idm_admin <kanidm_url> <password> [home_dir] [max_attempts]
# Returns: 0 on success, 1 on failure
init_idm_admin() {
    local kanidm_url="$1"
    local idm_admin_password="$2"
    local home_dir="${3:-/root}"
    local max_attempts="${4:-3}"

    # Validate parameters
    if [ -z "$kanidm_url" ] || [ -z "$idm_admin_password" ]; then
        bashio::log.error "Usage: init_idm_admin <kanidm_url> <password> [home_dir] [max_attempts]"
        return 1
    fi

    # Login with retry logic
    if ! init_idm_admin_session "$kanidm_url" "$idm_admin_password" "$home_dir" "$max_attempts"; then
        bashio::log.error "Failed to initialize idm_admin session"
        return 1
    fi

    # Configure authentication policy (non-fatal)
    configure_auth_policy

    bashio::log.info "✓ idm_admin session initialized successfully"
    return 0
}

# Export functions
export -f setup_kanidm_client_config
export -f try_idm_admin_login
export -f init_idm_admin_session
export -f configure_auth_policy
export -f init_idm_admin
