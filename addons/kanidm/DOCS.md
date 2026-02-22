
[![Donate via PayPal][paypal-badge]](https://www.paypal.com/donate/?hosted_button_id=5RBTFAV64XGJ2)
![update-badge](https://img.shields.io/github/last-commit/cordelster/hassio-addons?label=last%20update)
[![IssueHunt](https://img.shields.io/badge/IssueHunt-%24-brightgreen.svg)](https://issuehunt.io/r/cordelster/hassio-addons)

[paypal-badge]: https://img.shields.io/badge/Donate%20via%20PayPal-0070BA?logo=paypal&style=flat&logoColor=white

# Kanidm

Modern identity management and authentication platform for Home Assistant.

Kanidm provides secure authentication services including WebAuthn/passkeys, OAuth2/OIDC, LDAP, and optional RADIUS (through another adddon). It can serve as an identity provider for web applications, network services, Linux/UNIX systems, and WiFi.

## Quick Start

### Minimum Required Configuration

1. Set `domain` - DNS domain name for user identities (e.g., `mydomain.local`)
2. Set `hostname` - Hostname part only (e.g., `kanidm` which becomes `kanidm.mydomain.local`)
3. Set `person_username` - Your initial admin username (e.g., `admin_user`)
4. Set `person_displayname` - Your full name (e.g., `Admin User`)
5. Start the addon
6. Check the logs for your password reset token (QR code, link, or CLI command)
7. Use the reset token to set your password
8. Access the web interface at `https://{hostname}.{domain}:4869` (e.g., `https://kanidm.mydomain.local:4869`)

## Configuration

### Required Settings

#### domain
- **Description**: DNS domain name for Kanidm user identities (used in user@domain format)
- **Format**: Domain name only (no protocol, no port, no path)
- **Purpose**: This is the identity suffix, NOT the access URL
- **Examples**:
  - `idm.local` (local identity domain)
  - `kanidm.internal` (internal network identity domain)
  - `yourdomain.com` (public domain for identities)
- **CRITICAL**: Never change this after initial setup - it will break WebAuthn, OAuth tokens, and all credentials

#### hostname
- **Description**: Hostname part of the FQDN (combined with domain to form hostname.domain)
- **Format**: Hostname only (no domain, no protocol, no port)
- **Purpose**: Combined with `domain` to automatically build the FQDN and Origin URL (`https://hostname.domain:4869`)
- **Requirements**:
  - Do NOT include domain suffix (domain is configured separately)
  - Do NOT include `https://` protocol
  - Do NOT include port number
- **Examples**:
  - `kanidm` (becomes `kanidm.example.com` when combined with domain)
  - `idm` (becomes `idm.yourdomain.com` when combined with domain)
- **CRITICAL**: The resulting FQDN (hostname.domain) must match EXACTLY how you access Kanidm or WebAuthn/OAuth will fail

#### person_username
- **Description**: Username for your initial person account
- **Format**: Alphanumeric, lowercase recommended
- **Usage**: This account will have full admin privileges
- **Examples**: `john`, `jsmith`, `admin_user`

#### person_displayname
- **Description**: Full name for your initial person account
- **Format**: Any text
- **Usage**: Shown in the Kanidm web UI
- **Examples**: `John Smith`, `Admin User`

### TLS Certificates (Collapsible Section)

Kanidm requires TLS certificates for all connections. Configure under the **Certificates** section.
Make sure you have your DNS configured, or you will find you can not save your credentials. 

#### certificates.type

**selfsigned** (default):
- Auto-generates a self-signed certificate in `/ssl/`
- **Good for**: Testing and internal networks only
- **Browser warning**: Expected (you'll need to accept the security exception)
- **No additional configuration needed**: Completely automatic
- **Warning**: Not suitable for production use
- You can import /ssl/JamBoxKanidm-SELFIE-CA-Chain.pem into your devices also to create the trust.
- Added check on application startup will refresh the certs if they are within 30 days of expiring.

**letsencrypt**:
- Automatically uses Let's Encrypt addon certificates from `/ssl/`
- **Good for**: Production use with Let's Encrypt addon
- **Requires**: Let's Encrypt addon installed and configured
- **Certificates used**: `/ssl/fullchain.pem` and `/ssl/privkey.pem` (automatic paths)
- **No path configuration needed**: Just select "letsencrypt" and go!
- **Important**: Your `hostname` should match your Let's Encrypt certificate domain

**custom**:
- Use your own certificate files from `/ssl/` directory
- **Good for**: Enterprise CAs, custom certificates, advanced setups
- **Requires**: `certificates.chain_path` and `certificates.key_path` must be configured
- **Location**: Place certificate files anywhere in Home Assistant's `/ssl/` directory

#### certificates.chain_path (optional)
- **Required When**: `certificates.type = custom`
- **Description**: Path to TLS certificate chain file (PEM format)
- **Location**: Relative to `/ssl/` directory (do NOT include /ssl/ prefix)
- **Examples**:
  - `my-domain/fullchain.pem` (files in subdirectory)
  - `custom-certs/cert.pem` (alternative naming)
- **Leave empty** for selfsigned or letsencrypt modes

#### certificates.key_path (optional)
- **Required When**: `certificates.type = custom`
- **Description**: Path to TLS private key file (PEM format)
- **Location**: Relative to `/ssl/` directory (do NOT include /ssl/ prefix)
- **Examples**:
  - `my-domain/privkey.pem` (files in subdirectory)
  - `custom-certs/key.pem` (alternative naming)
- **Leave empty** for selfsigned or letsencrypt modes

### Network Configuration

**Internal Ports (Fixed)**: Kanidm runs on these standard ports internally:
- **4869**: HTTPS web interface
- **3636**: LDAPS (encrypted LDAP over SSL)
- **8444**: Replication (mutual-pull synchronization)

**External Port Mapping**: You can change the external port mapping in Home Assistant's addon **Network settings** (not in the addon configuration). The internal ports remain fixed to ensure stable client configurations.

**Access URL**: `https://{hostname}.{domain}:4869` (or your custom external port if changed in Network settings)

#### enable_ldap
- **Description**: Enable read-only LDAP interface for legacy applications
- **Default**: true
- **When to Enable**: Set to true if you have applications that require LDAP
- **Protocol**: LDAPS only (encrypted LDAP over TLS on port 3636)

### Database Tuning (Collapsible Section - Advanced)

#### database.fs_type
- **Description**: Filesystem type for database optimization
- **Default**: `other`
- **Options**:
  - `other`: Standard filesystems (ext4, btrfs, xfs, etc.)
  - `zfs`: ZFS filesystem (optimizes page size)
- **When to Use ZFS**: Only if your Home Assistant `/data/` directory is on ZFS

#### database.arc_size
- **Description**: In-memory cache size (number of entries, not bytes)
- **Default**: 0 (auto-calculate based on available memory)
- **Minimum**: 256
- **Recommendation**: Leave at 0 unless you have specific performance needs, which you might want to consider a different type of install, the setting is here none the less
- **Effect**: Higher values improve performance but consume more RAM

### Backup Configuration

Kanidm includes automatic online backup that runs while the server is operational.

#### enable_backup
- **Description**: Enable automatic scheduled backups
- **Default**: true
- **Recommendation**: Keep enabled for production use

#### backup_schedule
- **Description**: Cron schedule for automatic backups
- **Default**: `"00 22 * * *"` (daily at 22:00 UTC)
- **Format**: Standard cron format: `minute hour day month weekday`
- **Examples**:
  - `"00 22 * * *"`: Daily at 22:00 UTC
  - `"00 02 * * 0"`: Weekly on Sunday at 02:00 UTC
  - `"00 04 1 * *"`: Monthly on the 1st at 04:00 UTC

#### backup_versions
- **Description**: Number of backup versions to retain
- **Default**: 7 (one week of daily backups)
- **Recommendation**: Adjust based on your backup schedule
  - Daily backups: 7 (one week)
  - Weekly backups: 4 (one month)

### Logging Configuration

#### log_level
- **Description**: Logging verbosity
- **Default**: `info`
- **Options**:
  - `info`: Normal operation messages (recommended for production)
  - `debug`: Detailed debugging information
  - `trace`: Very verbose tracing (use only for troubleshooting)
- **Note**: Kanidm does not support `warn` or `error` log levels, as such they are left out to keep kanidm from panic attacks

### Directory Sync Configuration (LDAP and FreeIPA)

Kanidm can synchronize users and groups from external directory services:
- **LDAP directories**: LLDAP, OpenLDAP, Active Directory, etc.
- **FreeIPA**: Red Hat Identity Management / FreeIPA

This allows you to maintain a single source of truth in an existing directory while using Kanidm's modern authentication features (WebAuthn, OAuth2/OIDC).

#### directory_sync.enabled
- **Description**: Master switch to enable/disable all directory synchronization (LDAP and FreeIPA)
- **Default**: `false`
- **Purpose**: When disabled, no sync operations run regardless of individual source settings
- **Use Case**: Quick way to disable all syncs without losing configuration

#### Configuring Directory Sync Sources

The addon supports up to **5 concurrent directory sync sources** via the `directory_sync.sources` array.

**In the Home Assistant UI**: Click the **"Add item"** button to configure each source. Each source can be configured as either LDAP or FreeIPA type.

**In YAML configuration**: Add sources to the `directory_sync.sources` array.

**Common Configuration Fields (All Source Types):**

1. **enabled** (bool): Enable this specific sync source
2. **name** (string): Unique name (alphanumeric, no spaces)
   - Used in config filenames and logs
   - Examples: `lldap-prod`, `openldap-backup`, `ad-users`, `freeipa-main`

3. **sync_type** (string): Type of directory - `ldap` or `ipa`
   - `ldap`: Generic LDAP directories (LLDAP, OpenLDAP, Active Directory)
   - `ipa`: FreeIPA / Red Hat Identity Management

4. **sync_token** (password): Kanidm sync authentication token
   - Generate using: `kanidm system sync generate-token`
   - See "Generating Sync Tokens" section below

5. **schedule** (string): Cron-like schedule (7 fields)
   - Format: `second minute hour day month day-of-week year`
   - Default: `"0 */10 * * * * *"` (every 10 minutes)
   - Examples:
     - `"0 */5 * * * * *"` - Every 5 minutes
     - `"0 0 * * * * *"` - Every hour
     - `"0 0 */6 * * * *"` - Every 6 hours

**LDAP-Specific Configuration Fields (when sync_type=ldap):**

6. **ldap_uri** (string): LDAP/LDAPS connection URL
   - **Must use ldaps://** for secure connections
   - Examples:
     - `ldaps://lldap.local:6360` (LLDAP)
     - `ldaps://192.168.1.50:636` (OpenLDAP)
     - `ldaps://ad.company.com:636` (Active Directory)

7. **ldap_ca** (string): Path to CA certificate
   - Relative to `/ssl/` (e.g., `lldap/ca.pem`)
   - Or absolute path (e.g., `/ssl/custom/ca.crt`)
   - Required for LDAPS certificate validation

8. **ldap_sync_dn** (string): Bind DN for authentication
   - Examples:
     - `cn=admin,ou=people,dc=example,dc=com` (LLDAP)
     - `cn=Administrator,cn=Users,dc=company,dc=local` (Active Directory)

9. **ldap_sync_pw** (password): Password for bind DN

10. **ldap_sync_base_dn** (string): Search base DN
    - Examples:
      - `dc=example,dc=com` (LLDAP/OpenLDAP)
      - `dc=company,dc=local` (Active Directory)

11. **ldap_filter** (string): LDAP search filter
    - Default: `"(|(objectClass=person)(objectClass=group))"`
    - Customizable to filter specific OUs or attributes

12-17. **Attribute Mappings**: Map LDAP attributes to Kanidm fields
    - `person_objectclass`: Default `"person"`
    - `person_attr_id`: Default `"uid"`
    - `person_attr_displayname`: Default `"cn"`
    - `person_attr_mail`: Default `"mail"`
    - `group_objectclass`: Default `"group"`
    - `group_attr_name`: Default `"cn"`
    - `group_attr_member`: Default `"member"`

**FreeIPA-Specific Configuration Fields (when sync_type=ipa):**

6. **ipa_uri** (string): LDAPS connection URL
   - Must connect directly to a specific FreeIPA server (not load balancer)
   - Example: `ldaps://ipa.example.com:636`

7. **ipa_ca** (string): Path to FreeIPA CA certificate
   - Typically `/etc/ipa/ca.crt` on enrolled systems
   - Can be relative to `/ssl/` or absolute path

8. **ipa_sync_dn** (string): Account with content sync rights
   - Default FreeIPA admin: `cn=Directory Manager`
   - For production, create a dedicated sync account

9. **ipa_sync_pw** (password): Password for FreeIPA bind DN

10. **ipa_sync_base_dn** (string): Base DN to examine
    - Example: `dc=ipa,dc=example,dc=com`
    - Found in FreeIPA's LDAP configuration

**FreeIPA Advanced Options (Optional):**

11. **skip_invalid_password_formats** (bool): Treat malformed passwords as "no password"
    - Useful for migration from systems with incompatible password hashes
    - Default: `false`

12. **sync_password_as_unix_password** (bool): Sync passwords to unix credentials
    - Allows gradual migration by initially syncing passwords to unix credentials
    - Default: `false`

13. **status_bind** (string): Health monitoring endpoint
    - TCP address:port for Nagios-style health checks
    - Example: `127.0.0.1:8090`
    - Leave empty to disable

14-18. **Per-Entry Customization** (Expert Features - comma-separated syncuuid:value pairs):
    - `exclude_entries`: Exclude specific entries from sync
    - `map_uuid`: Remap entry UUIDs
    - `map_name`: Rename entries during sync
    - `map_gidnumber`: Reassign group ID numbers
    - `map_uidnumber`: Reassign user ID numbers
    - See [Kanidm FreeIPA Sync Docs](https://kanidm.github.io/kanidm/master/sync/freeipa.html) for details

#### Generating Sync Tokens

Before configuring LDAP sync, you need to generate a sync token from Kanidm:

**From a Remote Client:**
```bash
# Login to Kanidm
kanidm login -H https://your-kanidm-url:4869 -D admin

# Generate sync token
kanidm system sync generate-token my-ldap-sync --description "LLDAP Production Sync"
```

**From the Addon CLI:**
Requires Advanced SSH & Web Terminal addon, with protection mode off.
```bash
# Login as admin
docker exec addon_local_kanidm kanidm -H https://localhost:4869 --accept-invalid-certs login -D admin

# Generate token
docker exec addon_local_kanidm kanidm system sync generate-token my-ldap-sync --description "LLDAP Sync"
```

The command outputs a token like `eyJhbGciOiJF...`. Copy this token to the `sync_token` configuration field.

#### Example Configuration: Syncing from LLDAP

```yaml
directory_sync:
  enabled: true
  sources:
    # LLDAP Production Server
    - enabled: true
      name: "lldap-prod"
      sync_type: "ldap"
      sync_token: "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9..."
      schedule: "0 */10 * * * * *"
      ldap_uri: "ldaps://lldap.local:6360"
      ldap_ca: "lldap/ca.pem"
      ldap_sync_dn: "cn=admin,ou=people,dc=example,dc=com"
      ldap_sync_pw: "your_lldap_admin_password"
      ldap_sync_base_dn: "dc=example,dc=com"
      ldap_filter: "(|(objectClass=person)(objectClass=group))"
      person_objectclass: "person"
      person_attr_id: "uid"
      person_attr_displayname: "cn"
      person_attr_mail: "mail"
      group_objectclass: "group"
      group_attr_name: "cn"
      group_attr_member: "member"

    # LLDAP Backup Server (optional - second source)
    - enabled: true
      name: "lldap-backup"
      sync_type: "ldap"
      sync_token: "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9..."
      ldap_uri: "ldaps://lldap-backup.local:6360"
      # ... (similar configuration for backup server)
```

#### Example Configuration: Syncing from FreeIPA

```yaml
directory_sync:
  enabled: true
  sources:
    # FreeIPA Production Server
    - enabled: true
      name: "freeipa-main"
      sync_type: "ipa"
      sync_token: "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9..."
      schedule: "0 */10 * * * * *"
      ipa_uri: "ldaps://ipa.example.com:636"
      ipa_ca: "freeipa/ca.crt"
      ipa_sync_dn: "cn=Directory Manager"
      ipa_sync_pw: "your_directory_manager_password"
      ipa_sync_base_dn: "dc=ipa,dc=example,dc=com"
      # Advanced options (optional)
      skip_invalid_password_formats: false
      sync_password_as_unix_password: false
      status_bind: ""
      exclude_entries: ""
      map_uuid: ""
      map_name: ""
      map_gidnumber: ""
      map_uidnumber: ""
```

#### How Directory Sync Works

1. **Configuration Files**: The addon generates `/config/sync/ldap-sync-{name}.toml` or `/config/sync/ipa-sync-{name}.toml` for each enabled source
2. **Cron Jobs**: Cron jobs run `kanidm-sync` (LDAP) or `kanidm-ipa-sync` (FreeIPA) every 10 minutes (or per your schedule)
3. **Sync Process**:
   - Connects to external directory via LDAPS
   - Reads users and groups (using filter for LDAP, automatic for FreeIPA)
   - Synchronizes to Kanidm using the sync token
4. **Logs**: Sync logs are written to `/var/log/kanidm-sync/ldap-{name}.log` or `/var/log/kanidm-sync/ipa-{name}.log`

#### Monitoring Directory Sync

**View Sync Logs:**
```bash
# View logs for a specific LDAP sync source
docker exec addon_local_kanidm tail -f /var/log/kanidm-sync/ldap-lldap-prod.log

# View logs for a specific FreeIPA sync source
docker exec addon_local_kanidm tail -f /var/log/kanidm-sync/ipa-freeipa-main.log

# View all sync source logs
docker exec addon_local_kanidm ls -la /var/log/kanidm-sync/
```

**Check Cron Jobs:**
```bash
docker exec addon_local_kanidm crontab -l
```

**Manually Trigger Sync:**
```bash
# LDAP sync
docker exec addon_local_kanidm kanidm-sync -c /config/sync/ldap-sync-lldap-prod.toml

# FreeIPA sync
docker exec addon_local_kanidm kanidm-ipa-sync -c /config/sync/ipa-sync-freeipa-main.toml
```

#### Troubleshooting Directory Sync

**Sync Not Running:**
- Check `directory_sync.enabled` is `true`
- Check source is `enabled: true`
- Verify `sync_type` is set to `ldap` or `ipa`
- Verify sync token is valid
- Check addon logs for configuration errors

**LDAPS Connection Fails:**
- Verify URI uses `ldaps://` protocol
- Check CA certificate path is correct
- Ensure CA certificate file exists in `/ssl/`
- For FreeIPA: Ensure connecting to specific server (not load balancer)

**No Users/Groups Syncing:**
- **LDAP**: Verify `ldap_filter` matches your LDAP schema
- **LDAP**: Check attribute mappings match your LDAP server
- **FreeIPA**: Verify base DN is correct
- Review sync logs for specific errors
- Verify bind DN has read permissions

**Certificate Errors:**
- Ensure CA certificate is in PEM format
- Check certificate path (relative to `/ssl/` or absolute)
- Verify directory server certificate is signed by the CA
- For FreeIPA: Typically use `/etc/ipa/ca.crt` from enrolled system

### Replication Configuration (Collapsible Section - High Availability)

Kanidm supports multi-server replication for high availability using mutual-pull synchronization. This allows you to run multiple Kanidm instances that automatically sync data between them.

#### replication.enabled
- **Description**: Master switch to enable/disable replication
- **Default**: `false`
- **Purpose**: When enabled, this server participates in multi-server replication
- **Port**: Runs on standard port 8444 (repl protocol)
- **Requirements**: At least one replication partner must be configured

#### Configuring Replication Partners

The addon supports multiple replication partners via the `replication.partners` array.

**In the Home Assistant UI**: Click the **"Add item"** button to configure each partner server.

**Partner Configuration Fields:**

1. **origin** (string): Replication origin URL of the partner server
   - Format: `repl://hostname.domain:8444`
   - Example: `repl://kanidm2.example.com:8444`
   - Must be a different Kanidm server's replication endpoint

2. **certificate** (string): Partner's replication certificate
   - Retrieve from partner using: `kanidmd show-replication-certificate`
   - Copy the full certificate text (starts with `-----BEGIN CERTIFICATE-----`)
   - Paste the complete certificate here

3. **automatic_refresh** (bool): Enable automatic refresh for this partner
   - **Set to `true`** if THIS node acts as a secondary/read-only node relative to this partner
   - **Set to `false`** if THIS node acts as a primary/write node relative to this partner
   - This setting is per-partner, allowing flexible topologies

#### Example Replication Configuration

**Two-Node Setup** (Primary-Secondary):

```yaml
replication:
  enabled: true
  partners:
    # Primary node (kanidm1) - THIS node automatically refreshes from primary
    - origin: "repl://kanidm1.example.com:8444"
      automatic_refresh: true
      certificate: |
        -----BEGIN CERTIFICATE-----
        MIIBkTCCATegAwIBAgIIYj...
        -----END CERTIFICATE-----
```

**Three-Node Mesh** (Multi-Primary):

```yaml
replication:
  enabled: true
  partners:
    # Partner 1 - Equal peer (no automatic refresh)
    - origin: "repl://kanidm1.example.com:8444"
      automatic_refresh: false
      certificate: |
        -----BEGIN CERTIFICATE-----
        MIIBkTCCATegAwIBAgIIYj...
        -----END CERTIFICATE-----

    # Partner 2 - Equal peer (no automatic refresh)
    - origin: "repl://kanidm2.example.com:8444"
      automatic_refresh: false
      certificate: |
        -----BEGIN CERTIFICATE-----
        MIIBkTCCATegAwIBAgIIZm...
        -----END CERTIFICATE-----
```

#### Setting Up Replication

1. **On Primary Server** (kanidm1):
   - Run: `kanidmd show-replication-certificate`
   - Copy the certificate output

2. **On Secondary Server** (kanidm2):
   - Configure replication partner pointing to kanidm1
   - Paste kanidm1's certificate
   - Set `automatic_refresh: true` (secondary refreshes from primary)

3. **On Primary Server** (kanidm1):
   - Configure replication partner pointing to kanidm2
   - Get kanidm2's certificate: `kanidmd show-replication-certificate`
   - Paste kanidm2's certificate
   - Set `automatic_refresh: false` (primary doesn't refresh from secondary)

4. **Verify Replication**:
   - Check Kanidm logs for replication status
   - Create a test user on primary, verify it appears on secondary

**Important Notes:**
- Replication requires network connectivity on port 8444 between all nodes
- Use firewall rules to restrict access to replication ports
- TLS certificates are automatically used for replication security
- See [Kanidm Replication Docs](https://kanidm.github.io/kanidm/master/repl/deployment.html) for advanced topologies

## First Run Setup

### Step 1: Configure the Addon

Set the required configuration options:
- `domain`: Your Kanidm identity domain (e.g., `idm.local`)
- `hostname`: Hostname part only (e.g., `kanidm` becomes `kanidm.idm.local` with domain)
- `person_username`: Your admin username (e.g., `admin_user`)
- `person_displayname`: Your full name (e.g., `Admin User`)
- `certificates.type`: Choose `selfsigned` for testing or `letsencrypt` for production

### Step 2: Start the Addon

Click "Start" in the Home Assistant addon interface.

The addon will:
1. Validate your configuration
2. Build the origin URL from `hostname.domain:4869`
3. Configure TLS certificates based on your selection
4. Initialize the Kanidm database
5. Create the `admin` and `idm_admin` service accounts
6. Create your person account
7. Generate a credential reset token

### Step 3: Get Your Password Reset Token

Home Assistant, by default, retains entity history and recorder data for
10 days. This data, which includes detailed logs and state changes, is automatically purged after this period to manage database size.

**Check the addon logs** in Home Assistant. You'll see output like:

```
==========================================
CREDENTIAL RESET TOKEN GENERATED
==========================================

The person can use one of the following to allow the credential reset

Scan this QR Code:

█████████████████████████████████
█████████████████████████████████
████ ▄▄▄▄▄ ████ █▀▀▀ █ ▀██  ████
...
█████████████████████████████████

This link: https://homeassistant.local:4869/ui/reset?token=ABC123...
Or run this command: kanidm person credential use-reset-token ABC123...
This token will expire at: 2026-02-06T12:00:00-08:00

==========================================
IMPORTANT: Use one of the methods above to
set your password. This token expires in
24 hours.
==========================================
```

**Choose one of three methods**:
1. **Scan QR code** with your phone camera
2. **Click the link** in the logs
3. **Use CLI command** if you prefer terminal access

### Step 4: Set Your Password

Using any of the methods above:
1. You'll be prompted to choose a credential type - select **password**
2. Enter your password (minimum 10 characters, avoid repeating patterns)
3. Confirm your password
4. You'll see "Success"

### Step 5: Access the Web Interface

Navigate to `https://{hostname}.{domain}:4869` (e.g., `https://kanidm.idm.local:4869`).

**If using self-signed certificate**:
- Your browser will show a security warning
- This is expected and safe for internal use
- Click "Advanced" and proceed to accept the certificate

### Step 6: Log In

- **Username**: The username you set in `person_username` (e.g., `admin_user`)
- **Password**: The password you just set via the reset token

You can now configure Kanidm, create users, set up OAuth2 applications, etc.

### Service Account Credentials

Service account passwords are displayed in the addon logs on first run. This is a known trade-off — the logs are ephemeral (Home Assistant purges them after 10 days) and the passwords are only shown once. Community input on improving this workflow is welcome.

On first run, you'll see the `admin` and `idm_admin` service account passwords in the logs:

```
==========================================
Admin accounts initialized successfully!
==========================================

SYSTEM ADMIN (for server configuration):
  Username: admin
  Password: auto-generated-password-here

IDENTITY ADMIN (for user/group management):
  Username: idm_admin
  Password: auto-generated-password-here
==========================================
```

**These are for CLI/API use only** - use your person account for the web interface.
These are intended for break-glass purposes once you have your initial configuration in place, in case the defaults are insufficient.

## Account Types

Kanidm uses different account types for different purposes:

### Service Accounts (Built-in)

**admin**:
- **Purpose**: System/infrastructure administration
- **Permissions**: OAuth2 clients, schema, access controls, global configuration
- **Access**: CLI/API primarily (not designed for web UI)
- **Setup**: Password auto-generated and shown in addon logs on first run

**idm_admin**:
- **Purpose**: People/account administration
- **Permissions**: Create persons, credential resets, group management
- **Access**: CLI/API only (not designed for web UI)
- **Setup**: Password auto-generated and shown in addon logs on first run

### Person Accounts (User-created)

**Purpose**: Human user accounts for interactive login
- **Permissions**: Based on group membership (can be added to admin groups)
- **Access**: Web UI for self-service + administrative tasks (if in admin groups)
- **Authentication**: Interactive login with password/MFA
- **Creation**: Created during first run or via CLI/API

**Important**: The web UI is designed for person accounts. Service accounts like `admin` and `idm_admin` are meant for CLI/API automation, not web interface usage.

### Web UI Limitations

The Kanidm web admin interface was removed in recent versions unfortunately. The current web UI provides:
- Self-service features for person accounts (profile, credential management)
- OAuth2 application management (for accounts with appropriate permissions)

For full administrative control, use the Kanidm CLI:
```bash
docker exec addon_local_kanidm kanidm --help
```

### Initial Person Account

The addon automatically creates your initial person account on first run:
- **Username**: From `person_username` configuration
- **Display Name**: From `person_displayname` configuration
- **Password**: Set by you using the credential reset token (see First Run Setup)
- **Permissions**: Automatically added to `idm_admins`, `idm_people_admins`, and `idm_group_admins` groups

This person account can:
- Log in via web UI
- Manage other users and groups
- Configure OAuth2 applications
- Administer the Kanidm instance

### Creating Additional Person Accounts

To create more user accounts, use the CLI:
```bash
# Create the account
docker exec addon_local_kanidm kanidm -H https://localhost:4869 --accept-invalid-certs login -D idm_admin
docker exec addon_local_kanidm kanidm person create <username> "<Display Name>"

# Generate a reset token for them to set their password
docker exec addon_local_kanidm kanidm person credential create-reset-token <username> 86400

# Optionally add them to admin groups
docker exec addon_local_kanidm kanidm group add-members idm_admins <username>
```

## Accessing Kanidm

### Setup Home Assistant hass-oidc-auth integration
#### Requires ![hass-additional-ca](https://github.com/Athozs/hass-additional-ca)
 The Cert file "JamBoxKanidm-SELFIE-CA-Chain.pem" must be configured with hass-additional-ca and is critical for OpenID to work with kanidm
 
- Select type: OpenID
- URL: https://homeassistant.local:4869/oauth2/openid/homeassistant/.well-known/openid-configuration

### Web Interface

Access the web interface at your configured origin URL.

**Default self-signed setup**:
- URL: `https://homeassistant.local:4869`
- Accept browser security warning
- Log in with admin credentials

**Custom domain setup**:
1. Configure DNS to point your domain to Home Assistant IP
2. Set `domain` to match (e.g., `kanidm.yourdomain.com`)
3. Set `origin` to match (e.g., `https://kanidm.yourdomain.com:4869`)
4. Use Let's Encrypt HA addon or custom certificate

### LDAP Access (if enabled)

**Connection Details**:
- Protocol: LDAPS (LDAP over TLS)
- Host: Your `hostname.domain` (e.g., `kanidm.idm.local`)
- Port: 3636 (fixed internal port)
- TLS: Required (uses same certificate as web interface)

**Bind DN Format**:
- Example: `name=admin@kanidm.local`
- Replace `kanidm.local` with your configured domain

## Backup and Restore

### Automatic Online Backups

When `enable_backup = true`, Kanidm creates automatic JSON backups according to your schedule:

- **Location**: `/config/backups/` (addon_config - user-accessible and included in Home Assistant backups)
- **Format**: `kanidm_backup_YYYYMMDD_HHMMSS.json`
- **Retention**: Keeps last N versions (configurable via `backup_versions`)
- **Performance**: Backups run online without stopping the server
- **Schedule**: Default is `00 22 * * *` (10 PM daily, 2 hours before HA's midnight backup)

### Home Assistant Addon Backups

When you create an addon backup through Home Assistant:

1. Addon continues running (hot backup)
2. The addon_config directory (`/config/`) is backed up, including:
   - Automatic JSON backups (`/config/backups/`)
   - Server configuration files (`/config/config/`)
   - TLS certificates (`/config/certs/`)
   - Directory sync configurations (`/config/sync/`)
3. The `/data/` directory (containing the live database) is also backed up
4. Kanidm's scheduled JSON backups at 10 PM ensure consistency before HA's midnight backup

### Restore Procedure

**From Home Assistant Addon Backup**:
Simply restore the addon backup through Home Assistant UI - all data restores automatically.

**From Kanidm JSON Backup** (advanced):
If you need to restore from a specific Kanidm JSON backup, consult the Kanidm documentation for the `kanidmd database restore` command.

## Integration Examples

### OAuth2/OIDC Applications

Kanidm can serve as an identity provider for web applications:

1. Log in to Kanidm web interface as `admin`
2. Navigate to OAuth2 applications section
3. Create new OAuth2 client
4. Configure your application with:
   - Client ID
   - Client Secret
   - Redirect URIs
   - Scopes

**Supported Features**:
- PKCE S256 code verification
- ES256 token signatures
- HTTP basic authentication
- OpenID Connect

### RADIUS Authentication

**Requires a radius server or our kanidm-radius addon**
For network devices (WiFi, VPN, etc.):

1. Enable RADIUS account type for users in Kanidm
2. Configure network device to use Kanidm as RADIUS server
3. Users authenticate with their Kanidm credentials, or token

### Linux/UNIX Integration

Kanidm provides offline authentication for Linux systems:

1. Install `kanidm-unix` client on Linux machine
2. Configure `/etc/kanidm/config` with Kanidm server URL
3. Join system to Kanidm domain
4. Users can authenticate via SSH/PAM with cached credentials

## Security Considerations

### Password Security

**Admin Password**:
- Choose a strong, unique password
- Minimum 10 characters (Default, 12+ recommended)
- Change via Kanidm web interface if needed
- Never share admin credentials

### TLS Certificate Warnings

**Self-Signed Certificates**:
- Browser warnings are EXPECTED with self-signed certificates
- Safe for internal/testing use
- For production, use Let's Encrypt or custom trusted certificates

**Certificate Domain Matching**:
- TLS certificate CN/SAN must match your `domain` configuration
- Mismatches cause authentication failures
- WebAuthn requires exact domain matching

### Data Persistence

**What Persists**:
All Kanidm data is stored in the `/data/` directory, which is:
- ✅ Included in Home Assistant addon backups
- ✅ Preserved across addon restarts
- ✅ Preserved across addon updates
- ✅ Preserved across Home Assistant restarts

**Data Stored**:
- Database files (`/data/kanidm/kanidm.db`)
- Configuration files (`/data/kanidm/config/`)
- TLS certificates (`/data/kanidm/certs/`)
- Automatic JSON backups (`/config/backups/`)
- Initialization markers

**What Doesn't Persist**:
- ❌ **Addon uninstall**: When you uninstall the addon, ALL data is deleted
- This is by design - uninstalling completely removes the addon and its data

**Before Uninstalling**:
1. Create a Home Assistant addon backup (includes `/config/backups/` automatically)
2. Optionally copy `/config/backups/` to external storage for off-site backup
3. Document any OAuth2 client configurations

**Restoring After Reinstall**:
- Restore from Home Assistant addon backup
- All data, credentials, and configurations will be restored
- No manual reconfiguration needed

## Troubleshooting

### Service Account Shows "No linked applications" in Web UI

**Symptom**: Logging in as `admin` or `idm_admin` shows "No linked applications available" or "nomatchingentries" in the web UI.

**This is Expected Behavior**:
- Service accounts (`admin`, `idm_admin`) are designed for CLI/API usage
- The web UI is designed for person accounts only
- The web admin interface was removed in recent Kanidm versions

**Solution**:
1. Use the person account created during setup (from `person_username` config)
2. Log in with that person account to access web UI features
3. For administrative tasks, use the Kanidm CLI:
   ```bash
   docker exec addon_local_kanidm kanidm --help
   ```
**Creating Additional Person Accounts**:
```bash
# From Home Assistant CLI or SSH using the Avanced SSH Addon
# First, log in as idm_admin (use password from first-run logs)
docker exec addon_local_kanidm kanidm -H https://localhost:4869 --accept-invalid-certs login -D idm_admin

# Create the person account
docker exec addon_local_kanidm kanidm person create <username> "<Display Name>"

# Generate a reset token (valid for 24 hours)
docker exec addon_local_kanidm kanidm person credential create-reset-token <username> 86400

# Send the reset token to the user - they use it to set their password
# Optionally add them to groups, example to add another admin:
docker exec addon_local_kanidm kanidm group add-members idm_admins <username>
```

### Person Account Cannot Log In

**Symptom**: Person account created but login fails with "invalid credential state" or "account has no available credentials".

**Root Cause**: User hasn't set their password yet, or authentication policy requires MFA but only password was set.

**Solution**: This is automatically handled by the addon. On first run, the addon:
1. Creates the person account
2. Generates a credential reset token for you to set your password

If you still experience this issue:
1. Check addon logs for "Configuring authentication policy" message
2. Verify the policy command succeeded
3. Make sure you've set your password using the reset token
4. If needed, generate a new reset token (see "Creating Additional Person Accounts" above)

### Cannot save password or MFA
**Solution**: Do not use the IP address to access the Web UI — security requirements in the application require a DNS FQDN.
1. If you are using the self-generated certificates, you will be limited to Password/TOTP only
2. If you are using your own CA, the CA certificate must be trusted by the client you are using to access the UI. Certificates must be configured correctly.


### Cannot Access Web Interface

**Check Configuration**:
Verify your `domain` and `hostname` are correct:
```yaml
domain: "idm.local"
hostname: "kanidm"
```

The addon builds above example configuration origin as: `https://kanidm.idm.local:4869`

**Check Port**:
Ensure port 4869 is not blocked by firewall or already in use. You can change the external port mapping in the addon's Network settings if needed.

**Check Logs**:
Review addon logs in Home Assistant UI for startup errors. Look for "Built ORIGIN=" message.

### WebAuthn/Passkey Registration Fails

**Domain Matching**:
- `hostname` must match EXACTLY what appears in your browser's address bar
- `domain` is for identity purposes (user@domain) - can be different
- SSL certificate must be created correctly, trusted and configured (use `letsencrypt` for production)
- Certs should be configured with correct IP, DNS, and URI mappings


### LDAP Connection Fails

**Check LDAP Enabled**:
Ensure `enable_ldap = true` in configuration.

**Verify Certificate**:
LDAP uses same TLS certificate as web interface - must be valid.

**Check Port Access**:
Port 3636 must be accessible from client application.

### Login Fails

**Person Account**:
- Username: The value from `person_username` config
- Password: The one you set via the reset token
- If you forgot your password, generate a new reset token (see Creating Additional Person Accounts)

**Service Accounts**:
- `admin` and `idm_admin` passwords are in the first-run logs
- These are for CLI/API use only, not web UI
- If you lost them, you'll need to reset the database (delete `/data/kanidm.db` and restart)

### Backup Failures

**Check Disk Space**:
Ensure sufficient space in `/config/` for backup files. Each backup is a JSON export of the entire database.

**Verify Schedule**:
Ensure cron format is valid in `backup_schedule`.

**Check Logs**:
Review addon logs for backup-specific error messages.

## Advanced Configuration

### Custom Domain with Let's Encrypt

For production use with custom domain using HA's Let's Encrypt addon:

1. **Configure HA's Let's Encrypt addon**:
   - Set your domain (e.g., `yourdomain.com`)
   - Ensure it's working and certificate is generated in `/ssl/`

2. **Configure Kanidm addon**:
   ```yaml
   domain: "yourdomain.com"
   hostname: "idm"
   certificates:
     type: letsencrypt
   person_username: "admin_user"
   person_displayname: "Admin User"
   ```

3. **Network Setup**:
   - Configure DNS A record pointing to your HA IP
   - Forward port 443 to Home Assistant port 4869 (if external access)
   - Or change external port mapping in addon Network settings to 443

4. **First Run**:
   - Start the addon
   - Check logs for password reset token
   - Use token to set your password
   - Access at `https://idm.yourdomain.com:4869` (or `:443` if you changed port mapping)

### Custom Domain with Own Certificates

For using your own certificates:

1. **Obtain Certificates**:
   - Get certificate from your CA
   - Create directory in `/ssl/` (e.g., `/ssl/kanidm/`)
   - Save `fullchain.pem` and `privkey.pem` to `/ssl/kanidm/`

2. **Configure Kanidm addon**:
   ```yaml
   domain: "yourdomain.com"
   hostname: "kanidm"
   certificates:
     type: custom
     chain_path: "kanidm/fullchain.pem"
     key_path: "kanidm/privkey.pem"
   person_username: "admin_user"
   person_displayname: "Admin User"
   ```

3. **First Run**:
   - Start the addon
   - Check logs for password reset token
   - Use token to set your password
   - Access at `https://kanidm.yourdomain.com:4869`

### Performance Tuning

For large deployments with many users:

**Increase Cache Size**:
```yaml
database:
  arc_size: 2048
```

**Use ZFS** (if available):
```yaml
database:
  fs_type: zfs
```

**Monitor Performance**:
- Check addon logs for database performance metrics
- Adjust `database.arc_size` based on memory usage and query speed

### Backup Strategy Recommendations

**Small Deployments** (< 100 users):
```yaml
enable_backup: true
backup_schedule: "00 22 * * *"  # Daily
backup_versions: 7  # One week
```

**Large Deployments** (> 100 users):
```yaml
enable_backup: true
backup_schedule: "00 */6 * * *"  # Every 6 hours
backup_versions: 28  # One week of 6-hour backups
```

**Combined Strategy**:
- Kanidm automatic backups: Frequent (daily or more)
- Home Assistant addon backups: Weekly (via HA UI)
- External backups: Monthly (copy critical data to external storage)

## Version Management and Upgrades

This addon implements automatic version tracking and validation to ensure safe Kanidm upgrades.

### Version Tracking

On first run, the addon creates a marker file (`/config/.admin_initialized`) that tracks:
- Kanidm version (e.g., `1.8.5`)
- Addon version (e.g., `HA.1.0.1-kanidm.1.8.5`)
- Installation date and last startup time
- Applied migrations

### Sequential Upgrade Enforcement

**CRITICAL**: Kanidm requires sequential version upgrades. Skipping versions will corrupt your database.

The addon enforces this by:
- **Allowing**: 1.8.5 → 1.8.6 (patch bump)
- **Allowing**: 1.8.6 → 1.9.0 (next minor)
- **Blocking**: 1.8.5 → 1.9.1 (skipped 1.9.0)
- **Blocking**: 1.9.0 → 1.8.5 (downgrade)

### Upgrade Procedure

1. **Check Current Version**: View addon logs or check `/config/.admin_initialized`
2. **Upgrade Sequentially**: If multiple versions behind, upgrade one version at a time
3. **Backup First**: Always create a backup before upgrading
4. **Monitor Logs**: Watch for migration status and any errors

**If Upgrade Blocked**: You must install the intermediate version first.

Example: To go from 1.8.5 → 1.9.1:
1. Upgrade to 1.9.0
2. Wait for startup and migrations to complete
3. Upgrade to 1.9.1

## Support and Resources

- **Kanidm Documentation**: https://kanidm.com/docs/
- **Kanidm GitHub**: https://github.com/kanidm/kanidm
- **Home Assistant Community**: https://community.home-assistant.io/
- **Report Issues**: Check addon logs first, then report issues on the addon repository

## License

This Home Assistant addon is licensed under the MIT License.
Kanidm itself is licensed under the MPL-2.0 License.

## Developer Comments

Kanidm and LDAP in general is complex. Kudos to you if you venture into this rabbit hole, and read all the way down to my comment section, you're my type of people.

Kanidmd is designed by its developers to mostly be admin managed via its CLI tool and its WebUI recently stripped down to a self service token/password portal. Though it is highly robust, secure, and uses modern security practices in a way that probably exceeds most expectations. Also I love CLI, and this tool is well designed for its intent.

This journey as most my addons were developed out of my desire to suit my tastes, want to consolidate, reduce my power bill, since I run NetApp, Pure, Cisco, Brocade, type enterprise gear, and typically follow along with my experience in corporate datacenter principals and practices which I bring that experience into these little niche projects that most, likely are not going to jump into or use.

My stack, now that Kanidm dropped user management is I sync off [einschmidt lldap addon](https://github.com/einschmidt/hassio-addons) for users and groups, then manage the rest of my homelab in Kanidm. Though each LDAP is like a box of chocolate...

To that end, I tried to give some good examples, and your google skills may get a workout, mine still do.

Hope you find your DNS resolving and your Cert's authentic. 

[kofi-badge]: https://img.shields.io/badge/Donate%20via%20KoFi-0070BA?logo=kofi&style=flat&logoColor=white
[![Donate via ko-fi][kofi-badge]](https://ko-fi.com/L3L0V38OP)