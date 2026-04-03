# mail-forwarding-core

> **A simple, complete, abuse-aware, open-source mail forwarding stack.**

mail-forwarding-core (or simply **core**) is the reference implementation used
by [Haltman.io](https://haltman.io/) to provide a free, public,
production-grade mail forwarding service.

A public instance is available at
[https://forward.haltman.io](https://forward.haltman.io).

---

## Design Principles

* **Fully open-source** — no open-core, no artificial limitations, no telemetry
* **Stateless** — no mailbox storage, no message content logging
* **Abuse-aware** — anti-spoofing, sender ACL, rate limiting, SRS rejection
* **Deterministic** — configuration-driven, auditable, reproducible
* **Scalable by composition** — each component is independent and replaceable

---

## Architecture

mail-forwarding-core is composed of six building blocks:

| Component | Role |
|---|---|
| **Postfix** | SMTP engine, policy enforcement, forwarding |
| **Dovecot** | SASL authentication backend for submission |
| **PostSRSd** | Sender Rewriting Scheme (SRS) |
| **MariaDB** | Alias lookups, domain registry, sender ACL, user accounts |
| **OpenDKIM** | DKIM signing for outbound mail (optional) |
| **DNS** | MX routing, SPF, DMARC, DKIM records |

### Mail Flow

```
Inbound Mail (port 25)
   |
   v
Postfix smtpd
   |  recipient allowlist check (alias_handle, alias)
   |  sender anti-spoofing check (domain)
   |  SRS inbound rejection (block_srs_inbound.regexp)
   v
MariaDB  -->  alias_handle lookup  -->  alias lookup  -->  goto destination
   |
   v
PostSRSd (envelope sender rewrite)
   |
   v
Postfix smtp  -->  External Destination
```

```
Authenticated Submission (port 587, localhost)
   |
   v
Postfix submission
   |  TLS required
   |  Dovecot SASL auth (TCP 127.0.0.1:12345)
   |  Sender login map + ACL check (smtp_sender_acl)
   v
OpenDKIM signing (milter)
   |
   v
Postfix smtp  -->  External Destination
```

No messages are stored. No queues are inspected. No content is logged.

---

## Repository Structure

```
mail-forwarding-core/
  __db/                 # Current database schema (one .sql file per table)
  dns/                  # DNS record reference (MX, SPF, DMARC, DKIM)
  dovecot/              # Dovecot configuration (SASL + SQL auth)
  mariadb/              # MariaDB schema documentation
  opendkim/             # OpenDKIM configuration (KeyTable, SigningTable)
  postfix/              # Postfix configuration (main.cf, master.cf, MySQL maps)
  postsrsd/             # PostSRSd configuration
```

Each directory contains its own `README.md` with detailed documentation.

---

## Database Schema

The database contains **15 tables** organized into functional groups:

| Group | Tables | Purpose |
|---|---|---|
| MTA Core | `alias`, `alias_handle`, `domain`, `smtp_sender_acl` | Postfix lookups (4 tables, 8 MySQL maps) |
| SMTP Auth | `smtp_users` | Dovecot SASL credential store |
| API Layer | `api_tokens`, `api_token_requests`, `api_logs`, `api_bans` | Token lifecycle, audit, abuse prevention |
| User Management | `users`, `auth_sessions`, `email_verification_tokens`, `password_reset_tokens` | Accounts and session tracking |
| Email Workflow | `email_confirmations` | Subscription and confirmation flows |
| DNS Verification | `dns_requests` | Domain ownership verification |

Individual table definitions are in `__db/`. Full documentation is in `mariadb/README.md`.

---

## Installation

### Prerequisites

* Debian 13 (Trixie) or compatible
* Root or sudo access
* A public IP with port 25 open
* DNS control for each domain to be forwarded

### Installation Order

The order below is **mandatory** — installing out of order will cause
misleading failures:

1. **MariaDB** — schema and database user
2. **DNS** — MX, SPF, DMARC records
3. **PostSRSd** — SRS daemon
4. **Dovecot** — SASL authentication backend
5. **Postfix** — MTA and policy engine
6. **OpenDKIM** — DKIM signing (optional, last)

---

### 1. MariaDB

MariaDB is the lookup backend. Postfix never writes to it.

```bash
sudo apt install mariadb-server
```

```sql
CREATE DATABASE maildb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'mailuser'@'localhost' IDENTIFIED BY 'strong-password';
GRANT SELECT, INSERT, UPDATE, DELETE ON maildb.* TO 'mailuser'@'localhost';
FLUSH PRIVILEGES;
```

Create the schema using the `.sql` files in `__db/`, or see `mariadb/README.md`
for the full table definitions.

> Postfix requires only `SELECT`. The broader grants are for the API and
> administrative tooling.

---

### 2. DNS

Each forwarded domain requires MX, SPF, and DMARC records at minimum.

```dns
example.org.         MX   10 mail.example-mta.net.
example.org.         TXT  "v=spf1 mx -all"
_dmarc.example.org.  TXT  "v=DMARC1; p=none"
```

See `dns/README.md` for detailed guidance and DKIM record setup.

---

### 3. PostSRSd

Mail forwarding **requires SRS** to preserve SPF alignment.

```bash
sudo apt install postsrsd
```

Configuration file: `/etc/default/postsrsd`

```ini
SRS_DOMAIN=example.org
SRS_SECRET=/etc/postsrsd.secret
SRS_FORWARD_PORT=10001
SRS_REVERSE_PORT=10002
SRS_LISTEN_ADDR=127.0.0.1
RUN_AS=postsrsd
```

Generate the secret and start:

```bash
openssl rand -hex 32 | sudo tee /etc/postsrsd.secret
sudo chmod 600 /etc/postsrsd.secret
sudo systemctl enable --now postsrsd
```

See `postsrsd/` for the reference configuration file.

---

### 4. Dovecot

Dovecot provides SASL authentication for Postfix submission.

```bash
sudo apt install dovecot-core dovecot-imapd dovecot-mysql
```

Key configuration points:

* Listens on `127.0.0.1` only
* SQL authentication against `smtp_users` table via MariaDB
* TCP auth listener on port `12345` for Postfix SASL
* Unix socket at `/var/spool/postfix/private/auth` also available

See `dovecot/README.md` for full configuration files and setup instructions.

---

### 5. Postfix

Postfix acts strictly as a forwarding MTA with authenticated submission.

```bash
sudo apt install postfix postfix-mysql
```

Key configuration files:

| Server path | Reference file |
|---|---|
| `/etc/postfix/main.cf` | `postfix/main.cf` |
| `/etc/postfix/master.cf` | `postfix/master.cf` |
| `/etc/postfix/mysql-virtual-handles.cf` | `postfix/mysql-virtual-handles.cf` |
| `/etc/postfix/mysql-virtual-aliases.cf` | `postfix/mysql-virtual-aliases.cf` |
| `/etc/postfix/mysql-allowlist-handles.cf` | `postfix/mysql-allowlist-handles.cf` |
| `/etc/postfix/mysql-allowlist-aliases.cf` | `postfix/mysql-allowlist-aliases.cf` |
| `/etc/postfix/mysql-block-local-senders.cf` | `postfix/mysql-block-local-senders.cf` |
| `/etc/postfix/mysql-virtual-domains.cf` | `postfix/mysql-virtual-domains.cf` |
| `/etc/postfix/mysql-allowed-senders.cf` | `postfix/mysql-allowed-senders.cf` |
| `/etc/postfix/mysql-sender-login-maps.cf` | `postfix/mysql-sender-login-maps.cf` |
| `/etc/postfix/block_srs_inbound.regexp` | `postfix/block_srs_inbound.regexp` |

See `postfix/README.md` for detailed documentation of each file and the
policy architecture.

---

### 6. OpenDKIM (Optional)

OpenDKIM signs outbound mail to improve deliverability.

```bash
sudo apt install opendkim opendkim-tools
```

OpenDKIM listens on `inet:127.0.0.1:8891` and integrates with Postfix via
milter. Configuration is table-driven (`KeyTable`, `SigningTable`,
`TrustedHosts`).

If OpenDKIM is not installed, remove the milter directives from `main.cf`.

For multi-domain environments,
[mail-forwarding-dkim-sync](https://github.com/haltman-io/mail-forwarding-dkim-sync)
is recommended to keep DKIM tables synchronized with the database.

See `opendkim/README.md` for full configuration reference.

---

## Validation Checklist

After installation, verify:

- [ ] MX resolves to the Postfix host
- [ ] PostSRSd is listening on ports 10001 and 10002
- [ ] Dovecot auth listener is active on port 12345
- [ ] Postfix accepts mail on port 25
- [ ] Submission listener is active on port 587 (localhost)
- [ ] Alias resolution works (handle-based and address-based)
- [ ] Recipients not in the allowlist are rejected
- [ ] External senders forging local domains are rejected
- [ ] SRS rewrite is visible in forwarded message headers
- [ ] Authenticated submission works via `swaks` or equivalent
- [ ] Sender ACL rejects unauthorized MAIL FROM on submission
- [ ] DKIM signatures are present (if OpenDKIM is enabled)
- [ ] SPF passes on forwarded mail

---

## FAQ

**Is this an open relay?**
No. Recipients are explicitly allowlisted via MySQL; anything else is rejected.
Submission requires SASL authentication and sender ACL verification.

**Are messages logged?**
No message content is logged. Only minimal MTA operational logs exist.

**Is PostSRSd optional?**
No. Forwarding without SRS breaks SPF alignment.

**Why reject inbound SRS addresses?**
To prevent external SRS forgery and abuse. SRS is an internal forwarding
mechanism only.

**Can I use multiple domains?**
Yes. Domains and aliases are unlimited. Add entries to the `domain` and `alias`
tables.

**Is OpenDKIM mandatory?**
No, but strongly recommended for production deployments.

**Does this store mailboxes?**
No. This is forwarding only. No messages are stored.

**Is Dovecot required?**
Only if you need authenticated submission (port 587). If the server is
forwarding-only with no outbound relay, Dovecot can be omitted and the
submission service removed from `master.cf`.

---

## Security and Disclosure

If you find a vulnerability or misconfiguration:

[security@haltman.io](mailto:security@haltman.io)

We respond as fast as possible.

---

## Community

Join the Haltman.io Telegram group for questions, networking, design
discussions, and operational feedback:

[https://t.me/haltman_group](https://t.me/haltman_group)

---

## License

This project is released into the **public domain** under the
[Unlicense](./LICENSE).

---

## Links

* [Haltman.io](https://haltman.io/)
* [About Haltman.io](https://haltman.io/about)
* [Public forwarding instance](https://forward.haltman.io)

---

## Final Notes

mail-forwarding-core is intentionally **boring**.

No magic. No abstractions. No vendor lock-in.

If you understand SMTP, you can understand — and trust — this stack.
