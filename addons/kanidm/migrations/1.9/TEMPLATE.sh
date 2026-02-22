#!/bin/bash
# Migration: HA.X.Y.Z-kanidm.A.B.C
# Description: [Brief description of what this migration does]
# Author: [Your name]
# Date: [YYYY-MM-DD]

# IMPORTANT NOTES:
# 1. Function name MUST match pattern: migration_HA_X_Y_Z_kanidm_A_B_C
#    (replace dots and dashes with underscores)
# 2. Make migrations IDEMPOTENT (safe to run multiple times)
# 3. Use SAFE DEFAULTS (don't break existing setups)
# 4. Validate before committing changes (write to temp file first)
# 5. Log clearly what you're doing

# ==========================================
# MIGRATION FUNCTION
# ==========================================

migration_HA_X_Y_Z_kanidm_A_B_C() {
    local options_file="/data/options.json"

    bashio::log.info "Migration HA.X.Y.Z: [Description]"

    # ==========================================
    # STEP 1: CHECK IF ALREADY APPLIED
    # ==========================================
    # Make migration idempotent - check if changes already exist

    if jq -e '.new_field' "$options_file" > /dev/null 2>&1; then
        bashio::log.debug "  Migration already applied (new_field exists), skipping"
        return 0
    fi

    # ==========================================
    # STEP 2: PERFORM MIGRATION
    # ==========================================

    bashio::log.info "  Applying migration changes..."

    # Example: Add a new field
    jq '. + {
        "new_field": {
            "enabled": false,
            "value": "default"
        }
    }' "$options_file" > "${options_file}.tmp"

    # ==========================================
    # STEP 3: VALIDATE AND COMMIT
    # ==========================================

    # Check if jq succeeded and produced valid JSON
    if [ $? -eq 0 ] && jq -e '.' "${options_file}.tmp" > /dev/null 2>&1; then
        # Replace original with updated version
        mv "${options_file}.tmp" "$options_file"
        bashio::log.info "✓ Migration complete: [what was changed]"
        return 0
    else
        # Something went wrong - don't commit changes
        rm -f "${options_file}.tmp"
        bashio::log.error "✗ Migration failed: JSON validation error"
        return 1
    fi
}

# ==========================================
# COMMON MIGRATION PATTERNS
# ==========================================

# Pattern 1: Add New Field
add_field_example() {
    local options_file="/data/options.json"

    if ! jq -e '.new_field' "$options_file" > /dev/null 2>&1; then
        jq '. + {"new_field": "default_value"}' "$options_file" > "${options_file}.tmp"
        mv "${options_file}.tmp" "$options_file"
    fi
}

# Pattern 2: Rename Field
rename_field_example() {
    local options_file="/data/options.json"

    # Check if old exists and new doesn't
    if jq -e '.old_name' "$options_file" > /dev/null 2>&1 && \
       ! jq -e '.new_name' "$options_file" > /dev/null 2>&1; then
        jq '.new_name = .old_name | del(.old_name)' "$options_file" > "${options_file}.tmp"
        mv "${options_file}.tmp" "$options_file"
    fi
}

# Pattern 3: Remove Deprecated Field
remove_field_example() {
    local options_file="/data/options.json"

    if jq -e '.deprecated_field' "$options_file" > /dev/null 2>&1; then
        jq 'del(.deprecated_field)' "$options_file" > "${options_file}.tmp"
        mv "${options_file}.tmp" "$options_file"
    fi
}

# Pattern 4: Transform Field Structure (string to object)
transform_field_example() {
    local options_file="/data/options.json"

    # Check if field is a string (needs transformation)
    if jq -e '.field | type == "string"' "$options_file" > /dev/null 2>&1; then
        jq '.field = {"value": .field, "enabled": true}' "$options_file" > "${options_file}.tmp"
        mv "${options_file}.tmp" "$options_file"
    fi
}

# Pattern 5: Add Field to Array Items
add_to_array_items_example() {
    local options_file="/data/options.json"

    # Add 'schedule' field to each item in 'directory_sync.sources' array
    jq '.directory_sync.sources |= map(
        if has("schedule") then
            .
        else
            . + {"schedule": "0 */10 * * * * *"}
        end
    )' "$options_file" > "${options_file}.tmp"
    mv "${options_file}.tmp" "$options_file"
}

# Pattern 6: Conditional Migration Based on Other Fields
conditional_migration_example() {
    local options_file="/data/options.json"

    # Only add field if another field has specific value
    if jq -e '.feature_enabled == true' "$options_file" > /dev/null 2>&1; then
        if ! jq -e '.feature_config' "$options_file" > /dev/null 2>&1; then
            jq '. + {"feature_config": {"timeout": 30}}' "$options_file" > "${options_file}.tmp"
            mv "${options_file}.tmp" "$options_file"
        fi
    fi
}

# ==========================================
# MIGRATION CHECKLIST
# ==========================================
#
# Before creating your migration:
# [ ] Understand what changed in the config schema
# [ ] Determine the new addon version (following VERSION.md)
# [ ] Name the file: HA.X.Y.Z-kanidm.A.B.C.sh
# [ ] Place it in the correct Kanidm version directory (migrations/1.8/, etc.)
#
# In your migration function:
# [ ] Named correctly: migration_HA_X_Y_Z_kanidm_A_B_C
# [ ] Check if already applied (idempotent)
# [ ] Use safe defaults (don't break existing setups)
# [ ] Write to temp file first
# [ ] Validate JSON before committing
# [ ] Log what you're doing
# [ ] Return 0 on success, 1 on failure
#
# After creating migration:
# [ ] Test with old config (should apply changes)
# [ ] Test with new config (should skip)
# [ ] Test running twice (should be safe)
# [ ] Test with invalid JSON (should fail gracefully)
# [ ] Update config.yaml schema
# [ ] Update config.yaml version
# [ ] Update CHANGELOG.md
#
# ==========================================
