# Scripts & Filters Reference

This directory contains standalone filters, workers, and utility scripts used across the mail forwarding core.

---

## `pgp-encryptor-filter`

**PGP/MIME Inbound Mail Encryption Content Filter**

Implements **RFC 3156 (PGP/MIME)** and **RFC 7508 (Protected Headers / Memory Hole)** with hybrid sender rewriting and character boundary enforcement for strict DKIM/DMARC alignment.

### Key Capabilities

- **End-to-End Encryption**: Encrypts the entire MIME structure (headers, body parts, and attachments) into standard `multipart/encrypted` (`application/pgp-encrypted`) containers using the recipient's OpenPGP public key stored in MariaDB.
- **Dual Lookups with Strict Isolation**: Resolves inbound addresses first against handle-based identities (`alias_handle` table by local-part), then against address-based forwards (`alias` table). If an identity has `pgp_enabled = 0`, the filter immediately terminates lookup and passes the message through as unencrypted plaintext without modification.
- **Hybrid From-Rewriting**: Rewrites `From:` to `"Original Name (sender@domain.com)" <alias@hosted-domain.tld>` and preserves `Reply-To: sender@domain.com`. Downstream MTAs (e.g., ProtonMail, Gmail) evaluate local OpenDKIM signatures with a valid DMARC pass.
- **DoS / Header Injection Hardening**: Strips control characters and CRLF delimiters, enforces a 60-character cap on sender display names, a 254-character cap on sender email addresses, and a 150-character hard limit on total display names.
- **Subject Confidentiality**: When `pgp_hide_subject = 1`, the envelope subject is replaced with `[mail.thc.org: new encrypted email]` while the authentic subject is sealed inside the encrypted container via RFC 7508 protected headers.
- **Fail-Closed Security**: Exits with `EX_TEMPFAIL` (code 75) if an unexpected encryption error occurs for an enabled recipient, ensuring unencrypted plaintext is never accidentally leaked.

---

## Setup & Configuration Guide

### 1. Prerequisites & Dependencies

The filter requires Python 3 with `pymysql`, `pgpy`, and `standard-imghdr` (required for Python 3.13+ compatibility with `pgpy`):

```bash
sudo apt-get update
sudo apt-get install -y python3-pip python3-pymysql
sudo pip3 install pgpy standard-imghdr --break-system-packages
```

### 2. Dedicated System User & Permissions

For defense-in-depth, run the filter under a dedicated unprivileged system account:

```bash
# Create dedicated system user
sudo useradd -r -s /usr/sbin/nologin -M pgpfilter

# Install script to /usr/local/bin with restricted permissions (root-owned, pgpfilter group executable)
sudo install -o root -g pgpfilter -m 750 scripts/pgp-encryptor-filter /usr/local/bin/pgp-encryptor-filter
```

### 3. Database Schema Configuration (MariaDB)

Ensure the database tables have the required PGP columns:

```sql
-- For handle-based routing (alias_handle table)
ALTER TABLE alias_handle
  ADD COLUMN pgp_public_key MEDIUMTEXT NULL DEFAULT NULL AFTER active,
  ADD COLUMN pgp_fingerprint VARCHAR(64) NULL DEFAULT NULL AFTER pgp_public_key,
  ADD COLUMN pgp_enabled TINYINT(1) NOT NULL DEFAULT 0 AFTER pgp_fingerprint,
  ADD COLUMN pgp_hide_subject TINYINT(1) NOT NULL DEFAULT 0 AFTER pgp_enabled;

-- For address-based routing (alias table)
ALTER TABLE alias
  ADD COLUMN pgp_public_key MEDIUMTEXT NULL DEFAULT NULL AFTER active,
  ADD COLUMN pgp_fingerprint VARCHAR(64) NULL DEFAULT NULL AFTER pgp_public_key,
  ADD COLUMN pgp_enabled TINYINT(1) NOT NULL DEFAULT 0 AFTER pgp_fingerprint,
  ADD COLUMN pgp_hide_subject TINYINT(1) NOT NULL DEFAULT 0 AFTER pgp_enabled;
```

#### Enabling PGP for an Alias or Handle

To activate encryption for a specific handle or alias:

```sql
-- Enable PGP for handle 'baldencil' with subject masking:
UPDATE alias_handle
SET pgp_enabled = 1,
    pgp_hide_subject = 1,
    pgp_public_key = '-----BEGIN PGP PUBLIC KEY BLOCK-----\n...\n-----END PGP PUBLIC KEY BLOCK-----',
    pgp_fingerprint = 'A1B2C3D4E5F6...'
WHERE handle = 'baldencil';

-- Keep PGP disabled for handle 'extencil' (default behavior):
UPDATE alias_handle
SET pgp_enabled = 0,
    pgp_hide_subject = 0
WHERE handle = 'extencil';
```

### 4. Postfix Integration (`postfix/master.cf`)

#### Step A: Attach the Content Filter to Port 25 Inbound Listener

In `/etc/postfix/master.cf`, add `-o content_filter=pgpfilter:dummy` to the `smtp` (port 25) service:

```text
smtp      inet  n       -       y       -       -       smtpd
  -o content_filter=pgpfilter:dummy
```

#### Step B: Define the Pipe Service

Add the `pgpfilter` service definition to `/etc/postfix/master.cf`:

```text
# PGP/MIME Content Filter for Inbound Mail Encryption
pgpfilter unix -       n       n       -       10      pipe
  flags=Rq user=pgpfilter null_sender=
  argv=/usr/local/bin/pgp-encryptor-filter -f ${sender} -o ${original_recipient} ${recipient}
```

> **Note**: Passing `-o ${original_recipient}` ensures the filter knows the exact inbound address typed by the sender, avoiding false lookups against expanded internal forward destinations.

#### Step C: Configure Loop-Prevention Reinjection Port (10025)

The filter delivers processed messages back to Postfix via `127.0.0.1:10025`. This listener must clear `content_filter=` to prevent infinite delivery loops:

```text
# Local reinjection listener for content filters (bypasses re-filtering)
127.0.0.1:10025 inet n  -       n       -       -       smtpd
  -o content_filter=
  -o smtpd_authorized_xforward_hosts=127.0.0.0/8
  -o smtpd_client_restrictions=
  -o smtpd_helo_restrictions=
  -o smtpd_sender_restrictions=
  -o smtpd_recipient_restrictions=permit_mynetworks,reject
  -o mynetworks=127.0.0.0/8
  -o receive_override_options=no_header_body_checks,no_unknown_recipient_checks
```

### 5. Applying Changes

Validate configuration syntax and reload Postfix:

```bash
sudo postfix check
sudo systemctl reload postfix
```

### 6. Environment Variables

The filter script can be configured using environment variables or fallback to defaults:

| Variable | Default | Purpose |
|---|---|---|
| `DB_HOST` | `127.0.0.1` | MariaDB host address |
| `DB_USER` | `mailuser` | MariaDB service user |
| `DB_PASS` | `(configured secret)` | MariaDB password |
| `DB_NAME` | `maildb` | Database containing `alias` and `alias_handle` |

---

## Verification & Troubleshooting

Monitor live mail transactions:

```bash
journalctl -u postfix -f
```

- **Plaintext Passthrough**: When a recipient has `pgp_enabled = 0`, the filter logs delivery through `relay=pgpfilter` without modifying body or headers.
- **Encrypted Delivery**: When `pgp_enabled = 1`, the message is encrypted into `multipart/encrypted`, signed by OpenDKIM on outbound hop, and accepted with valid DKIM/DMARC by external providers.
