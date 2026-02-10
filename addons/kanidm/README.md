# Home Assistant Addon: Kanidm

Home Assistant addon for running Kanidm, a modern identity management and authentication platform.

## Features
- Using Alpine foundation
- WebAuthn/Passkey authentication
- OAuth2/OIDC identity provider
- Read-only LDAP interface
- Linux/UNIX integration support
- Automatic backups with configurable retention
- SSL encryption for all connections
- Auto-recovery of admin credentials on first run

## Installation

1. Add this repository to Home Assistant addons
2. Install the "Kanidm" addon
3. Configure the addon (minimum: user, domain and hostname)
4. Start the addon
5. Check logs for auto-generated admin credentials

## Configuration

### Required Settings

- **domain**: Your Kanidm domain (e.g., `kanidm.local`)
- **origin**: Your access URL (e.g., `https://homeassistant.local:4869`)

### SSL Certificate Options

- **selfsigned** (default): Auto-generated certificate for testing
- **letsencrypt_ha**: Use Home Assistant's Let's Encrypt addon certificates
- **custom**: Provide your own certificate files

See DOCS.md for complete configuration details.

## First Run

After starting the addon, check the logs for automatically recovered admin credentials:
- Username: `admin`
- Password: Displayed in logs (save it immediately!)

Access the web interface at your configured origin URL.

## Documentation

See [DOCS.md](DOCS.md) for detailed configuration and usage instructions.

## Support

Report issues at:
- Addon specific: https://github.com/cordelster/hassio-addons/issues
- kanidm issues: https://github.com/kanidm/kanidm/issues

## Known issues
- ldap_sync is missing from the package
- python modules are missing from the build

## License

This addon is licensed under the MIT License.
Kanidm is licensed under the MPL-2.0 License.
