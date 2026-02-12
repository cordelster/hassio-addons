
[![Donate via PayPal][paypal-badge]](https://www.paypal.com/donate/?hosted_button_id=5RBTFAV64XGJ2)
![update-badge](https://img.shields.io/github/last-commit/cordelster/hassio-addons?label=last%20update)
[![IssueHunt](https://img.shields.io/badge/IssueHunt-%24-brightgreen.svg)](https://issuehunt.io/r/cordelster/hassio-addons)

[paypal-badge]: https://img.shields.io/badge/Donate%20via%20PayPal-0070BA?logo=paypal&style=flat&logoColor=white

# Kanidm Manager

Web-based UI for managing Kanidm OAuth2 clients, users, groups, and more.

This addon provides a user-friendly web interface for managing your Kanidm instance without requiring CLI access. It wraps the excellent [kanidm-oauth2-manager](https://github.com/Tricked-dev/kanidm-oauth2-manager) by Tricked-dev.

**Important:** This addon requires the **Kanidm** addon to be installed and running.

## Quick Start

### Prerequisites

1. **Install and configure the Kanidm addon** first
2. **Note the idm_admin password** from Kanidm addon logs (shown on first run)

### Configuration

1. **Install this addon** from the addon store
2. **Configure the connection**:
   ```yaml
   kanidm_url: "https://YOUR-HA-IP:4869"
   kanidm_username: "idm_admin"
   kanidm_password: "your-password-from-kanidm-logs"
   ```
   Replace `YOUR-HA-IP` with your Home Assistant's IP address (e.g., `192.168.1.100`)
3. **Start the addon**
4. **Access via sidebar** - Click "Kanidm Manager" in Home Assistant sidebar

## Configuration Options

### kanidm_url
- **Description**: URL to your Kanidm instance
- **Required**: Yes
- **Default**: `https://192.168.120.198:4869` (example - use your HA IP)
- **Format**: Full URL with protocol and port

**For local Kanidm addon:**
```yaml
kanidm_url: "https://192.168.1.100:4869"
```
Replace `192.168.1.100` with your Home Assistant's IP address.

**For custom domain:**
```yaml
kanidm_url: "https://auth.yourdomain.com:4869"
```

**Important**: Use your Home Assistant's IP address, not `addon_local_kanidm` or `localhost`. The manager needs a routable address to connect to the Kanidm addon.

### kanidm_username
- **Description**: Kanidm admin username for management access
- **Required**: Yes
- **Default**: `idm_admin`
- **Format**: Username of a service account with admin privileges

The default `idm_admin` account is automatically created by the Kanidm addon and has permissions to manage users, groups, and OAuth2 clients.

### kanidm_password
- **Description**: Password for the admin account
- **Required**: Yes
- **Format**: Password (hidden in UI)

**Where to find this:**
1. Go to the **Kanidm addon** (not this addon)
2. Open the **Logs** tab
3. Find the section that shows:
   ```
   IDENTITY ADMIN (for user/group management):
     Username: idm_admin
     Password: auto-generated-password-here
   ```
4. Copy that password and paste it into this addon's configuration

## Features

This addon provides a web interface for:

### OAuth2 Client Management
- Create OAuth2 clients for applications
- Configure redirect URIs
- Manage client secrets
- Set scopes and permissions

### User Management
- Create new person accounts
- Generate password reset tokens
- Manage user credentials
- View and edit user attributes

### Group Management
- Create and delete groups
- Add/remove members
- Manage group permissions
- View group membership

### Self-Service Portal
- Users can manage their own credentials
- Configure MFA/WebAuthn
- Update profile information

## Access Methods

### Via Home Assistant Sidebar (Recommended)
1. Click "Kanidm Manager" in the Home Assistant sidebar
2. The interface opens with ingress (no additional login required for HA admins)

### Via Direct Port (Optional)
If you disabled ingress, access at:
- `http://homeassistant.local:3000`
- `http://your-ha-ip:3000`

## Troubleshooting

### Cannot connect to Kanidm

**Symptom**: Manager shows connection error or can't authenticate

**Solutions:**

1. **Check Kanidm addon is running**:
   - Go to Home Assistant → Settings → Add-ons
   - Verify "Kanidm" addon shows as "Started"
   - Check Kanidm addon logs for errors

2. **Verify URL is correct**:
   - For local addon: `https://addon_local_kanidm:4869`
   - For custom domain: Use your configured domain
   - URL must include `https://` protocol
   - URL must include port `:4869`

3. **Verify password is correct**:
   - Password must match what's shown in Kanidm addon logs
   - Copy password exactly (no extra spaces)
   - Password is case-sensitive

### "Invalid credentials" error

**Check username:**
- Default should be `idm_admin` (not `admin`)
- Username is case-sensitive

**Check password:**
- Get password from Kanidm addon logs, not from guessing
- Look for "IDENTITY ADMIN" section in logs
- Password was auto-generated on first Kanidm run

### Connection timeout

**Check network:**
- Ensure both addons are on same Home Assistant instance
- If using custom domain, ensure DNS resolves correctly
- Check firewall rules if using external Kanidm instance

### Addon won't start

**Check configuration:**
- Both `kanidm_url` and `kanidm_password` must be set
- URL must be valid format (https://...)
- Check addon logs for specific error messages

## Accessing from Outside Home Assistant

If you want to access the Kanidm Manager from outside your Home Assistant instance:

**Option 1: Use Home Assistant's remote access**
- Access via Home Assistant's Nabu Casa or external URL
- Login to Home Assistant
- Use sidebar to access Kanidm Manager

**Option 2: Disable ingress and use port**
1. Edit addon configuration
2. Set `ingress: false` in config (requires manual edit)
3. Access directly via `http://your-ha-ip:3000`
4. Configure reverse proxy if needed

## Security Considerations

### Admin-Only Access
- The sidebar panel is configured as admin-only
- Only Home Assistant administrators can access the manager
- Regular Home Assistant users won't see it in their sidebar

### Credentials
- idm_admin password is shown in logs on first Kanidm run only
- Store the password securely
- Consider changing it after initial setup (via Kanidm CLI)

### Network Security
- Manager connects to Kanidm using `addon_local_kanidm` (internal network)
- No external exposure required for local setup
- If exposing externally, use HTTPS and strong authentication

## Related Addons

- **Kanidm**: The identity management server (required)
- **Kanidm RADIUS**: RADIUS server for WiFi/VPN authentication (optional)

## Support and Resources

- **Kanidm Documentation**: https://kanidm.com/docs/
- **OAuth2 Manager Source**: https://github.com/Tricked-dev/kanidm-oauth2-manager
- **Report Issues**: Check addon logs first, then report on GitHub issues for the appropriate problem source. 

 **cordelster/hassio wrapper issues**: https://github.com/cordelster/hassio-addons/issues
 
## Credits

### Support up stream if you can.

This addon wraps the [kanidm-oauth2-manager](https://github.com/Tricked-dev/kanidm-oauth2-manager) by Tricked-dev.

All credit for the web interface functionality goes to the upstream project.

[kofi-badge]: https://img.shields.io/badge/Donate%20via%20KoFi-0070BA?logo=kofi&style=flat&logoColor=white
[![Donate via ko-fi][kofi-badge]](https://ko-fi.com/L3L0V38OP)
