#!/bin/bash
# lib/init_person.sh
# Person account creation and credential reset token generation

# ==========================================
# PERSON ACCOUNT CREATION
# ==========================================

# Create person account
# Usage: create_person_account <username> <displayname>
# Returns: 0 on success, 1 on failure
# Note: Requires active idm_admin session (HOME/.cache/kanidm/tokens must exist)
create_person_account() {
    local username="$1"
    local displayname="$2"

    if [ -z "$username" ] || [ -z "$displayname" ]; then
        bashio::log.error "Usage: create_person_account <username> <displayname>"
        return 1
    fi

    bashio::log.info "Creating person account '${username}'..."
    bashio::log.debug "  Username: ${username}"
    bashio::log.debug "  Display Name: ${displayname}"

    # Create person account (authenticated via session token from idm_admin login)
    # This is the REAL test of whether authentication worked
    local output
    if output=$(kanidm person create "${username}" "${displayname}" 2>&1); then
        bashio::log.info "✓ Person account '${username}' created successfully"
        bashio::log.debug "${output}"

        # Allow transaction to complete before next operation
        sleep 0.5

        return 0
    else
        local exit_code=$?
        bashio::log.error "Failed to create person account '${username}' (exit code: ${exit_code})"
        bashio::log.error "Details: ${output}"
        return 1
    fi
}

# ==========================================
# GROUP MEMBERSHIP
# ==========================================

# Add person to admin groups
# Usage: add_person_to_admin_groups <username>
# Returns: 0 on success (non-fatal on individual group failures)
add_person_to_admin_groups() {
    local username="$1"

    if [ -z "$username" ]; then
        bashio::log.error "Usage: add_person_to_admin_groups <username>"
        return 1
    fi

    bashio::log.info "Adding '${username}' to admin groups..."

    local groups="idm_admins idm_people_admins idm_group_admins"
    local success_count=0
    local fail_count=0

    for group in $groups; do
        bashio::log.debug "Adding '${username}' to group '${group}'..."

        local output_group
        if output_group=$(kanidm group add-members "${group}" "${username}" 2>&1); then
            bashio::log.info "✓ Added '${username}' to group '${group}'"
            bashio::log.debug "${output_group}"
            success_count=$((success_count + 1))

            # Brief delay between group operations
            sleep 0.3
        else
            bashio::log.warning "Failed to add '${username}' to group '${group}'"
            bashio::log.warning "Details: ${output_group}"
            fail_count=$((fail_count + 1))
        fi
    done

    bashio::log.debug "Group membership assignment completed: ${success_count} succeeded, ${fail_count} failed"

    if [ $success_count -eq 0 ]; then
        bashio::log.error "Failed to add user to any admin groups"
        return 1
    fi

    return 0
}

# ==========================================
# CREDENTIAL RESET TOKEN
# ==========================================

# Generate credential reset token for person account
# Usage: generate_reset_token <username> [validity_seconds]
# Returns: 0 on success, 1 on failure
# Outputs: Displays reset token information to user
generate_reset_token() {
    local username="$1"
    local validity_seconds="${2:-86400}"  # Default: 24 hours

    if [ -z "$username" ]; then
        bashio::log.error "Usage: generate_reset_token <username> [validity_seconds]"
        return 1
    fi

    bashio::log.info "Generating credential reset token for '${username}'..."
    bashio::log.debug "  Token validity: ${validity_seconds} seconds"

    local reset_token_output
    reset_token_output=$(kanidm person credential create-reset-token "${username}" ${validity_seconds} 2>&1)
    local reset_token_exit=$?

    if [ ${reset_token_exit} -ne 0 ]; then
        bashio::log.error "Failed to create reset token for '${username}'"
        bashio::log.error "Token creation output: ${reset_token_output}"
        return 1
    fi

    # Display the complete reset token output (includes QR code, link, and command)
    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info "CREDENTIAL RESET TOKEN GENERATED"
    bashio::log.info "=========================================="
    bashio::log.info ""
    echo "${reset_token_output}" | while IFS= read -r line; do
        bashio::log.warning "$line"
    done
    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info "IMPORTANT: Use one of the methods above to"
    bashio::log.info "set your password. This token expires in"
    bashio::log.info "$((validity_seconds / 3600)) hours."
    bashio::log.info "=========================================="

    return 0
}

# ==========================================
# MAIN INITIALIZATION FUNCTION
# ==========================================

# Initialize person account (create, add to groups, generate reset token)
# Usage: init_person <username> <displayname> [token_validity_seconds]
# Returns: 0 on success, 1 on failure
# Note: Requires active idm_admin session
init_person() {
    local username="$1"
    local displayname="$2"
    local token_validity="${3:-86400}"

    # Validate parameters
    if [ -z "$username" ] || [ -z "$displayname" ]; then
        bashio::log.error "Usage: init_person <username> <displayname> [token_validity_seconds]"
        return 1
    fi

    bashio::log.info ""
    bashio::log.info "Initializing person account..."

    # Create person account
    if ! create_person_account "$username" "$displayname"; then
        bashio::log.error "Person account creation failed"
        return 1
    fi

    # Add to admin groups (non-fatal if some fail)
    if ! add_person_to_admin_groups "$username"; then
        bashio::log.warning "Failed to add person to all admin groups"
        bashio::log.warning "User may have limited administrative permissions"
        # Continue anyway - user was created successfully
    fi

    # Generate credential reset token
    if ! generate_reset_token "$username" "$token_validity"; then
        bashio::log.error "Failed to generate credential reset token"
        bashio::log.error "You will need to create a reset token manually:"
        bashio::log.error "  kanidm person credential create-reset-token ${username} 86400"
        return 1
    fi

    # Display success summary
    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info "USER ACCOUNT CREATED SUCCESSFULLY!"
    bashio::log.info "=========================================="
    bashio::log.info "Person Account:"
    bashio::log.info "  Username: ${username}"
    bashio::log.info "  Display Name: ${displayname}"
    bashio::log.info ""
    bashio::log.info "=========================================="
    bashio::log.info "Log in with person account to use Kanidm!"
    bashio::log.info "=========================================="

    return 0
}

# Export functions
export -f create_person_account
export -f add_person_to_admin_groups
export -f generate_reset_token
export -f init_person
