#!/bin/bash
# lib/config_migration.sh
# Config schema migration runner

# Migration directory base
MIGRATION_BASE="/usr/local/share/kanidm/migrations"

# ==========================================
# MIGRATION TRACKING
# ==========================================

# Add migration to applied list in marker file
# Usage: add_applied_migration "HA.1.0.1-kanidm.1.8.5"
add_applied_migration() {
    local migration_id="$1"
    local current=$(read_marker_field "MIGRATIONS_APPLIED")

    if [ -z "$current" ]; then
        write_marker_field "MIGRATIONS_APPLIED" "$migration_id"
    else
        # Check if already in list
        if echo "$current" | grep -q "$migration_id"; then
            bashio::log.debug "Migration $migration_id already in applied list"
            return 0
        fi
        write_marker_field "MIGRATIONS_APPLIED" "${current},${migration_id}"
    fi
}

# Check if migration was already applied
# Usage: is_migration_applied "HA.1.0.1-kanidm.1.8.5"
# Returns: 0 if applied, 1 if not
is_migration_applied() {
    local migration_id="$1"
    local applied=$(read_marker_field "MIGRATIONS_APPLIED")

    if [ -z "$applied" ]; then
        return 1  # Not applied
    fi

    if echo "$applied" | grep -q "$migration_id"; then
        return 0  # Applied
    fi

    return 1  # Not applied
}

# Clear migration list (used when Kanidm major.minor changes)
# Usage: clear_applied_migrations
clear_applied_migrations() {
    bashio::log.info "Clearing migration history for new Kanidm version"
    write_marker_field "MIGRATIONS_APPLIED" ""
}

# ==========================================
# MIGRATION EXECUTION
# ==========================================

# Run a single migration script
# Usage: run_migration_script "/path/to/migration.sh"
# Returns: 0 on success, 1 on failure
run_migration_script() {
    local script_path="$1"
    local script_name=$(basename "$script_path" .sh)

    bashio::log.info "🚧 Running migration: ${script_name}"

    # Check if already applied
    if is_migration_applied "$script_name"; then
        bashio::log.debug "  Migration already applied, skipping"
        return 0
    fi

    # Source the migration script
    if [ ! -f "$script_path" ]; then
        bashio::log.error "🚨 Migration script not found: $script_path"
        return 1
    fi

    # Make executable if not already
    chmod +x "$script_path" 2>/dev/null || true

    # Source the script (defines migration function)
    if ! source "$script_path"; then
        bashio::log.error "🚨 Failed to source migration script: $script_path"
        return 1
    fi

    # Extract function name from script name
    # HA.1.0.1-kanidm.1.8.5.sh → migration_HA_1_0_1_kanidm_1_8_5
    local func_name="migration_$(echo "$script_name" | sed 's/[.-]/_/g')"

    # Check if function exists
    if ! declare -f "$func_name" > /dev/null; then
        bashio::log.error "🚨 Migration function not found: ${func_name}"
        bashio::log.error "Expected function in ${script_path}"
        return 1
    fi

    # Run the migration function
    if $func_name; then
        bashio::log.info "✓ Migration ${script_name} completed successfully"
        add_applied_migration "$script_name"
        return 0
    else
        bashio::log.error "🚨 Migration ${script_name} FAILED"
        return 1
    fi
}

# ==========================================
# MIGRATION DISCOVERY AND RUNNER
# ==========================================

# Run all pending migrations for current Kanidm version
# Usage: run_config_migrations
# Returns: 0 on success, 1 on failure
run_config_migrations() {
    local kanidm_major_minor=$(get_kanidm_major_minor)
    local migration_dir="${MIGRATION_BASE}/${kanidm_major_minor}"
    local prev_addon_version=$(read_marker_field "ADDON_VERSION")
    local curr_addon_version=$(get_addon_version)

    bashio::log.info "🚧 Checking for config migrations (Kanidm ${kanidm_major_minor})..."
    bashio::log.debug "  Migration directory: ${migration_dir}"
    bashio::log.debug "  Previous addon: ${prev_addon_version}"
    bashio::log.debug "  Current addon: ${curr_addon_version}"

    # Check if migration directory exists
    if [ ! -d "$migration_dir" ]; then
        bashio::log.debug "No migrations directory for Kanidm ${kanidm_major_minor}"
        return 0
    fi

    # Find all migration scripts in directory
    local migration_scripts=$(find "$migration_dir" -name "HA.*.sh" -type f 2>/dev/null | sort)

    if [ -z "$migration_scripts" ]; then
        bashio::log.debug "No migration scripts found in ${migration_dir}"
        return 0
    fi

    # Parse version numbers for comparison
    # Extract just the HA version part (HA.1.0.5-kanidm.1.9.0 → 1.0.5)
    local prev_ha_version=$(echo "$prev_addon_version" | sed -E 's/^HA\.([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')
    local curr_ha_version=$(echo "$curr_addon_version" | sed -E 's/^HA\.([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')

    parse_semantic_version "$prev_ha_version"
    local prev_ha_major=$VERSION_MAJOR
    local prev_ha_minor=$VERSION_MINOR
    local prev_ha_patch=$VERSION_PATCH

    parse_semantic_version "$curr_ha_version"
    local curr_ha_major=$VERSION_MAJOR
    local curr_ha_minor=$VERSION_MINOR
    local curr_ha_patch=$VERSION_PATCH

    local migrations_run=0
    local migrations_skipped=0

    # Iterate through migration scripts
    while IFS= read -r script_path; do
        local script_name=$(basename "$script_path" .sh)

        # Extract version from script name (HA.1.0.1-kanidm.1.8.5 → 1.0.1)
        local script_ha_version=$(echo "$script_name" | sed -E 's/^HA\.([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')

        # Parse script version
        parse_semantic_version "$script_ha_version"
        local script_ha_major=$VERSION_MAJOR
        local script_ha_minor=$VERSION_MINOR
        local script_ha_patch=$VERSION_PATCH

        # Skip if script version <= previous version (already applied or not needed)
        if [ "$script_ha_major" -lt "$prev_ha_major" ] || \
           ([ "$script_ha_major" -eq "$prev_ha_major" ] && [ "$script_ha_minor" -lt "$prev_ha_minor" ]) || \
           ([ "$script_ha_major" -eq "$prev_ha_major" ] && [ "$script_ha_minor" -eq "$prev_ha_minor" ] && [ "$script_ha_patch" -le "$prev_ha_patch" ]); then
            bashio::log.debug "Skipping ${script_name} (already applied)"
            migrations_skipped=$((migrations_skipped + 1))
            continue
        fi

        # Skip if script version > current version (future version)
        if [ "$script_ha_major" -gt "$curr_ha_major" ] || \
           ([ "$script_ha_major" -eq "$curr_ha_major" ] && [ "$script_ha_minor" -gt "$curr_ha_minor" ]) || \
           ([ "$script_ha_major" -eq "$curr_ha_major" ] && [ "$script_ha_minor" -eq "$curr_ha_minor" ] && [ "$script_ha_patch" -gt "$curr_ha_patch" ]); then
            bashio::log.debug "Skipping ${script_name} (future version)"
            continue
        fi

        # This migration is between prev and curr versions - run it
        bashio::log.info "🚧 Applying migration: ${script_name}"

        if run_migration_script "$script_path"; then
            migrations_run=$((migrations_run + 1))
        else
            bashio::log.error "🚨 Migration failed: ${script_name}"
            return 1
        fi

    done <<< "$migration_scripts"

    # Summary
    if [ $migrations_run -gt 0 ]; then
        bashio::log.info "✓ Applied ${migrations_run} migration(s) successfully"
    else
        bashio::log.info "No new migrations to apply"
    fi

    return 0
}

# Run migrations after finishing previous Kanidm version
# This handles the case where user upgrades Kanidm version
# and we need to apply any missed migrations from old version first
# Usage: run_pending_migrations_from_previous_version
run_pending_migrations_from_previous_version() {
    local prev_kanidm_major_minor=$(read_marker_field "KANIDM_MAJOR_MINOR")
    local migration_dir="${MIGRATION_BASE}/${prev_kanidm_major_minor}"

    if [ -z "$prev_kanidm_major_minor" ]; then
        bashio::log.debug "No previous Kanidm version recorded"
        return 0
    fi

    if [ ! -d "$migration_dir" ]; then
        bashio::log.debug "No migrations directory for previous Kanidm ${prev_kanidm_major_minor}"
        return 0
    fi

    bashio::log.info "🚧 Checking for pending migrations from Kanidm ${prev_kanidm_major_minor}..."

    # Temporarily run migrations from old directory
    local kanidm_major_minor="$prev_kanidm_major_minor"
    run_config_migrations
}

# Export functions
export -f add_applied_migration
export -f is_migration_applied
export -f clear_applied_migrations
export -f run_migration_script
export -f run_config_migrations
export -f run_pending_migrations_from_previous_version
