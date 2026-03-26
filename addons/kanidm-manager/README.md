[![Donate via PayPal][paypal-badge]](https://www.paypal.com/donate/?hosted_button_id=5RBTFAV64XGJ2)
![update-badge](https://img.shields.io/github/last-commit/cordelster/hassio-addons?label=last%20update)
[![IssueHunt](https://img.shields.io/badge/IssueHunt-%24-brightgreen.svg)](https://issuehunt.io/r/cordelster/hassio-addons)


[paypal-badge]: https://img.shields.io/badge/Donate%20via%20PayPal-0070BA?logo=paypal&style=flat&logoColor=white

# Kanidm Manager - Home Assistant Addon

Web-based UI for managing Kanidm OAuth2 clients, users, and groups.

## About

This addon provides a user-friendly web interface for managing your Kanidm identity management server. It wraps the excellent [kanidm-oauth2-manager](https://github.com/Tricked-dev/kanidm-oauth2-manager) project by Tricked-dev as a Home Assistant addon with ingress sidebar integration.

## Features

- OAuth2 client management
- User and person account management
- Group management and membership
- Credential and MFA configuration
- Home Assistant sidebar integration (admin-only)
- Secure internal communication with Kanidm addon

## Prerequisites

- **Kanidm addon** must be installed and running
- **idm_admin password** from Kanidm addon logs

## Quick Start

1. Install the Kanidm addon (if not already installed)
2. Install this addon
3. Configure connection settings:
   ```yaml
   kanidm_url: "https://addon_local_kanidm:4869"
   kanidm_username: "idm_admin"
   kanidm_password: "password-from-kanidm-logs"
   ```
4. Start the addon
5. Access via Home Assistant sidebar: "Kanidm Manager"

## Configuration

See [DOCS.md](DOCS.md) for detailed configuration options and troubleshooting.

## Support

- [Kanidm Documentation](https://kanidm.com/docs/)
- [Upstream Project](https://github.com/Tricked-dev/kanidm-oauth2-manager)
- [Report Issues](https://github.com/cordelster//hassio-addons/issues)

## Credits

This addon wraps the [kanidm-oauth2-manager](https://github.com/Tricked-dev/kanidm-oauth2-manager) by Tricked-dev.

## License

See upstream project for license information.

[kofi-badge]: https://img.shields.io/badge/Donate%20via%20KoFi-0070BA?logo=kofi&style=flat&logoColor=white
[![Donate via ko-fi][kofi-badge]](https://ko-fi.com/L3L0V38OP)
