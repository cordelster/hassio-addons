# Changelog

All notable changes to this addon will be documented in this file.
## [1.0.7] - 2026-02-19
  **UPDATE Discriptions**: Minor document updates.

## [1.0.6] - 2026-02-18

  **SECURITY PATCH**: block cloud metadata SSRF and add API path allowlist:
  - fetch-icon: block file://, ftp:// schemes and 169.254.169.254 (IMDSv1/v6)
    with loud warning logs if the metadata endpoint is probed
  - fetch-icon: apply same block to HTML-parsed icon href redirects
  - kani proxy: allowlist valid Kanidm API path prefixes (v1/oauth2,
    v1/group, v1/person, v1/account) and reject path traversal attempts
  **fix**: use $app/paths base for subpath/ingress compatibility
    All absolute-path fetch() calls and img src attributes now use the
    SvelteKit `base` from `$app/paths`, allowing deployment under a
    URL subpath (e.g. Home Assistant ingress at /api/hassio_ingress/{token}/).

  When paths.base is '' (default), all paths evaluate identically to
  before — fully backward compatible.

## [1.0.5] - 2026-02-11
- Fork upstream modify to allow multi arch builds
- Modify arch and source, we maintain our own unless a PR is accepted.

## [1.0.1] - 2026-02-06
- Add Documentation and prep for https://github.com/cordelster/hassio-addons

### Documentation
- DOCS.md with setup instructions
- Troubleshooting guide
- Security considerations
- Access methods (sidebar and direct port)

## [1.0.0] - 2025-09-11

### Added
- Initial release of Kanidm Manager addon for Home Assistant
- Wraps [kanidm-oauth2-manager](https://github.com/Tricked-dev/kanidm-oauth2-manager) Docker image
- Home Assistant ingress support for sidebar integration
- Admin-only panel access
- Auto-configuration for local Kanidm addon connection
- Web-based management interface for:
  - OAuth2 clients
  - Users and person accounts
  - Groups and memberships
  - Self-service credential management

### Configuration
- Simple 3-field configuration (URL, username, password)
- Automatic internal hostname resolution (`slug_kanidm`)
- Support for external/custom domain Kanidm instances


## Credits

This addon wraps the work by Tricked-dev: https://github.com/Tricked-dev/kanidm-oauth2-manager
