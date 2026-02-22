# Changelog

All notable changes to this addon will be documented in this file.

## [HA.1.0.6-kanidm.1.9.0] - 2026-02-18

### Changed
 **Moved migrations.d folder**: to the root of kanidms config directory. The upgrade script will
   move any files automatically for upgrades coming from HA.1.0.5-kanidm.1.9.0
 
 
## [HA.1.0.5-kanidm.1.9.0] - 2026-02-18

### Changed
 **UPDATED**: kanidm-1.9.0
 **FEATURE PREVIEW**: HJSON migration and provisioning folder (config/migrations.d)
 **FIX**: Cert management date calculation

## [HA.1.0.4-kanidm.1.8.6] - 2026-02-14


### Changed
- **Replaced Sources**: Updated to Alpine linux v3.23 - HASSI image
  - openssl: updated to 3.5
  - curl:    updated to 8.17
- **Replaced Source Repo**: Using https://jambox-it.github.io/aports/ as it has package retention
  - Has LDAP an IPA sync binaries, and built on Alpine v3.23
  - Provides full images.
- **Redo Self signed certs**: First in maybe a series revamped to provide full chain.
    Gathers available information from user configuration as well as the system to 
    provide a more correct chain of RootCA, IntermediateCA (install as truste root to devices),
    and server certificates. It's not a industry grade trust, but as close as you  might
    get using a self generated and signed chain without a real PKS/CA server.
  - Generated certs are easily identifiable (jamboxkanidn-[certType].pem), incase LetsEncrypt
    add-on is installed later ( no guessing ) and we are jamming it all in one box.


## [HA.1.0.3-kanidm.1.8.6] - 2026-02-11
Update kanidm to 1.8.6

## [HA.1.0.2-kanidm.1.8.5] - 2026-02-11


### Added
- **Version Tracking System**: Automatic tracking of Kanidm and addon versions
  - Marker file (`/config/.admin_initialized`) tracks installation state and version history
  - Records Kanidm version, addon version, installation date, last startup, and applied migrations
  - Enables safe upgrade validation and migration tracking
- **Sequential Upgrade Enforcement**: Prevents version skips that could corrupt database
  - Validates upgrade paths (allows patch bumps and next minor version)
  - Blocks dangerous version skips (e.g., 1.8.5 → 1.9.1 requires 1.9.0 first)
  - Blocks downgrades to prevent data corruption
- **Migration System**: Organized migration framework for Kanidm version upgrades
  - Migrations organized by version directories (`/usr/local/share/kanidm/migrations/{version}/`)
  - Automatic execution during upgrades with tracking to prevent duplicate runs
  - Template provided for creating new migrations
- **Modular Library System**: Refactored run.sh into reusable library modules
  - `lib/detect_state.sh`: Installation state detection and version management
  - `lib/version_mgmt.sh`: Version comparison and upgrade validation
  - `lib/config_migration.sh`: Migration runner and tracking
  - `lib/init_idm_admin.sh`: Admin session initialization with retry logic
  - `lib/init_person.sh`: Person account creation and credential management
  - `lib/init_database.sh`: Database initialization and configuration
- **Improved Version Detection**: More reliable version detection from binaries and Supervisor API
  - Uses `kanidmd version` command instead of package manager queries
  - Queries Home Assistant Supervisor API for addon version (no more warnings)
  - Fallback chain ensures version is always detected

### Changed
- **Refactored Initialization Flow**: Cleaner startup with modular components
  - Separated concerns: state detection → validation → migration → initialization
  - Better error handling and logging at each stage
  - Improved debugging with detailed state information display
- **Enhanced Retry Logic**: Improved expect-based authentication reliability
  - Better detection of login success/failure/timeout states
  - Configurable retry attempts (default 3) for ~94% overall success rate
  - Detailed debug logging for troubleshooting authentication issues

### Fixed
- **Version Detection Warnings**: Eliminated "Could not determine addon version" warnings
  - Now uses Supervisor API as primary detection method
  - Added environment variable fallback for CI/CD scenarios
- **Expect Login Reliability**: More robust session establishment
  - Added 2-second wait after successful login for session propagation
  - Better handling of authentication policy configuration
  - Improved error detection and retry logic

### Documentation
- Added version management and upgrade procedures section to DOCS.md
- Clarified sequential upgrade requirements and process
- Fixed minor typos in developer comments

## [HA.1.0.1-kanidm.1.8.5] - 2025-12-18
- Versioning change to clearly identify addoon vs upstream versions
- Remove ingrees as kanidm rightfully blocks in x-frame headers
- Add version pinning since I'm sharing. Hello world!

## [1.0.0] - 2025-12-05
- Updated kanidm to 1.8

### Added
- **Replication Support**: Multi-server replication for high availability
  - Configure multiple replication partners with mutual-pull synchronization
  - Per-partner automatic refresh setting (secondary vs primary node configuration)
  - Replication runs on standard port 8444 (exposed in Docker ports)
  - Easy certificate exchange via partner configuration


### Changed
- **BREAKING**: Replaced `origin` configuration field with `hostname` and `domain` fields
  - Origin URL is now automatically built from hostname.domain:4869
  - Users enter hostname part (e.g., "kanidm") and domain part (e.g., "example.com")
  - System builds FQDN automatically (kanidm.example.com)
  - Reduces configuration errors and ensures proper origin URL construction
- **BREAKING**: Simplified certificate configuration fields
  - Renamed `custom_cert_chain` → `cert_chain_path`
  - Renamed `custom_cert_key` → `cert_key_path`
  - Changed `certificate_type` options: `letsencrypt_ha` → `letsencrypt`
- **Improved**: Let's Encrypt addon integration (Option 1 certificate mode)
  - `selfsigned`: Auto-generates certificate in `/config/certs/` (testing only)
  - `letsencrypt`: Automatically uses `/ssl/fullchain.pem` and `/ssl/privkey.pem` (no path entry needed!)
  - `custom`: Uses custom paths from `/ssl/` directory (enter relative paths)
- Updated configuration descriptions to clarify:
  - `domain`: Used for identity format (user@domain), not access URL
  - `hostname`: The actual hostname/IP used to access Kanidm
  - Initial user setup process with reset tokens
  - Certificate paths are relative to `/ssl/` directory
  
## [0.2.0] - 2025-09-02
- Update kanidm to 1.7.3


### Changed
- Move health check from run, to it's own file


## [0.1.0] - 2025-06-3
- Update kanidm to 1.6.3
  
### Added
- CA certificate support for LDAPS connections, autogeneration, checks addon_config/slug default  (relative or absolute paths)
- Comprehensive certificate validation with better error messages
- Debug logging for certificate permissions and paths
- Clear warnings when using self-signed certificates for testing

### Security
- User now set password using time-limited reset tokens (24 hour expiry)
- Better certificate validation ensures SSL is properly configured

### Fixed

- Clear error messages when Let's Encrypt certificates are not found
- Fixed `bashio::log.warn` to `bashio::log.warning` (correct bashio function name)
- Fixed missing LDAP configuration - `enable_ldap` and `ldap_port` now properly configure LDAPS
- Fixed `db_fs_type` not being used in server.toml (was hardcoded to "other" not that this matters for HA)

## [0.0.1] - 2025-04-30

### Added
- Initial release of Kanidm addon for Home Assistant
- AppArmor security profile
- Comprehensive configuration validation on startup
- Admin password retrieval setup on first run
- Health check monitoring

### Security
- TLS required for all connections (HTTPS and LDAPS)
- Restrictive file permissions for configuration (400/600)
- Online backups run without stopping the server
