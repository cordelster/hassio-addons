#!/bin/bash
# Migration: HA.1.0.6-kanidm.1.9.0
# Description: Move migrations directory from /config/kanidm/migrations.d/ to /config/migrations.d/
# Author: cordelster
# Date: 2026-02-21

# IMPORTANT: This migration handles filesystem changes, not JSON config changes
# The migrations directory path was changed to simplify directory structure

# ==========================================
# MIGRATION FUNCTION
# ==========================================

migration_HA_1_0_6_kanidm_1_9_0() {
    local old_migrations_dir="/config/kanidm/migrations.d"
    local new_migrations_dir="/config/migrations.d"

    bashio::log.info "Migration HA.1.0.6: Move migrations directory"

    # ==========================================
    # STEP 1: CHECK IF ALREADY APPLIED
    # ==========================================

    # If old directory doesn't exist, migration already applied or never needed
    if [ ! -d "$old_migrations_dir" ]; then
        bashio::log.debug "  Old migrations directory doesn't exist, skipping"
        return 0
    fi

    # If old directory exists but is empty, just remove it
    if [ -z "$(ls -A "$old_migrations_dir" 2>/dev/null)" ]; then
        bashio::log.info "  Old migrations directory is empty, removing it"
        rmdir "$old_migrations_dir" 2>/dev/null || true
        # Also remove parent /config/kanidm/ if it's empty
        rmdir "/config/kanidm" 2>/dev/null || true
        return 0
    fi

    # ==========================================
    # STEP 2: PERFORM MIGRATION
    # ==========================================

    bashio::log.info "  Migrating files from old to new location..."

    # Create new directory if it doesn't exist
    mkdir -p "$new_migrations_dir"

    # Move all files from old to new directory
    local files_moved=0
    for file in "$old_migrations_dir"/*; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local dest_file="$new_migrations_dir/$filename"

            # Check if file already exists in destination
            if [ -f "$dest_file" ]; then
                bashio::log.warning "  File already exists in new location, skipping: $filename"
                continue
            fi

            # Move file
            if mv "$file" "$dest_file"; then
                bashio::log.info "  ✓ Moved: $filename"
                files_moved=$((files_moved + 1))
            else
                bashio::log.error "  ✗ Failed to move: $filename"
                return 1
            fi
        fi
    done

    # ==========================================
    # STEP 3: CLEANUP
    # ==========================================

    # Remove old directory
    if rmdir "$old_migrations_dir" 2>/dev/null; then
        bashio::log.info "  ✓ Removed old migrations directory"
    else
        bashio::log.warning "  Old migrations directory not empty after migration"
        bashio::log.warning "  Leaving it in place for manual review"
    fi

    # Try to remove parent /config/kanidm/ if empty
    if [ -d "/config/kanidm" ]; then
        if rmdir "/config/kanidm" 2>/dev/null; then
            bashio::log.info "  ✓ Removed empty /config/kanidm/ directory"
        else
            bashio::log.debug "  /config/kanidm/ not empty, leaving it"
        fi
    fi

    # ==========================================
    # STEP 4: SUMMARY
    # ==========================================

    if [ $files_moved -gt 0 ]; then
        bashio::log.info "✓ Migration complete: moved ${files_moved} file(s)"
    else
        bashio::log.info "✓ Migration complete: no files to move"
    fi

    return 0
}
