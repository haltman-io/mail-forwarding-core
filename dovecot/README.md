````markdown
# Dovecot + Postfix TCP SASL Setup on Debian 13 (Trixie)

This document reproduces the current setup described earlier:

- Dovecot installed locally
- Dovecot listening only on `127.0.0.1`
- IMAP enabled
- SQL authentication against MariaDB/MySQL
- Postfix submission authentication via **Dovecot over TCP** on `127.0.0.1:12345`
- Postfix sender login map via MySQL

This is **not** a full virtual mailbox platform design. It is a direct reproduction of the current auth path and service layout.

---

## 1. Install required packages

```bash
apt update
apt install -y \
  postfix postfix-mysql \
  dovecot-core dovecot-imapd dovecot-mysql \
  mariadb-server mariadb-client \
  swaks
````

---

## 2. Create the database and auth tables

Log into MariaDB:

```bash
mysql -u root -p
```

Create the database, SQL user, and tables:

```sql
CREATE DATABASE maildb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'mailuser'@'127.0.0.1' IDENTIFIED BY 'CHANGE_ME_STRONG_PASSWORD';
GRANT SELECT ON maildb.* TO 'mailuser'@'127.0.0.1';
FLUSH PRIVILEGES;

USE maildb;

CREATE TABLE smtp_users (
  username VARCHAR(255) NOT NULL PRIMARY KEY,
  password VARCHAR(255) NOT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1
);

CREATE TABLE smtp_sender_acl (
  sender VARCHAR(255) NOT NULL PRIMARY KEY,
  login  VARCHAR(255) NOT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1
);
```

Generate a password hash for Dovecot:

```bash
doveadm pw -s sha256-crypt
```

Insert a test account:

```sql
INSERT INTO smtp_users (username, password, active)
VALUES ('user@example.com', '{SHA256-CRYPT}PASTE_HASH_HERE', 1);

INSERT INTO smtp_sender_acl (sender, login, active)
VALUES ('user@example.com', 'user@example.com', 1);
```

---

## 3. Back up the default configs

```bash
cp -a /etc/dovecot /etc/dovecot.bak.$(date +%F-%H%M%S)
cp -a /etc/postfix /etc/postfix.bak.$(date +%F-%H%M%S)
```

---

## 4. Configure Dovecot

### 4.1 `/etc/dovecot/dovecot.conf`

Replace the file with:

```conf
dovecot_config_version = 2.4.0
dovecot_storage_version = 2.4.0

protocols = imap
listen = 127.0.0.1

!include conf.d/*.conf

sql_driver = mysql

mysql 127.0.0.1 {
  user = mailuser
  password = CHANGE_ME_STRONG_PASSWORD
  dbname = maildb
}
```

---

### 4.2 `/etc/dovecot/conf.d/10-auth.conf`

Replace the file with:

```conf
auth_mechanisms = plain login
!include auth-sql.conf.ext
```

---

### 4.3 `/etc/dovecot/conf.d/auth-sql.conf.ext`

Replace the file with:

```conf
passdb sql {
  query = SELECT username AS user, password FROM smtp_users WHERE username = '%{user}' AND active = 1
}
```

---

### 4.4 `/etc/dovecot/conf.d/10-master.conf`

Keep the relevant parts like this:

```conf
service imap-login {
  inet_listener imap {
  }
  inet_listener imaps {
  }
}

service auth {
  unix_listener auth-userdb {
  }

  inet_listener auth {
    port = 12345
  }
}
```

This setup uses **TCP auth**, not the Postfix Unix socket auth path.

---

### 4.5 `/etc/dovecot/conf.d/10-mail.conf`

Set the mail layout to match the current setup:

```conf
mail_driver = mbox
mail_home = /home/%{user | username}
mail_inbox_path = /var/mail/%{user}
mail_path = %{home}/mail
mail_privileged_group = mail
```

---

### 4.6 `/etc/dovecot/conf.d/10-ssl.conf`

Replace or adjust the SSL section:

```conf
ssl = yes

ssl_server {
  cert_file = /etc/dovecot/private/dovecot.pem
  key_file = /etc/dovecot/private/dovecot.key
}
```

Create the directory and place your certs:

```bash
install -d -m 0700 /etc/dovecot/private
cp /path/to/fullchain.pem /etc/dovecot/private/dovecot.pem
cp /path/to/privkey.pem /etc/dovecot/private/dovecot.key
chown root:root /etc/dovecot/private/dovecot.pem /etc/dovecot/private/dovecot.key
chmod 0600 /etc/dovecot/private/dovecot.pem /etc/dovecot/private/dovecot.key
```

---

### 4.7 `/etc/dovecot/conf.d/15-mailboxes.conf`

Use standard special-use folders:

```conf
namespace inbox {
  inbox = yes

  mailbox Drafts {
    special_use = \Drafts
  }
  mailbox Junk {
    special_use = \Junk
  }
  mailbox Trash {
    special_use = \Trash
  }
  mailbox Sent {
    special_use = \Sent
  }
  mailbox "Sent Messages" {
    special_use = \Sent
  }
}
```

---

## 5. Configure Postfix

### 5.1 `/etc/postfix/main.cf`

Make sure this is present:

```conf
smtpd_sasl_type = dovecot
```

---

### 5.2 `/etc/postfix/master.cf`

Configure submission with Dovecot TCP auth:

```conf
# -------------------------------------------------
# SMTP listener services
# -------------------------------------------------
smtp      inet  n       -       y       -       -       smtpd
127.0.0.1:submission inet n       -       n       -       -       smtpd

# -------------------------------------------------
# Submission service overrides
# -------------------------------------------------
  -o syslog_name=postfix/submission

  # TLS enforcement and AUTH only after TLS
  -o smtpd_tls_security_level=encrypt
  -o smtpd_tls_auth_only=yes

  # SASL via Dovecot (TCP)
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=inet:127.0.0.1:12345

  # Relay only for authenticated clients
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject

  # MAIL FROM anti-spoofing
  -o smtpd_sender_login_maps=mysql:/etc/postfix/mysql-sender-login-maps.cf
  -o smtpd_sender_restrictions=submission_sender_policy

  # DKIM/milters for originating mail
  -o milter_macro_daemon_name=ORIGINATING

# -------------------------------------------------
# Queue management services
# -------------------------------------------------
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite

# -------------------------------------------------
# Bounce and verification services
# -------------------------------------------------
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap

# -------------------------------------------------
# Outbound transport services
# -------------------------------------------------
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
        -o syslog_name=${multi_instance_name?{$multi_instance_name}:{postfix}}/$service_name

# -------------------------------------------------
# Local delivery and utility services
# -------------------------------------------------
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
postlog   unix-dgram n  -       n       -       1       postlogd
```

---

### 5.3 `/etc/postfix/mysql-sender-login-maps.cf`

Create the file:

```conf
user = mailuser
password = CHANGE_ME_STRONG_PASSWORD
hosts = 127.0.0.1
dbname = maildb
query = SELECT login FROM smtp_sender_acl WHERE sender='%s' AND active=1 LIMIT 1
```

Secure it:

```bash
chown root:root /etc/postfix/mysql-sender-login-maps.cf
chmod 0640 /etc/postfix/mysql-sender-login-maps.cf
```

---

## 6. Enable and restart services

```bash
systemctl enable --now mariadb
systemctl enable --now dovecot
systemctl enable --now postfix

systemctl restart dovecot
systemctl restart postfix
```

---

## 7. Validate the configuration

Check Dovecot:

```bash
dovecot -n
```

Check Postfix:

```bash
postfix check
postconf -n
```

Check Dovecot auth TCP listener:

```bash
ss -ltnp | grep 12345
```

Check Postfix submission listener:

```bash
ss -ltnp | grep ':587\|:submission'
```

---

## 8. Test SMTP AUTH

```bash
swaks \
  --server 127.0.0.1:587 \
  --tls \
  --auth LOGIN \
  --auth-user user@example.com \
  --auth-password 'YOUR_REAL_PASSWORD' \
  --from user@example.com \
  --to test@example.net
```

---

## 9. Troubleshooting

Show effective Dovecot config:

```bash
dovecot -n
```

Show effective Postfix config:

```bash
postconf -n
```

Show recent Dovecot logs:

```bash
journalctl -u dovecot -n 100 --no-pager
```

Show recent Postfix logs:

```bash
journalctl -u postfix -n 100 --no-pager
```

Check whether Postfix is using TCP auth path:

```bash
grep -Rni "smtpd_sasl_path\|inet:127.0.0.1:12345\|private/auth" /etc/postfix
```

---

## 10. Notes

* This setup uses **Dovecot TCP auth** on `127.0.0.1:12345`.
* It does **not** require Postfix to use `/var/spool/postfix/private/auth`.
* If a Unix auth socket exists in Dovecot config but Postfix points to `inet:127.0.0.1:12345`, the Unix socket is not the active SASL path for submission.
* The storage layout here matches the current setup: `mbox`, `/var/mail/%{user}`, and `%{home}/mail`.
* This is a reproduction of the current working design, not a generic recommended architecture for all deployments.

```

If you want, I can also turn this into a more polished repository-style `README.md` section with `Prerequisites`, `Configuration`, `Validation`, and `Troubleshooting` headings only once, without the extra explanatory text.
```
