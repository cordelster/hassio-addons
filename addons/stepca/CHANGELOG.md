# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.8] - 2026-03-23

### Added
- **ACME EAB key management** — list, generate, and remove External Account Binding keys
  via the ACF web UI (Provisioners → Manage EAB Keys). Equivalent to JWK token generation
  for ACME clients requiring pre-authorization.
- **ACME provisioner options** — per-challenge-type selection (http-01, dns-01, tls-alpn-01),
  Require EAB toggle, and Force CN toggle when adding a provisioner.
- **ACME directory URL** displayed inline on Provisioners list and Provisioner Details pages,
  with a direct "Manage EAB Keys" link.
- **Serial-based certificate identity** — all certificate action links (view, revoke) now use
  the decimal serial number as the URL key. Renewed certs with duplicate CNs are correctly
  identified. Active/Superseded/Revoked issuance status labels added to cert list.
- **Compact time-remaining display** — certificate list shows `Xd Yh` / `Xh Ym` / `Xm`
  instead of floored days, with µs-precision DB load timing using `posix.clock_gettime`.
- **Sub-day cert expiration precision** — expiration status now computed from a float
  lifetime ratio rather than floored day count, fixing false Critical status on short-lived
  certs (e.g. 24h ACME certs at 23h 55m showing as 0 days remaining → Critical).
- **`defaults.json` sync** — saving a new CA DNS name in the Configuration tab now also
  updates `defaults.json` `ca-url`, keeping the step CLI context consistent.

### Changed
- **Backup simplified** — dropped the UUID encryption key system and Backup Manager ACF
  module. Backups are now encrypted with the CA initialization password (`password.txt`),
  which is already required to operate the CA. No separate key generation step needed.
- **Restore workflow** — automated restore on startup by placing the archive and a
  `password.txt` alongside it in the addon config directory; manual restore via
  `pki-restore.sh` over SSH.
- **acf-stepca updated to latest** — complete refresh of the embedded ACF PKI module
  incorporating all fixes and features developed through March 2026.

### Removed
- **Backup Manager ACF module** — replaced by the simplified CA-password-based backup
  system. The UUID key manager, one-time key display, and all associated ACF views are gone.

### Fixed
- `create_certificate` CA track was missing `--ca-url` flag, causing `step ca certificate`
  to fall back to `defaults.json` and fail if that file had a stale hostname.
- `now_ts` scope bug — variable defined inside `if exp_epoch` block was referenced outside
  it, producing nil in the time-remaining display.
- All luacheck warnings resolved (undefined variable + line-length violations).
- **ACF user management broken under AppArmor** — `fs.is_file()` in ACF uses `lstat` and
  returns `false` for symlinks. The previous design symlinked `/etc/acf/passwd` →
  `/data/acf/passwd`; ACF's `write_entry` guard treated the symlink as a missing file and
  returned false before writing, causing "Failed to create new user" for all web UI user
  operations. Fixed by setting `confdir=/data/acf/` in `acf.conf` so ACF operates on the
  real file directly instead of through the symlink.

### Security
- **AppArmor enforce mode enabled** (`apparmor: true` in `config.yaml`). A minimum-required
  profile covering s6-overlay, step-ca, nginx, fcgiwrap, ACF/Lua/Haserl, backup/restore,
  and HA ingress is enforced at the container boundary. Capabilities are limited to those
  actually required (`chown`, `dac_override`, `fowner`, `setuid`, `setgid`,
  `net_bind_service`, `fsetid`).

---

## [0.0.7] - 2025-09-09

### Removed
- **PyKMIP / KMIP server** — dropped entirely. The addon scope is narrowed to PKI and
  certificate authority management. NetApp ONTAP and other KMIP clients are out of scope.
  Removed PyKMIP service, SQLite database, KMIP ACF module, KMIP client cert management,
  Python dependencies, and all related configuration options.
- **Backup Manager ACF module** — the UUID-based encryption key system introduced in 0.0.6
  was removed as too complex to maintain relative to its value. Backup encryption moved to
  the CA initialization password in 0.0.8.

### Changed
- Dockerfile and service set cleaned up following PyKMIP removal.
- AppArmor profile updated to remove KMIP-related rules.


## [0.0.6] - 2025-07-25

### Added - Production Readiness (P0 Critical Items)

- **SQLite Database Integrity Checks**
  - Pre-startup integrity validation for PyKMIP database
  - Automatic backup before checks (10-backup rotation)
  - Fast fail-fast quick_check + full integrity_check
  - Automatic dump/restore repair for corrupted databases
  - Database vacuum optimization
  - Home Assistant entity integration (5 sensors)
  - Health monitoring with JSON metrics (30-day retention)
  - Comprehensive documentation

- **Service Restart Backoff System**
  - Exponential backoff for all critical services (1s → 60s max)
  - Automatic circuit breaker (10 max attempts)
  - Persistent restart tracking in `/data/.restart-state/`
  - Counter reset after 5 minutes successful uptime
  - Home Assistant notifications for failures
  - Exit code/signal interpretation
  - All services covered: step-ca, pykmip, nginx, fcgiwrap, backup, cert-renewal

- **Backup Validation System**
  - 9 comprehensive validation checks:
    1. Archive integrity test (fast 1-2s)
    2. Backup extraction verification
    3. Manifest verification
    4. Critical files presence check
    5. Certificate format validation (PEM, expiry)
    6. Certificate chain verification
    7. SQLite database integrity
    8. JSON configuration validation
    9. Statistics calculation
  - Periodic validation service (weekly default)
  - Home Assistant entity and notifications
  - Metrics recording (30-day retention)
  - Detailed logging and error reporting

- **ACF Web UI Views (Complete)**
  - PKI Manager module (6 views):
    - CA setup wizard with secure password display
    - Main dashboard with service status
    - Certificate list and expiration tracking
    - Admin password viewer
    - Certificate creation form
  - nginx configuration (port 8099, TLS, FastCGI)
  - fcgiwrap CGI support
  - Bootstrap 3 styling
  - Following Alpine ACF conventions

### Added - Secure Backup Key Management (2025-06-24)

- **UUID-Based Encryption Key System**
  - Cryptographically secure UUID v4 keys (122 bits of entropy)
  - Server-side key storage at `/data/backup/encryption.key` with chmod 600
  - One-time key display at generation for enhanced security
  - Key metadata storage with creation timestamp and version
  - Automatic key validation (UUID format checking)

- **Backup Manager ACF Module** (backup-manager)
  - Complete web interface for backup and encryption key management
  - Role-based access control (ADMIN for key operations, OPERATOR for backups)
  - Encryption Key management views:
    - Generate Key - Create new UUID encryption key (one-time display)
    - Reset Key - Generate new key with old key archival
    - Import Key - Import existing key for migration/recovery
    - Key Status - View key metadata without exposing actual key
  - Backup operations views:
    - List Backups - View all backups across all locations
    - Create Backup - Trigger manual backup
  - Restoration views:
    - Upload Backup - Upload backup archive from local computer
    - Inspect Backup - View archive contents without extraction
    - Restore Backup - Full restoration with service management

- **Backup Key Manager Script** (`backup-key-manager.sh`)
  - Command-line tool for encryption key operations
  - Generate, get, import, reset, validate key operations
  - Secure key archival during reset
  - Key metadata management
  - Integration with backup and restore scripts

- **Enhanced Backup Scripts**
  - pki-backup.sh now uses UUID key from key manager
  - pki-restore.sh supports key from manager or command-line
  - Improved error messages with web UI navigation instructions
  - Backup operations fail gracefully if key not configured

### Fixed

- **PyKMIP Python 3.12 Compatibility**
  - Fixed `ImportError: cannot import name 'SafeConfigParser'`
  - Added post-install patch to alias ConfigParser as SafeConfigParser
  - PyKMIP now works with Python 3.12 (Alpine 3.23 base)

- **Service Restart Backoff Logging**
  - Fixed `bashio::log.*: command not found` in finish scripts
  - Changed to plain echo logging (works in all s6 contexts)
  - Logs still appear in supervisor output

- **Backup Validation on First Boot**
  - Added encryption key check before validation
  - Gracefully skips validation if key not configured
  - Prevents error spam on initial startup

- **OAuth2 Configuration Schema**
  - Changed OAuth2 URL fields from `"url?"` to `str?` in schema
  - Empty URLs now allowed when using local authentication
  - Added runtime URL validation in run.sh when OAuth2 enabled
  - Supports provider presets and manual configuration

### Changed

- **Removed `backup_password` from Configuration**
  - Encryption key no longer stored in add-on configuration
  - Enhanced security through server-side key management
  - Key managed exclusively via Backup Manager ACF module
  - Prevents key exposure in configuration files or logs

- **Backup Workflow**
  - First-time setup now requires web UI key generation
  - Automated backups skip execution if key not configured
  - Manual backups provide clear instructions for key setup

### Security Enhancements

- UUID keys provide stronger entropy than user-chosen passwords
- Key never exposed in configuration or logs
- One-time display prevents key re-exposure
- Role-based access control for key management
- Old keys archived (chmod 400) during reset for backup recovery
- Backup upload and inspection capabilities for external backups

### Documentation

- Complete Backup Manager ACF module documentation
- UUID-based encryption key management guide
- Key loss and compromise recovery procedures
- Web UI backup operations documentation
- Updated command-line backup procedures
- Security best practices for key storage

### Implementation Status

- Phase 5: Encrypted Backup Integration - ENHANCED with secure key management

## [0.0.5] - 2025-06-01

### Added - Automated Backup System (Phase 5)

- **Encrypted Backup System**
  - Automated encrypted backups using tar + 7z with AES-256 encryption
  - Password-protected backup archives with header encryption
  - Backup manifest generation with file inventory and critical file checks
  - s6-overlay periodic service for automated backup scheduling
  - Initial backup 5 minutes after startup, then at configured intervals

- **Backup Configuration**
  - `backup_enabled` - Enable/disable automated backups
  - `backup_password` - Required password for backup encryption (AES-256)
  - `backup_interval_hours` - Configurable backup interval (1-168 hours)
  - `backup_retention_count` - Automatic retention policy (1-30 backups)
  - `backup_location` - Multiple storage locations (config, share, addon_config)

- **Backup Restoration**
  - Complete restoration script with safety backup creation
  - Automatic service stop/start during restoration
  - Backup manifest verification before restoration
  - Post-restoration permission fixing
  - Support for password from configuration or command-line

- **Backup Management**
  - Automatic retention policy enforcement
  - Old backup cleanup when retention limit exceeded
  - Manual backup trigger capability
  - List available backups across all locations
  - Backup size and timestamp reporting

- **Backup Contents**
  - step-ca data (Root CA, certificates, configuration)
  - KMIP database and configuration
  - Certificate Revocation Lists
  - Web UI user data
  - Add-on configuration
  - Complete file inventory in manifest

### Security
- AES-256 encryption for backup archives
- Header encryption to hide filenames
- Password requirement for backup access
- Strong password recommendations in documentation
- Security warnings for backup storage

### Documentation
- Complete backup and recovery section in DOCS.md
- Backup configuration reference in CONFIGURATION.md
- Backup translations for all options
- Backup best practices and security considerations
- Manual backup and restoration procedures
- Safety backup creation during restoration

### Dependencies Added
- p7zip - 7-Zip archiver for encrypted backups

### Implementation Status
- Phase 5: Encrypted Backup Integration - COMPLETED

## [0.0.4] - 2025-05-02

### Added - Alpine ACF Integration
- **ACF PKI Manager Module** (acf-pki)
  - Complete MVC architecture following Alpine standards
  - Dashboard and status monitoring
  - Certificate listing and detailed inspection
  - Certificate creation with templates (Root CA, Intermediate CA, Server, Client, WiFi)
  - Certificate revocation with confirmation
  - CA hierarchy viewing
  - CRL management and refresh
  - Audit log viewer
  - Configuration management

- **ACF KMIP Manager Module** (acf-kmip)
  - Separate module following Alpine packaging standards
  - KMIP key database querying and statistics
  - Key details and operation history viewing
  - KMIP client certificate management (vendor-agnostic)
  - Support for multiple client types (NetApp, VMware vSphere, Dell EMC, Pure Storage, generic)
  - Client-type specific installation instructions
  - KMIP service control (start/stop/restart)
  - KMIP audit log viewing

- **KMIP Database Tools**
  - Python-based KMIP database query tool
  - List all symmetric keys
  - Get key details and operation history
  - Search keys by name or identifier
  - Database statistics and reporting

- **External Authentication**
  - LDAP authentication support (FreeIPA, lldap, OpenLDAP, 389 DS, Active Directory)
  - OAuth2/OIDC authentication support
  - Preset configurations for Kanidm, Authentik, Keycloak, Okta
  - Role mapping from LDAP groups to ACF roles
  - Claims-based role assignment for OAuth2
  - Unified authentication module (acf-auth.lua)
  - Local, LDAP, and OAuth2 authentication methods

- **Web Server Configuration**
  - nginx configured for ACF web interface
  - fcgiwrap for ACF CGI script execution
  - SSL/TLS using step-ca generated certificates
  - s6-overlay services for nginx and fcgiwrap

- **ACF Role-Based Access Control**
  - ADMIN role: Full system access
  - OPERATOR role: Certificate and client management
  - USER role: Read and create capabilities
  - READONLY role: View-only access

### Configuration Enhancements
- Authentication method selection (local, LDAP, OAuth2)
- Complete LDAP configuration options (server, port, TLS, bind DN, filters, groups)
- Complete OAuth2/OIDC configuration options (client ID/secret, endpoints, claims)
- Multi-vendor KMIP client support configuration

### Dependencies Added
- acf-core and acf-lib (Alpine Configuration Framework)
- lua5.3, lua-posix, lua-filesystem, lua-cjson
- haserl (server-side scripting for ACF views)
- fcgiwrap (FastCGI wrapper for CGI scripts)
- openldap-clients (LDAP authentication tools)
- curl (OAuth2 token exchange)

### Documentation
- ACF module structure and architecture
- KMIP key management workflows
- External authentication setup guides
- Multi-vendor KMIP client integration

### Technical Implementation
- Proper Alpine Linux package structure
- Separate ACF modules (acf-pki and acf-kmip)
- Lua-based MVC architecture
- Configuration Framework Entities (CFE) for data exchange
- nginx reverse proxy with SSL/TLS

## [Unreleased - Future Phases]

### Planned - Phase 4: Web Management Interface
- Lua + Haserl web management interface
- nginx integration for UI and CRL distribution
- Dashboard for certificate and key management
- Certificate templates (CA, Intermediate CA, Server, Client/Server, Client, WiFi)
- One-click certificate revocation with CRL update
- Audit log viewer for PyKMIP operations
- Security confirmations for destructive operations
- OPNsense trust management page compatibility

### Completed - Phase 5: Backup Integration (v0.0.5)
- ✓ Encrypted backup of /data directory
- ✓ Compression of backup archives (tar + 7z)
- ✓ User-configurable backup schedule
- ✓ Backup restoration procedures
- ✓ Backup retention policy management
- Future: Integration with Home Assistant backup system (supervisor API)

### Planned - Additional Features
- Automated CRL refresh (24-hour schedule)
- Certificate expiration notifications
- Health monitoring and watchdog
- Home Assistant ingress support
- Visual assets (icon.png, logo.png)

## [0.0.3] - 2025-03-13 (Foundation)

### Added
- Initial Home Assistant add-on structure
- step-ca (Smallstep) certificate authority integration
- PyKMIP server for KMIP 1.1/1.2 protocol support
- Mutual TLS authentication for NetApp ONTAP integration
- s6-overlay service management for step-ca and PyKMIP
- Persistent storage for certificates and keys in /data
- Multi-architecture support (amd64, aarch64)
- bashio integration for configuration management
- AppArmor security profile
- Translation support for internationalization

### Configuration System
- Comprehensive pre-startup configuration options
- CA Mode selection (generate new or import existing)
- Complete CA identity configuration (organization, country, validity)
- CA import capability for existing PKI integration
- Automatic Intermediate CA generation
- Automatic server certificate generation (KMIP and Web UI)
- Web UI administrative user configuration
- KMIP server customization options
- Certificate defaults configuration (validity, key size, algorithm)
- Automated CRL distribution with configurable update interval
- System hostname and domain configuration

### Documentation
- README.md - Installation and quick start guide
- DOCS.md - Comprehensive technical documentation
- CONFIGURATION.md - Complete configuration reference
- SETUP.md - Developer setup and publishing guide
- IMPLEMENTATION.md - Detailed phase tracking and roadmap
- STATUS.md - Project status report
- CLAUDE.md - AI development context
- NetApp ONTAP integration guide
- Manual backup procedures (until Phase 5)
- Security best practices and guidelines

### Implementation Status
- Phase 1: Container Orchestration - COMPLETED
- Phase 2: PKI Initialization - COMPLETED (including CA import/generate)
- Phase 3: KMIP & NetApp Handshake - COMPLETED
- Phase 4: Web Management Interface - NOT STARTED
- Phase 5: Encrypted Backup Integration - NOT STARTED

### Security
- Password-protected Root CA private key
- Automatic secure file permissions
- Configuration validation on startup
- Web UI password requirement enforcement
- Mutual TLS for KMIP connections
