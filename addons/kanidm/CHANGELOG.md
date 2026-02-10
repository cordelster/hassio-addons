# Changelog

All notable changes to this addon will be documented in this file.

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
