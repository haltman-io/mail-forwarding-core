# Postfix Configuration Reference

This directory contains **reference Postfix configuration files** used by the
`mail-forwarding` project.

These files are intentionally provided as **realistic, production-inspired examples**.
They are meant to document **architecture, behavior, and security decisions** — not to
serve as a copy-paste, one-command deployment.

If you understand Postfix, these files should be sufficient to reproduce the same
behavior in your own environment after adapting them to your infrastructure.

---

## Scope and Intent

The configurations in this directory describe a Postfix setup with the following goals
(as implemented in `main.cf`):

- Act strictly as a **mail forwarding / aliasing service**
- **No local mailbox delivery**
- Recipients and aliases managed via **MySQL**
- Strong **anti-spoofing** and **anti-open-relay** posture
- Explicit handling of **SRS (Sender Rewriting Scheme)**
- Designed to integrate with **DKIM** and external policy services

This is **not** a beginner guide to Postfix.
Basic familiarity with Postfix concepts is assumed.

---

## Files Overview

### `main.cf`

Primary Postfix configuration.

Key characteristics:

- Explicitly disables local delivery via an empty `mydestination`
- Virtual alias lookups backed by MySQL
- Recipient allowlisting backed by MySQL (default reject)
- HELO/EHLO hygiene
- Integration points for:
  - SRS (TCP maps)
  - DKIM (milter)

TLS is enabled with example certificate paths (see below).

---

#### How `main.cf` wires this together

##### No local delivery

```ini
mydestination =
```

##### MySQL-backed aliasing + recipient allowlist

```ini
virtual_alias_maps = mysql:/etc/postfix/mysql-virtual-aliases.cf

smtpd_recipient_restrictions =
    reject_non_fqdn_recipient,
    check_recipient_access mysql:/etc/postfix/mysql-rcpt-allow.cf,
    reject,
```

In this setup:

- `mysql-rcpt-allow.cf` controls which `RCPT TO` addresses are accepted (allowlist).
- `mysql-virtual-aliases.cf` controls where accepted recipients are forwarded (`address` → `goto`).

##### Anti-spoofing + inbound SRS rejection

```ini
smtpd_sender_restrictions =
    permit_mynetworks,
    check_sender_access regexp:/etc/postfix/block_srs_inbound.regexp,
    check_sender_access mysql:/etc/postfix/mysql-block-local-senders.cf,
    permit
```

##### SRS integration (postsrsd or equivalent)

```ini
sender_canonical_maps = tcp:localhost:10001
recipient_canonical_maps = tcp:localhost:10002
```

##### DKIM signing/verification (OpenDKIM or compatible milter)

```ini
smtpd_milters = inet:127.0.0.1:8891
```

##### TLS

```ini
smtpd_tls_security_level = may
smtp_tls_security_level = may

smtpd_tls_cert_file = /etc/letsencrypt/live/mail.example.com/fullchain.pem
smtpd_tls_key_file  = /etc/letsencrypt/live/mail.example.com/privkey.pem
```

If you don’t want Postfix terminating TLS on this host, remove/comment the TLS lines.
If you do enable TLS, ensure the certificate and key paths exist or Postfix may fail to start.

---

### `master.cf`

Service definitions used by Postfix.

- Largely defaults
- No unsafe overrides
- No custom listeners exposed

Provided for completeness and transparency.

---

### `mysql-virtual-aliases.cf`

Defines how Postfix resolves email aliases via MySQL.

This file controls:

- Address → destination mappings
- Forwarding behavior

---

### `mysql-rcpt-allow.cf`

Defines how Postfix checks whether a recipient is accepted at SMTP time.

This file controls:

- Which `RCPT TO` addresses are accepted (allowlist)

In `main.cf`, anything not allowlisted is rejected.

---

### `mysql-block-local-senders.cf`

Implements **dynamic sender spoofing protection**.

Instead of returning data, this query intentionally returns a **static REJECT**
when the sender domain matches an active local domain.

This prevents external clients from forging `MAIL FROM` addresses belonging
to hosted domains.

This behavior is deliberate.

---

### `block_srs_inbound.regexp`

Rejects inbound messages with SRS-formatted senders.

This ensures:

- SRS is only used internally for forwarding
- External SRS traffic is not accepted blindly

---

## Implicit Dependencies (Important)

These configurations assume the presence of additional components.
They are **not** included or deployed automatically.

You **must** account for them if you reuse these files.

### 1. SRS daemon (postsrsd or equivalent)

The following lines in `main.cf`:

```ini
sender_canonical_maps = tcp:localhost:10001
recipient_canonical_maps = tcp:localhost:10002
```

Assume:

* An SRS daemon listening on:

  * `localhost:10001` (forward rewriting)
  * `localhost:10002` (reverse rewriting)

If no daemon is running, Postfix will fail to process addresses correctly.

---

### 2. DKIM milter

The following line in `main.cf`:

```ini
smtpd_milters = inet:127.0.0.1:8891
```

Assumes:

* OpenDKIM (or compatible milter)
* Listening locally on port `8891`

DKIM keys, selector management, and DNS records are **out of scope** for this directory.

---

### 3. MySQL / MariaDB schema

The MySQL queries assume:

* A database schema containing at least:

  * `alias`
  * `domain`
* Fields such as:

  * `alias.address`, `alias.goto`, `alias.active`
  * `domain.name`, `domain.active`

Schema creation and migrations are handled elsewhere in the project.

---

## Security Considerations

* No credentials are embedded in these files.
* All database credentials are placeholders.
* No real IP addresses are exposed.
* TLS is configured with example paths; replace with your real certificate locations.

---

## FAQ

### ❓ Are these files safe to publish publicly?

Yes.

They contain **no secrets**, **no credentials**, and **no environment-specific identifiers**.
They document behavior and architecture only.

---

### ❓ Can I deploy Postfix by copying these files as-is?

No.

These files are **reference configurations**, not an installer.
You must adapt:

* Domains
* Database credentials
* TLS certificates
* Auxiliary services (SRS, DKIM)

---

### ❓ Why is TLS configured with example paths?

Because certificate provisioning is environment-specific, but most real deployments
need TLS.

The example uses Let’s Encrypt-style paths for `mail.example.com` to show what a
working setup looks like. Replace these paths with your real certificate locations
or remove/comment the TLS lines if TLS termination is handled elsewhere.

---

### ❓ Why does `mysql-block-local-senders.cf` return a static `REJECT`?

This is intentional.

The query is used purely as a **boolean existence check**.
If the sender domain exists and is active locally, Postfix rejects the sender to prevent spoofing.

---

### ❓ Why reject inbound SRS addresses?

Because SRS is an **internal forwarding mechanism**.

Accepting external SRS blindly increases abuse surface and breaks trust assumptions.

---

### ❓ Is this an open relay?

No.

Recipients are explicitly allowlisted via `mysql-rcpt-allow.cf`; anything else is rejected.
That keeps the service from relaying to arbitrary destinations.

---

### ❓ Where are SPF, DKIM, and DMARC configured?

Outside of this directory.

This folder documents **Postfix behavior only**.
DNS configuration and policy enforcement are handled elsewhere in the project.

---

## Final Notes

This directory exists to:

* Make design decisions explicit
* Document security posture
* Enable reproducibility by experienced operators

If you are looking for a “one-click mail server”, this is not it.

If you are looking for a **transparent, abuse-aware mail forwarding architecture**,
you are in the right place.
