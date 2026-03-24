# ha-stepca — Setup & Configuration Guide

## Overview

ha-stepca provides a full PKI (Public Key Infrastructure) for Home Assistant and your local
network, built on [step-ca](https://smallstep.com/docs/step-ca) and managed through the
Alpine Configuration Framework (ACF) web UI.

The CA issues TLS certificates for Home Assistant itself, for other local services you define,
and optionally for any ACME client on your network.

---

## Step 1 — Set a Static IP and Hostname on the Home Assistant Host

The CA's TLS certificate is generated at initialization time and locked to the hostname you
configure. If the host IP changes later, your DNS record breaks and every step CLI call and
ACME client will fail.

Assign a static IP to the HA host through one of:
- Your router's DHCP reservation (preferred — no changes needed on HA itself)
- A static IP configured directly on the HA network interface

Choose a meaningful, stable FQDN for the CA host — e.g. `pki.home.lab`. You will use this
name in addon configuration (step 3) and it will be baked into the CA's TLS certificate at
initialization time (step 4). It cannot be changed without re-initializing the CA.

---

## Step 2 — Create a DNS A Record

step-ca embeds the configured hostname into its TLS certificate as a Subject Alternative Name
at init time. The hostname must be resolvable via standard DNS before you initialize the CA —
mDNS (`.local`) is not sufficient because ACME challenge validation and step CLI connections
both require it.

Create an A record in your internal DNS (Pi-hole, AdGuard Home, router, bind, etc.):

```
<hostname>.<domain_name>  →  <static_IP>
```

Example — if you set hostname to `pki` and domain name to `home.lab`:

```
pki.home.lab  →  192.168.1.50
```

Verify it resolves from another host on your network before proceeding:

```sh
nslookup pki.home.lab
```

> **Why this order matters:** step-ca's intermediate CA certificate has the FQDN baked into
> its SAN at `step ca init` time. Changing the hostname afterwards requires a full CA
> re-initialization — all previously issued certificates remain valid but the CA's own TLS
> identity changes, breaking all existing client trust stores and ACME clients.

---

## Step 3 — Configure and Start the Addon

Install the addon and configure it **before** starting it for the first time. The CA is not
initialized at this stage — step-ca will not start until after the Setup Wizard runs in step 4.

### Required Settings

Open the addon **Configuration** tab in Home Assistant:

| Setting | Value | Notes |
|---|---|---|
| `hostname` | `pki` | Short hostname only — no domain |
| `domain_name` | `home.lab` | Your internal domain |

The addon constructs the CA's FQDN as `hostname.domain_name`. This must exactly match the
DNS A record you created in step 2.

### HA Integration (Managed Certificates)

When **HA Integration** is enabled, the addon automatically issues and renews TLS certificates
for Home Assistant and any services you define under **Custom Certs**. Enable **Default Certs**
to automatically issue a certificate for `hostname.domain_name`.

For each custom cert, set the common name, any additional SANs (comma-separated), and the
desired validity period. Enable **HA Base SANs** to also include `hostname.domain_name` as a
SAN on the custom cert.

Managed certs are issued automatically after the CA is initialized (step 4).

### Backup Settings

Configure backup before starting so the first automated backup runs correctly after init.
Enable backups, set the interval and retention count, and choose a backup location
(`share` writes to `/share/pki-backups/`; `addon_config` stores backups within the addon's
own data directory).

See the [Backup section](#backup-and-recovery) for encryption key setup.

### Start the Addon

Once configuration is saved, start the addon. The ACF web UI will redirect to the Setup Wizard
when you first open it via ingress.

---

## Step 4 — Initialize the CA via Ingress

Open the addon web UI through Home Assistant ingress:

**Home Assistant → ha-stepca → Open Web UI**

The UI will automatically redirect to the CA Setup Wizard.

### Setup Wizard Fields

| Field | Guidance |
|---|---|
| **Root CA Name** | Display name, e.g. `Home Lab Root CA` |
| **Provisioner Name** | Name for the default JWK provisioner, e.g. `admin` |
| **CA Password** | Strong password — encrypts the CA private keys on disk. **Store this securely.** |
| **Intermediate Validity** | How long the intermediate CA cert is valid. Must be less than the root CA lifetime (root is ~10 years). Recommended: 5 years. |
| **Default Cert Validity** | Validity for issued leaf certificates. Recommended: 90 days with automated renewal. |

After submitting, the wizard runs `step ca init` using the FQDN from your addon configuration.
step-ca starts automatically on success and the CA is ready to issue certificates.

> **Save your CA password.** It is required to restart step-ca after a reboot and for recovery
> scenarios. It is stored encrypted on disk but you need it for any command-line operations.

### Configure Authority Limits After Init

By default step-ca caps TLS certificate validity at 24 hours. Raise this immediately after
initializing or managed cert renewals will fire daily regardless of configured validity.

**Step CA → Configuration → Manage Global CA Limits**

Set `maxTLSCertDuration` to match your intended maximum, e.g.:
- `2160h` for 90-day certificates
- `8760h` for 1-year certificates

---

## Step 5 — Retrieve and Install the Root CA Certificate

Before any device can trust certificates issued by your CA, it must trust the Root CA.

The Root CA certificate is served directly by step-ca at:

```
https://<hostname>.<domain_name>/roots.pem
```

Because the CA's TLS certificate is issued by itself, the first retrieval must bypass
certificate verification:

```sh
curl -k https://pki.home.lab/roots.pem -o root_ca.pem
```

The CA fingerprint is displayed on the **Step CA → Status** page in the ACF web UI and can
be used to verify the downloaded certificate is authentic.

### Installing the Root CA

| Platform | Method |
|---|---|
| **Linux** | Copy to `/usr/local/share/ca-certificates/` and run `update-ca-certificates` |
| **macOS** | Open in Keychain Access → add to System keychain → mark as Always Trust |
| **Windows** | Double-click the `.crt` file → Install → Trusted Root Certification Authorities |
| **iOS** | Email or AirDrop the file → install profile → enable full trust in Settings |
| **Android** | Settings → Security → Install certificate |
| **Firefox** | Preferences → Privacy & Security → Certificates → Import |
| **Home Assistant** | See below |

### Trusting the Root CA in Home Assistant

Home Assistant does not use the host OS trust store. The correct way to add a custom Root CA
is the **Additional CA Certificates** integration:

1. Place `root_ca.pem` in your HA config directory under `additional_ca_certificates/`
   (create the folder if it doesn't exist): `/config/additional_ca_certificates/root_ca.pem`
2. Restart Home Assistant

HA's internal HTTP client will then trust certificates issued by your CA for outbound
connections (webhooks, integrations, etc.).

For **addons and integrations** that make their own TLS connections — such as MQTT brokers,
reverse proxies, or custom integrations — check whether the addon provides a configuration
option for a CA certificate path. Many do, and pointing them directly at `/ssl/root_ca.pem`
(or wherever you store it) is cleaner than relying on system trust. Each addon runs in its
own container and will not automatically pick up the Additional CA Certificates setting.

---

## Step 6 — Configure Provisioners and ACME Clients

The Setup Wizard creates one JWK provisioner. From **Step CA → Provisioners** you can manage
provisioners and add new ones.

### ACME Provisioner (Recommended for Automated Clients)

Add an ACME provisioner to allow certbot, acme.sh, Caddy, Traefik, and other ACME-compatible
tools to request certificates automatically.

1. **Provisioners → Add Provisioner → Type: ACME**
2. Set a name (e.g. `acme`)
3. Optionally enable **Require EAB** — prevents unauthorized clients from registering.
   When enabled, generate EAB keys per-client under **Provisioners → Manage EAB Keys**.
4. Save and restart step-ca when prompted

The ACME directory URL for clients is displayed on the Provisioners page:

```
https://<hostname>.<domain_name>/acme/<provisioner-name>/directory
```

### Configuring ACME Clients

Clients must be pointed at your CA's directory URL and must trust your Root CA certificate.

**certbot:**
```sh
certbot certonly \
  --server https://pki.home.lab/acme/acme/directory \
  --standalone \
  --ca-certs /path/to/root_ca.pem \
  -d myservice.home.lab
```

**acme.sh:**
```sh
acme.sh --issue \
  --server https://pki.home.lab/acme/acme/directory \
  -d myservice.home.lab \
  --standalone \
  --ca-bundle /path/to/root_ca.pem
```

**Nginx Proxy Manager** (HA community addon):

1. Install the Root CA certificate in NPM: **SSL Certificates → Custom Certificate** —
   upload `root_ca.pem` as a custom CA so NPM's ACME client trusts your CA.
2. Add a new SSL certificate: **SSL Certificates → Add SSL Certificate → Let's Encrypt**
3. Enter the domain name(s) for the proxy host
4. Under **Advanced**, set the ACME server to your CA's directory URL:
   ```
   https://pki.home.lab/acme/acme/directory
   ```
5. Complete the certificate request — NPM will use your CA instead of Let's Encrypt

> If your ACME provisioner has **Require EAB** enabled, generate an EAB key pair under
> **Step CA → Provisioners → Manage EAB Keys** and enter the Key ID and HMAC key in NPM's
> certificate request form under the EAB fields.

**Caddy** (`Caddyfile`):
```
{
  acme_ca https://pki.home.lab/acme/acme/directory
  acme_ca_root /path/to/root_ca.pem
}
```

### JWK Provisioner (Manual Issuance)

Use the JWK provisioner to issue certificates manually via the ACF web UI.
Go to **Step CA → Certificates → Create Certificate**, select the JWK provisioner, and fill
in the common name, SANs, and validity period.

---

## Backup and Recovery

> **CAUTION:** `/data` contains your Root CA private key. Loss of this data is permanent and
> unrecoverable. There is no way to regenerate the same Root CA.

### Automated Backups

Backups run automatically on the schedule configured in the addon settings. Each backup is a
7z-encrypted archive using the CA initialization password as the encryption key.
**The CA password and the backup password are the same — store it securely.**

Backup archives are written to:

| Location setting | Path |
|---|---|
| `share` | `/share/stepca/backups/` |
| `addon_config` | `/config/backups/` |

Each archive contains the full `/data/step/` tree — Root CA, intermediate CA, private keys,
database, and configuration. Old archives are pruned automatically per the retention count.

### Restoring a Backup

**Automated restore on startup** — place the archive and a `password.txt` file containing
the CA password into `/addon_configs/<addon-slug>/`, then restart the addon. The startup
process detects the archive and restores before step-ca starts.

**Manual restore via SSH** — from a shell inside the container:

```sh
pki-restore.sh pki-backup-20260101_120000.tar.7z <ca-password>
```

The script stops step-ca, makes a safety copy of current data, restores the archive, fixes
permissions, and restarts step-ca.

---

## Direct HTTPS Access (Optional)

By default the ACF web UI is only reachable through HA ingress. To enable direct HTTPS
access on port 8099, enable **Direct Access** in the addon configuration and set a username,
password, and the certificate and key filenames (relative to `/ssl/`) to use for TLS.

Enable port 8099 in the addon **Network** settings.

> Use a certificate issued by your own CA for the `certfile`/`keyfile` fields.
> Do not expose port 8099 to the internet.

---

## References

- [step-ca documentation](https://smallstep.com/docs/step-ca)
- [step CLI reference](https://smallstep.com/docs/step-cli)
- [Home Assistant Add-on Security](https://developers.home-assistant.io/docs/add-ons/security)
