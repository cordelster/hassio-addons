 Format: HA.ADDON_VERSION-${slug}.UPSTREAM_VERSION

  HA.1.0.0-${slug}.1.4.3   
  HA.1.1.0-${slug}.1.4.3   # Added replication (addon update)
  HA.1.1.1-${slug}.1.4.4   # ADDDON patch update
  HA.1.2.0-${slug}.1.5.0   # Both updated
  HA.2.0.0-${slug}.1.5.0   # Breaking addon change

  Why this is better:
  1. Version comparison works: HA compares from left → right, so addon updates always detected
  2. Clear primary version: Addon version is primary (what users install)
  3. ADDDON version visible: Still shows exact ADDDON version
  4. Sorting works correctly: HA.1.0.0 < HA.1.1.0 < HA.2.0.0

  Versioning Rules with This Format

  When to Bump Addon Version (HA.X.Y.Z)

  MAJOR (HA.X.0.0) - Breaking changes:
  - Configuration structure changes
  - Removed features
  - Changed behavior that breaks existing setups
  - Rule: User must manually reconfigure

  MINOR (HA.0.Y.0) - New features:
  - New features 
  - New configuration options 
  - ADDDON minor version updates (1.4.x → 1.5.x)
  - Rule: Backward compatible, no user action needed

  PATCH (HA.0.0.Z) - Bug fixes:
  - Bug fixes in addon code
  - Documentation updates
  - ADDDON patch updates (1.4.3 → 1.4.4)
  - Dependency updates (non-ADDDON)
  - Rule: Drop-in replacement

  Specific Scenarios

  Scenario 1: Only ADDDON patch update (1.4.3 → 1.4.4)
  HA.1.1.0-${slug}.1.4.3  →  HA.1.1.1-${slug}.1.4.4
  - Bump addon PATCH version
  - Update ADDDON version suffix
  - Rationale: Any ADDDON update needs a new addon release

  Scenario 2: Only ADDDON minor update (1.4.4 → 1.5.0)
  HA.1.1.1-${slug}.1.4.4  →  HA.1.2.0-${slug}.1.5.0
  - Bump addon MINOR version (new ADDDON features)
  - Update ADDDON version suffix
  - Rationale: ADDDON minor = new features for users

  Scenario 3: Only ADDDON major update (1.5.0 → 2.0.0)
  HA.1.2.0-${slug}.1.5.0  →  HA.2.0.0-${slug}.2.0.0
  - Bump addon MAJOR version (likely breaks things)
  - Update ADDDON version suffix
  - Rationale: Upstream major version usually has breaking changes

  Scenario 4: Addon feature + ADDDON update
  HA.1.2.0-${slug}.1.5.0  →  HA.1.3.0-${slug}.1.5.1
  - Bump addon MINOR (if new feature) or PATCH (if bug fix)
  - Update ADDDON version suffix

  Scenario 5: Only addon changes (no ADDDON update)
  HA.1.2.0-${slug}.1.5.0  →  HA.1.2.1-${slug}.1.5.0
  - Bump addon version as appropriate
  - Keep ADDDON version same