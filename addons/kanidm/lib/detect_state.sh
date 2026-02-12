#!/bin/bash
# lib/detect_state.sh
# Marker file management and installation state detection

# Marker file location
MARKER_FILE="/config/.admin_initialized"

# ==========================================
# MARKER FILE OPERATIONS
# ==========================================

# Read a field from the marker file
# Usage: read_marker_field "FIELD_NAME"
# Returns: field value or empty string if not found
read_marker_field() {
    local field_name="$1"

    if [ ! -f "$MARKER_FILE" ]; then
        return 0
    fi

    # Read field from key=value format
    grep "^${field_name}=" "$MARKER_FILE" 2>/dev/null | cut -d'=' -f2-
}

# Write a field to the marker file
# Usage: write_marker_field "FIELD_NAME" "value"
write_marker_field() {
    local field_name="$1"
    local field_value="$2"

    # Create marker file if it doesn't exist
    if [ ! -f "$MARKER_FILE" ]; then
        touch "$MARKER_FILE"
    fi

    # Check if field already exists
    if grep -q "^${field_name}=" "$MARKER_FILE" 2>/dev/null; then
        # Update existing field (compatible with macOS and Linux sed)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^${field_name}=.*|${field_name}=${field_value}|" "$MARKER_FILE"
        else
            sed -i "s|^${field_name}=.*|${field_name}=${field_value}|" "$MARKER_FILE"
        fi
    else
        # Append new field
        echo "${field_name}=${field_value}" >> "$MARKER_FILE"
    fi
}

# Initialize marker file with all fields
# Usage: init_marker_file [addon_version]
init_marker_file() {
    local current_version="${1:-$(get_addon_version)}"
    local kanidm_version=$(get_kanidm_version)
    local kanidm_major_minor=$(get_kanidm_major_minor "$kanidm_version")
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    bashio::log.info "Initializing marker file"

    write_marker_field "INITIALIZED" "true"
    write_marker_field "KANIDM_VERSION" "$kanidm_version"
    write_marker_field "KANIDM_MAJOR_MINOR" "$kanidm_major_minor"
    write_marker_field "ADDON_VERSION" "$current_version"
    write_marker_field "INIT_DATE" "$timestamp"
    write_marker_field "LAST_STARTUP" "$timestamp"
    write_marker_field "MIGRATIONS_APPLIED" ""

    bashio::log.info "✓ Marker file initialized"
}

# Update marker file on startup
# Usage: update_marker_file [addon_version]
update_marker_file() {
    local current_version="${1:-$(get_addon_version)}"
    local kanidm_version=$(get_kanidm_version)
    local kanidm_major_minor=$(get_kanidm_major_minor "$kanidm_version")
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    write_marker_field "KANIDM_VERSION" "$kanidm_version"
    write_marker_field "KANIDM_MAJOR_MINOR" "$kanidm_major_minor"
    write_marker_field "ADDON_VERSION" "$current_version"
    write_marker_field "LAST_STARTUP" "$timestamp"
}

# ==========================================
# VERSION EXTRACTION
# ==========================================

# Get current Kanidm version from installed package or addon version
# Returns: version string like "1.8.5"
# Extraction hierarchy:
#   1. From kanidmd binary (actual installed version)
#   2. From kanidm binary (fallback)
#   3. From addon version string (config.yaml - source of truth)
get_kanidm_version() {
    local version=""

    # Try kanidmd version command (output: "kanidmd 1.8.5")
    if command -v kanidmd >/dev/null 2>&1; then
        version=$(kanidmd version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    fi

    # Fallback: try kanidm version command
    if [ -z "$version" ] && command -v kanidm >/dev/null 2>&1; then
        version=$(kanidm version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    fi

    # Last resort: extract from addon version (config.yaml is source of truth)
    if [ -z "$version" ]; then
        bashio::log.debug "Could not determine Kanidm version from binaries, extracting from addon version"
        local addon_version=$(get_addon_version)
        if [ "$addon_version" = "unknown" ]; then
            bashio::log.error "Cannot extract Kanidm version: addon version unknown"
            echo "unknown"
            return 1
        fi
        # Extract kanidm version from format: HA.x.x.x-kanidm.1.8.5
        version=$(echo "$addon_version" | sed -E 's/.*-kanidm\.([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
        if [ -z "$version" ] || [ "$version" = "$addon_version" ]; then
            bashio::log.error "Could not extract Kanidm version from addon version: $addon_version"
            bashio::log.error "Expected format: HA.x.x.x-kanidm.x.x.x"
            echo "unknown"
            return 1
        fi
        bashio::log.debug "Extracted Kanidm version from config.yaml: $version"
    fi

    echo "$version"
}

# Extract major.minor from Kanidm version
# Usage: get_kanidm_major_minor "1.8.5"
# Returns: "1.8"
get_kanidm_major_minor() {
    local version="${1:-$(get_kanidm_version)}"
    echo "$version" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/'
}

# Get addon version from Supervisor API or environment
# Returns: full addon version like "HA.1.0.2-kanidm.1.8.5"
# This is the SINGLE SOURCE OF TRUTH for both addon and Kanidm versions
get_addon_version() {
    # Primary method: Query Home Assistant Supervisor API
    # This is the most reliable method as HA injects the version from config.yaml
    if command -v curl >/dev/null 2>&1 && [ -n "${SUPERVISOR_TOKEN:-}" ]; then
        local version=$(curl -sf -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
            http://supervisor/addons/self/info 2>/dev/null | \
            grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$version" ]; then
            bashio::log.debug "✓ Addon version from Supervisor API: ${version}"
            echo "$version"
            return 0
        fi
    fi

    # Fallback: Environment variable (if set by user or CI/CD)
    if [ -n "${ADDON_VERSION:-}" ]; then
        bashio::log.debug "✓ Addon version from environment: ${ADDON_VERSION}"
        echo "$ADDON_VERSION"
        return 0
    fi

    # Fatal: Could not determine version from any source
    bashio::log.error "Could not determine addon version from Supervisor API or environment"
    bashio::log.error "This indicates a problem with the Home Assistant installation"
    echo "unknown"
    return 1
}

# ==========================================
# STATE DETECTION
# ==========================================

# Detect current installation state
# Returns: FRESH_INSTALL, NORMAL_STARTUP, UPGRADE_REQUIRED, VERSION_SKIP, INCONSISTENT_STATE
detect_installation_state() {
    local current_addon_version=$(get_addon_version)
    local current_kanidm_version=$(get_kanidm_version)
    local current_kanidm_major_minor=$(get_kanidm_major_minor "$current_kanidm_version")

    bashio::log.debug "Detecting installation state..."
    bashio::log.debug "  Current addon version: ${current_addon_version}"
    bashio::log.debug "  Current Kanidm version: ${current_kanidm_version}"

    # Check if marker file exists
    if [ ! -f "$MARKER_FILE" ] || [ ! -s "$MARKER_FILE" ]; then
        # Check if database exists (might be interrupted install)
        if [ -f "/data/kanidm.db" ]; then
            bashio::log.warning "Database exists but marker file is missing"
            echo "INCONSISTENT_STATE"
            return 1
        fi

        bashio::log.info "No marker file found - fresh installation"
        echo "FRESH_INSTALL"
        return 0
    fi

    # Read previous versions from marker
    local prev_addon_version=$(read_marker_field "ADDON_VERSION")
    local prev_kanidm_version=$(read_marker_field "KANIDM_VERSION")
    local prev_kanidm_major_minor=$(read_marker_field "KANIDM_MAJOR_MINOR")

    bashio::log.debug "  Previous addon version: ${prev_addon_version}"
    bashio::log.debug "  Previous Kanidm version: ${prev_kanidm_version}"

    # Check for version changes
    if [ "$prev_addon_version" != "$current_addon_version" ] || \
       [ "$prev_kanidm_version" != "$current_kanidm_version" ]; then

        # Check if Kanidm version changed
        if [ "$prev_kanidm_version" != "$current_kanidm_version" ]; then
            bashio::log.info "Kanidm version changed: ${prev_kanidm_version} → ${current_kanidm_version}"

            # This will be checked by version_mgmt.sh for skip detection
            echo "UPGRADE_REQUIRED"
            return 0
        fi

        # Addon version changed but Kanidm same
        bashio::log.info "Addon version changed: ${prev_addon_version} → ${current_addon_version}"
        echo "UPGRADE_REQUIRED"
        return 0
    fi

    # No version changes - normal startup
    bashio::log.debug "No version changes detected"
    echo "NORMAL_STARTUP"
    return 0
}

# Check if database file exists and is accessible
# Returns: 0 if valid, 1 if not
validate_database_exists() {
    if [ ! -f "/data/kanidm.db" ]; then
        bashio::log.debug "Database file does not exist"
        return 1
    fi

    if [ ! -r "/data/kanidm.db" ]; then
        bashio::log.error "Database file exists but is not readable"
        return 1
    fi

    # Check if file has content
    if [ ! -s "/data/kanidm.db" ]; then
        bashio::log.error "Database file exists but is empty"
        return 1
    fi

    bashio::log.debug "✓ Database file exists and is accessible"
    return 0
}

# Display state information for debugging
# Usage: show_state_info
show_state_info() {
    bashio::log.info "=========================================="
    bashio::log.info "INSTALLATION STATE"
    bashio::log.info "=========================================="

    if [ -f "$MARKER_FILE" ]; then
        bashio::log.info "Marker file: EXISTS"
        bashio::log.info "  Addon version: $(read_marker_field 'ADDON_VERSION')"
        bashio::log.info "  Kanidm version: $(read_marker_field 'KANIDM_VERSION')"
        bashio::log.info "  Init date: $(read_marker_field 'INIT_DATE')"
        bashio::log.info "  Last startup: $(read_marker_field 'LAST_STARTUP')"

        local migrations=$(read_marker_field 'MIGRATIONS_APPLIED')
        if [ -n "$migrations" ]; then
            local count=$(echo "$migrations" | tr ',' '\n' | wc -l | tr -d ' ')
            bashio::log.info "  Migrations applied: ${count}"
        else
            bashio::log.info "  Migrations applied: 0"
        fi
    else
        bashio::log.info "Marker file: NOT FOUND"
    fi

    if [ -f "/data/kanidm.db" ]; then
        local db_size=$(du -h /data/kanidm.db | cut -f1)
        bashio::log.info "Database: EXISTS (${db_size})"
    else
        bashio::log.info "Database: NOT FOUND"
    fi

    bashio::log.info "=========================================="
}

# Export functions for use in other scripts
export -f read_marker_field
export -f write_marker_field
export -f init_marker_file
export -f update_marker_file
export -f get_kanidm_version
export -f get_kanidm_major_minor
export -f get_addon_version
export -f detect_installation_state
export -f validate_database_exists
export -f show_state_info
