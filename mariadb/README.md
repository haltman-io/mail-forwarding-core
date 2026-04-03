# MariaDB Configuration

This document describes the **MariaDB schema** for the `mail-forwarding` project.

The database serves as the backend for Postfix virtual alias lookups, SMTP
authenticated submission, API access control, user account management, and
domain DNS verification.

---

## Scope

The schema supports:

- Virtual alias resolution (address and handle-based)
- Domain management
- SMTP sender ACL and authenticated relay
- API token lifecycle and audit logging
- User accounts and session management
- Email confirmation workflows
- DNS ownership verification

---

## Table Overview

The database contains **15 tables** organized into the following groups:

### MTA Core (Postfix-queried)

| Table | Purpose |
|---|---|
| `alias` | Address-level forwarding rules |
| `alias_handle` | Handle-based alias routing |
| `domain` | Virtual domain registry |
| `smtp_sender_acl` | Sender access control for submission |

### SMTP Authentication

| Table | Purpose |
|---|---|
| `smtp_users` | Credentials for authenticated SMTP submission |

### API Layer

| Table | Purpose |
|---|---|
| `api_tokens` | Issued API tokens (hashed) |
| `api_token_requests` | Pending token request flows |
| `api_logs` | API request audit log |
| `api_bans` | Bans by email, domain, IP, or name |

### User Management

| Table | Purpose |
|---|---|
| `users` | Admin/user accounts |
| `auth_sessions` | Refresh-token session tracking |
| `email_verification_tokens` | Email verification for user accounts |
| `password_reset_tokens` | Password reset request tracking |

### Email Workflow

| Table | Purpose |
|---|---|
| `email_confirmations` | Subscription and confirmation flows |

### DNS Verification

| Table | Purpose |
|---|---|
| `dns_requests` | Domain ownership verification tracking |

---

## Database Creation

Access MariaDB:

```bash
sudo mysql
```

Create the database:

```sql
CREATE DATABASE maildb;
```

---

## Database User

Create a dedicated user with appropriate privileges:

```sql
CREATE USER 'db_username'@'localhost' IDENTIFIED BY 'db_p4ssw0rd';
GRANT SELECT, INSERT, UPDATE, DELETE ON maildb.* TO 'db_username'@'localhost';
FLUSH PRIVILEGES;
```

> Postfix requires only `SELECT`. The broader grants are for the API and
> administrative tooling.

---

## Schema Definitions

Select the database:

```sql
USE maildb;
```

### MTA Core

#### `alias`

Defines address-level forwarding rules.

```sql
CREATE TABLE `alias` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `address` varchar(320) NOT NULL,
  `goto` text NOT NULL,
  `active` tinyint(1) DEFAULT 1,
  `created` timestamp NULL DEFAULT current_timestamp(),
  `modified` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_alias_address` (`address`),
  KEY `idx_alias_goto_id` (`goto`(191),`id`),
  KEY `idx_alias_goto_created` (`goto`(191),`created`),
  KEY `idx_alias_goto_modified` (`goto`(191),`modified`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
```

#### `alias_handle`

Maps short handles to full addresses for catch-all style routing.

```sql
CREATE TABLE `alias_handle` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `handle` varchar(128) NOT NULL,
  `address` varchar(255) DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_handle` (`handle`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
```

#### `domain`

Registry of virtual domains served by Postfix.

```sql
CREATE TABLE `domain` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `active` tinyint(1) DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
```

#### `smtp_sender_acl`

Controls which authenticated users may send as which sender addresses.

```sql
CREATE TABLE `smtp_sender_acl` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `login` varchar(320) NOT NULL,
  `sender` varchar(320) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_login_sender` (`login`,`sender`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
```

### SMTP Authentication

#### `smtp_users`

Credentials for SMTP authenticated submission (Dovecot/SASL).

```sql
CREATE TABLE `smtp_users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(320) NOT NULL,
  `password` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
```

### API Layer

#### `api_tokens`

Issued API tokens. Only the hash is stored.

```sql
CREATE TABLE `api_tokens` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `owner_email` varchar(254) NOT NULL,
  `token_hash` binary(32) NOT NULL,
  `status` enum('active','revoked','expired') NOT NULL DEFAULT 'active',
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `expires_at` datetime(6) NOT NULL,
  `revoked_at` datetime(6) DEFAULT NULL,
  `revoked_reason` varchar(500) DEFAULT NULL,
  `created_ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `last_used_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_api_tokens_token_hash` (`token_hash`),
  KEY `idx_api_tokens_owner_email` (`owner_email`),
  KEY `idx_api_tokens_expires_at` (`expires_at`),
  KEY `idx_api_tokens_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### `api_token_requests`

Pending API token requests awaiting email confirmation.

```sql
CREATE TABLE `api_token_requests` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `email` varchar(254) NOT NULL,
  `token_hash` binary(32) NOT NULL,
  `status` enum('pending','confirmed','expired') NOT NULL DEFAULT 'pending',
  `days` int(10) unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `expires_at` datetime(6) NOT NULL,
  `confirmed_at` datetime(6) DEFAULT NULL,
  `request_ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `send_count` int(10) unsigned NOT NULL DEFAULT 1,
  `last_sent_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `attempts_confirm` int(10) unsigned NOT NULL DEFAULT 0,
  `active_pending` tinyint(4) GENERATED ALWAYS AS (case when `status` = 'pending' then 1 else NULL end) VIRTUAL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_api_token_requests_token_hash` (`token_hash`),
  UNIQUE KEY `uq_api_token_requests_email_active_pending` (`email`,`active_pending`),
  KEY `idx_api_token_requests_email_status` (`email`,`status`),
  KEY `idx_api_token_requests_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### `api_logs`

Audit log for API requests.

```sql
CREATE TABLE `api_logs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `api_token_id` bigint(20) unsigned DEFAULT NULL,
  `api_token_owner_email` varchar(254) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `route` varchar(128) NOT NULL,
  `body` longtext DEFAULT NULL,
  `request_ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_api_logs_created_at` (`created_at`),
  KEY `idx_api_logs_token_id` (`api_token_id`),
  KEY `idx_api_logs_owner_email` (`api_token_owner_email`),
  CONSTRAINT `api_logs_ibfk_1` FOREIGN KEY (`api_token_id`) REFERENCES `api_tokens` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### `api_bans`

Bans targeting emails, domains, IPs, or names.

```sql
CREATE TABLE `api_bans` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ban_type` enum('email','domain','ip','name') NOT NULL,
  `ban_value` varchar(254) NOT NULL,
  `reason` varchar(500) NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `expires_at` datetime(6) DEFAULT NULL,
  `revoked_at` datetime(6) DEFAULT NULL,
  `revoked_reason` varchar(500) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_active_target` (`ban_type`,`ban_value`,`revoked_at`),
  KEY `idx_lookup` (`ban_type`,`ban_value`),
  KEY `idx_expires_at` (`expires_at`),
  KEY `idx_revoked_at` (`revoked_at`),
  KEY `idx_api_bans_type_value_active` (`ban_type`,`ban_value`,`revoked_at`,`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### User Management

#### `users`

Admin and user accounts.

```sql
CREATE TABLE `users` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `email` varchar(254) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `email_verified_at` datetime(6) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `is_admin` tinyint(1) NOT NULL DEFAULT 0,
  `password_changed_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6),
  `last_login_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_email` (`email`),
  UNIQUE KEY `uq_users_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### `auth_sessions`

Refresh-token based session tracking with rotation detection.

```sql
CREATE TABLE `auth_sessions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `session_family_id` char(36) NOT NULL,
  `refresh_token_hash` binary(32) NOT NULL,
  `refresh_expires_at` datetime(6) NOT NULL,
  `status` enum('active','rotated','revoked','reuse_detected') NOT NULL DEFAULT 'active',
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `revoked_at` datetime(6) DEFAULT NULL,
  `replaced_by_session_id` bigint(20) unsigned DEFAULT NULL,
  `last_used_at` datetime(6) DEFAULT NULL,
  `request_ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_auth_sessions_refresh_token_hash` (`refresh_token_hash`),
  KEY `ix_auth_sessions_family_status` (`session_family_id`,`status`,`refresh_expires_at`),
  KEY `ix_auth_sessions_user_family` (`user_id`,`session_family_id`),
  KEY `fk_auth_sessions_replaced_by` (`replaced_by_session_id`),
  CONSTRAINT `fk_admin_auth_sessions_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_auth_sessions_replaced_by` FOREIGN KEY (`replaced_by_session_id`) REFERENCES `auth_sessions` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### `email_verification_tokens`

Tokens for verifying user email addresses.

```sql
CREATE TABLE `email_verification_tokens` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `token_hash` binary(32) NOT NULL,
  `expires_at` datetime(6) NOT NULL,
  `used_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `request_ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `send_count` int(10) unsigned NOT NULL DEFAULT 1,
  `last_sent_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_email_verification_tokens_token_hash` (`token_hash`),
  KEY `ix_email_verification_tokens_user_active` (`user_id`,`used_at`,`expires_at`),
  CONSTRAINT `fk_email_verification_tokens_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

#### `password_reset_tokens`

Tokens for password reset flows.

```sql
CREATE TABLE `password_reset_tokens` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `token_hash` binary(32) NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `expires_at` datetime(6) NOT NULL,
  `used_at` datetime(6) DEFAULT NULL,
  `request_ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `send_count` int(10) unsigned NOT NULL DEFAULT 1,
  `last_sent_at` datetime(6) DEFAULT NULL,
  `attempts_confirm` int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_password_reset_requests_token_hash` (`token_hash`),
  KEY `ix_password_reset_tokens_user_active` (`user_id`,`used_at`,`expires_at`),
  CONSTRAINT `fk_password_reset_requests_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### Email Workflow

#### `email_confirmations`

Tracks email-based confirmation flows (subscriptions, alias creation, etc.).

```sql
CREATE TABLE `email_confirmations` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `email` varchar(254) NOT NULL,
  `token_hash` binary(32) NOT NULL,
  `status` enum('pending','confirmed','expired') NOT NULL DEFAULT 'pending',
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `expires_at` datetime(6) NOT NULL,
  `confirmed_at` datetime(6) DEFAULT NULL,
  `request_ip` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `send_count` int(10) unsigned NOT NULL DEFAULT 1,
  `last_sent_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `attempts_confirm` int(10) unsigned NOT NULL DEFAULT 0,
  `active_pending` tinyint(4) GENERATED ALWAYS AS (case when `status` = 'pending' then 1 else NULL end) VIRTUAL,
  `intent` varchar(32) NOT NULL DEFAULT 'subscribe',
  `alias_name` varchar(64) DEFAULT NULL,
  `alias_domain` varchar(253) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_token_hash` (`token_hash`),
  UNIQUE KEY `uq_email_active_pending` (`email`,`active_pending`),
  KEY `idx_email_status` (`email`,`status`),
  KEY `idx_expires_at` (`expires_at`),
  KEY `idx_request_ip_created` (`request_ip`,`created_at`),
  KEY `idx_last_sent_at` (`last_sent_at`),
  KEY `idx_intent_email` (`intent`,`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### DNS Verification

#### `dns_requests`

Tracks domain DNS verification status for UI and email domain validation.

```sql
CREATE TABLE `dns_requests` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `target` varchar(253) NOT NULL,
  `type` enum('UI','EMAIL') NOT NULL,
  `status` varchar(16) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `activated_at` datetime DEFAULT NULL,
  `last_checked_at` datetime DEFAULT NULL,
  `next_check_at` datetime DEFAULT NULL,
  `last_check_result_json` text DEFAULT NULL,
  `fail_reason` text DEFAULT NULL,
  `expires_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_target_type` (`target`,`type`),
  KEY `idx_status` (`status`),
  KEY `idx_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
```

---

## Postfix Integration

Postfix queries the database via **8 MySQL map files**, hitting **4 tables**:

| MySQL Map | Table | Query Purpose |
|---|---|---|
| `mysql-virtual-aliases.cf` | `alias` | Resolve destination address from alias |
| `mysql-virtual-handles.cf` | `alias_handle` | Resolve address from handle (local-part) |
| `mysql-allowlist-aliases.cf` | `alias` | Verify recipient alias exists |
| `mysql-allowlist-handles.cf` | `alias_handle` | Verify recipient handle exists |
| `mysql-block-local-senders.cf` | `domain` | Reject forged local senders |
| `mysql-virtual-domains.cf` | `domain` | Verify valid virtual domain |
| `mysql-allowed-senders.cf` | `smtp_sender_acl` | Verify sender is allowed on submission |
| `mysql-sender-login-maps.cf` | `smtp_sender_acl` | Map sender address to login for SASL check |

Postfix **never modifies** database contents.

---

## Example Data

```sql
INSERT INTO domain (name, active) VALUES ('example.org', 1);

INSERT INTO alias (address, goto, active)
VALUES ('info@example.org', 'user@external-provider.net', 1);

INSERT INTO alias_handle (handle, address, active)
VALUES ('support', 'info@example.org', 1);
```

---

## Security Considerations

* Passwords are stored hashed (`smtp_users.password`, `users.password_hash`)
* All tokens are stored as `binary(32)` hashes — plaintext tokens are never persisted
* IP addresses use `varbinary(16)` to support both IPv4 and IPv6
* Foreign keys enforce referential integrity (`api_logs` -> `api_tokens`, `auth_sessions` -> `users`, etc.)
* Postfix uses read-only access
* Virtual generated columns enforce single-active-pending constraints without application logic

---

## Schema Dump

To export the schema without data:

```bash
mysqldump --no-data maildb > maildb.schema.sql
```

---

## Summary

* MariaDB serves as the backend for Postfix lookups, SMTP auth, API management, and user accounts
* **15 tables** organized into 6 functional groups
* Postfix queries 4 tables (`alias`, `alias_handle`, `domain`, `smtp_sender_acl`) via 8 MySQL maps
* Remaining tables support the API layer, user management, email workflows, and DNS verification
* All sensitive data (passwords, tokens) is stored hashed
