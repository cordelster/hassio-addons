#!/bin/bash
# lib/version_mgmt.sh
# Version comparison, skip detection, and upgrade path generation

# Source detect_state for version extraction functions
# (will be sourced by run.sh which sources both)

# ==========================================
# VERSION COMPARISON
# ==========================================

# Parse semantic version into components
# Usage: parse_semantic_version "1.8.5"
# Sets: VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH
parse_semantic_version() {
    local version="$1"

    # Extract major.minor.patch
    VERSION_MAJOR=$(echo "$version" | cut -d. -f1)
    VERSION_MINOR=$(echo "$version" | cut -d. -f2)
    VERSION_PATCH=$(echo "$version" | cut -d. -f3 | cut -d'-' -f1)  # Remove any suffix

    # Validate extracted values
    if [ -z "$VERSION_MAJOR" ] || [ -z "$VERSION_MINOR" ]; then
        bashio::log.error "Failed to parse version: $version"
        return 1
    fi

    # Default patch to 0 if not present
    VERSION_PATCH="${VERSION_PATCH:-0}"
}

# Compare two semantic versions
# Usage: compare_versions "1.8.5" "1.9.0"
# Returns: 0 if equal, 1 if first > second, 2 if first < second
compare_versions() {
    local ver1="$1"
    local ver2="$2"

    # Parse first version
    parse_semantic_version "$ver1"
    local v1_major=$VERSION_MAJOR
    local v1_minor=$VERSION_MINOR
    local v1_patch=$VERSION_PATCH

    # Parse second version
    parse_semantic_version "$ver2"
    local v2_major=$VERSION_MAJOR
    local v2_minor=$VERSION_MINOR
    local v2_patch=$VERSION_PATCH

    # Compare major version
    if [ "$v1_major" -gt "$v2_major" ]; then
        return 1  # ver1 > ver2
    elif [ "$v1_major" -lt "$v2_major" ]; then
        return 2  # ver1 < ver2
    fi

    # Major versions equal, compare minor
    if [ "$v1_minor" -gt "$v2_minor" ]; then
        return 1  # ver1 > ver2
    elif [ "$v1_minor" -lt "$v2_minor" ]; then
        return 2  # ver1 < ver2
    fi

    # Major and minor equal, compare patch
    if [ "$v1_patch" -gt "$v2_patch" ]; then
        return 1  # ver1 > ver2
    elif [ "$v1_patch" -lt "$v2_patch" ]; then
        return 2  # ver1 < ver2
    fi

    # All equal
    return 0
}

# ==========================================
# VERSION SKIP DETECTION
# ==========================================

# Detect if Kanidm version skip is attempted
# Usage: detect_version_skip "1.5.0" "1.7.0"
# Returns: 0 if safe, 1 if skip detected
detect_version_skip() {
    local prev_version="$1"
    local curr_version="$2"

    bashio::log.debug "Checking for version skip: ${prev_version} → ${curr_version}"

    # Parse previous version
    parse_semantic_version "$prev_version"
    local prev_major=$VERSION_MAJOR
    local prev_minor=$VERSION_MINOR

    # Parse current version
    parse_semantic_version "$curr_version"
    local curr_major=$VERSION_MAJOR
    local curr_minor=$VERSION_MINOR

    # Check for major version skip (e.g., 1.x → 3.x)
    if [ "$curr_major" -gt "$((prev_major + 1))" ]; then
        bashio::log.error "Major version skip detected: ${prev_major}.x → ${curr_major}.x"
        return 1
    fi

    # Check for minor version skip within same major (e.g., 1.5 → 1.7)
    if [ "$curr_major" -eq "$prev_major" ] && [ "$curr_minor" -gt "$((prev_minor + 1))" ]; then
        bashio::log.error "Minor version skip detected: ${prev_major}.${prev_minor} → ${curr_major}.${curr_minor}"
        return 1
    fi

    # Patch version skips are ALLOWED (e.g., 1.8.3 → 1.8.7 is safe)
    bashio::log.debug "✓ Sequential upgrade detected (no skip)"
    return 0
}

# ==========================================
# UPGRADE PATH GENERATION
# ==========================================

# Generate required upgrade path for skipped versions
# Usage: generate_upgrade_path "1.5.0" "1.8.0"
generate_upgrade_path() {
    local from_version="$1"
    local to_version="$2"

    bashio::log.fatal ""
    bashio::log.fatal "=========================================="
    bashio::log.fatal "REQUIRED UPGRADE PATH"
    bashio::log.fatal "=========================================="
    bashio::log.fatal "From: ${from_version}"
    bashio::log.fatal "To: ${to_version}"
    bashio::log.fatal ""

    # Parse versions
    parse_semantic_version "$from_version"
    local from_major=$VERSION_MAJOR
    local from_minor=$VERSION_MINOR

    parse_semantic_version "$to_version"
    local to_major=$VERSION_MAJOR
    local to_minor=$VERSION_MINOR

    bashio::log.fatal "You must upgrade through each version:"

    # Handle major version transitions
    if [ "$to_major" -gt "$from_major" ]; then
        # Need to go through major version transitions
        for major in $(seq $from_major $((to_major - 1))); do
            local next_major=$((major + 1))
            bashio::log.fatal "  Step: ${major}.${from_minor}.x → ${major}.$((from_minor + 1)).x → ... → ${major}.9.x → ${next_major}.0.x"
            from_minor=0  # Reset minor for next major version
        done
    fi

    # Handle minor version transitions within final major version
    if [ "$to_minor" -gt "$from_minor" ]; then
        for minor in $(seq $from_minor $((to_minor - 1))); do
            local next_minor=$((minor + 1))
            bashio::log.fatal "  Step: ${to_major}.${minor}.x → ${to_major}.${next_minor}.x"
        done
    fi

    bashio::log.fatal ""
    bashio::log.fatal "Example sequential upgrade:"
    bashio::log.fatal "  1. Install addon with Kanidm ${from_version}"
    bashio::log.fatal "  2. Let it start and complete migration"
    bashio::log.fatal "  3. Install next version in sequence"
    bashio::log.fatal "  4. Repeat until you reach ${to_version}"
    bashio::log.fatal "=========================================="
}

# Handle version skip error (fatal)
# Usage: handle_version_skip "1.5.0" "1.8.0"
handle_version_skip() {
    local prev_version="$1"
    local curr_version="$2"

    bashio::log.fatal ""
    bashio::log.fatal "=========================================="
    bashio::log.fatal "UNSUPPORTED KANIDM UPGRADE DETECTED"
    bashio::log.fatal "=========================================="
    bashio::log.fatal "Previous version: ${prev_version}"
    bashio::log.fatal "Attempted version: ${curr_version}"
    bashio::log.fatal ""
    bashio::log.fatal "Kanidm requires SEQUENTIAL upgrades."
    bashio::log.fatal "Skipping versions will CORRUPT your database!"
    bashio::log.fatal ""

    # Generate upgrade path
    generate_upgrade_path "$prev_version" "$curr_version"

    bashio::log.fatal ""
    bashio::log.fatal "=========================================="
    bashio::log.fatal "INSTRUCTIONS TO FIX"
    bashio::log.fatal "=========================================="
    bashio::log.fatal "1. STOP - Do not start this addon version"
    bashio::log.fatal "2. Restore from backup (if available)"
    bashio::log.fatal "   Backup location: /config/backups/"
    bashio::log.fatal "3. Install intermediate addon versions:"
    bashio::log.fatal "   - Follow the upgrade path shown above"
    bashio::log.fatal "   - Install each version in sequence"
    bashio::log.fatal "   - Let each version complete startup before upgrading"
    bashio::log.fatal "4. Your database will be safely migrated"
    bashio::log.fatal ""
    bashio::log.fatal "DO NOT CONTINUE - Database corruption is likely!"
    bashio::log.fatal "=========================================="
    bashio::log.fatal ""

    # Exit with error
    exit 1
}

# ==========================================
# UPGRADE VALIDATION
# ==========================================

# Validate upgrade is safe
# Usage: validate_upgrade
# Returns: 0 if safe, exits on error
validate_upgrade() {
    local prev_kanidm_version=$(read_marker_field "KANIDM_VERSION")
    local curr_kanidm_version=$(get_kanidm_version)

    bashio::log.info "Validating upgrade path..."
    bashio::log.info "  Previous: ${prev_kanidm_version}"
    bashio::log.info "  Current: ${curr_kanidm_version}"

    # Check for version skip
    if ! detect_version_skip "$prev_kanidm_version" "$curr_kanidm_version"; then
        # Version skip detected - fatal error
        handle_version_skip "$prev_kanidm_version" "$curr_kanidm_version"
        # handle_version_skip exits, this line never reached
    fi

    bashio::log.info "✓ Upgrade path validated (sequential)"
    return 0
}

# Check if Kanidm major.minor version changed
# Returns: 0 if changed, 1 if same
check_kanidm_major_minor_change() {
    local prev_major_minor=$(read_marker_field "KANIDM_MAJOR_MINOR")
    local curr_major_minor=$(get_kanidm_major_minor)

    if [ -z "$prev_major_minor" ]; then
        # First run with version tracking
        bashio::log.debug "No previous Kanidm major.minor recorded"
        return 1  # Treat as "no change" for first run
    fi

    if [ "$prev_major_minor" != "$curr_major_minor" ]; then
        bashio::log.info "Kanidm major.minor changed: ${prev_major_minor} → ${curr_major_minor}"
        return 0  # Changed
    fi

    bashio::log.debug "Kanidm major.minor unchanged: ${curr_major_minor}"
    return 1  # Same
}

# Export functions
export -f parse_semantic_version
export -f compare_versions
export -f detect_version_skip
export -f generate_upgrade_path
export -f handle_version_skip
export -f validate_upgrade
export -f check_kanidm_major_minor_change
