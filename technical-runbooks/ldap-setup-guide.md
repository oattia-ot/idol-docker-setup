# LDAP Setup Guide with Docker

> **Last Updated:** May 2026

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1 — Create the Docker Compose File](#step-1--create-the-docker-compose-file)
- [Step 2 — Start the Services](#step-2--start-the-services)
- [Step 3 — Verify LDAP is Running](#step-3--verify-ldap-is-running)
- [Step 4 — Access the Web UI (phpLDAPadmin)](#step-4--access-the-web-ui-phpldapadmin)
- [Step 5 — Add Your First User](#step-5--add-your-first-user)
- [Step 6 — Install ldap-utils (Optional)](#step-6--install-ldap-utils-optional)
- [Troubleshooting](#troubleshooting)
- [Useful Tutorials & Resources](#useful-tutorials--resources)

---

## Overview

This guide walks through deploying a local **OpenLDAP** server using Docker Compose, with a **phpLDAPadmin** web UI for easy management.

| Service       | Image                        | Port       | Purpose              |
|---------------|------------------------------|------------|----------------------|
| openldap      | `osixia/openldap:1.5.0`      | 389 / 636  | LDAP server          |
| phpldapadmin  | `osixia/phpldapadmin:latest` | 8080       | Web management UI    |

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed
- [Docker Compose](https://docs.docker.com/compose/install/) v2+ installed
- Ports `389`, `636`, and `8080` available on your machine

---

## Step 1 — Create the Docker Compose File

Create a file named `docker-compose.yml` with the following content:

```yaml
services:

  openldap:
    image: osixia/openldap:1.5.0
    container_name: openldap
    restart: unless-stopped
    ports:
      - "389:389"
      - "636:636"
    environment:
      LDAP_ORGANISATION: "Example Organisation"
      LDAP_DOMAIN: "example.com"
      LDAP_BASE_DN: ""
      LDAP_ADMIN_PASSWORD: "Admin1234!"       # ⚠ Change before production
      LDAP_CONFIG_PASSWORD: "Config1234!"     # ⚠ Change before production
      LDAP_TLS: "false"
      LDAP_REMOVE_CONFIG_AFTER_SETUP: "true"
      LDAP_RFC2307BIS_SCHEMA: "false"
    volumes:
      - openldap_data:/var/lib/ldap
      - openldap_config:/etc/ldap/slapd.d
    networks:
      - ldap_net
    healthcheck:
      test: ["CMD", "ldapsearch", "-x", "-H", "ldap://localhost:389",
             "-b", "dc=example,dc=com", "-D", "cn=admin,dc=example,dc=com",
             "-w", "Admin1234!"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 20s

  phpldapadmin:
    image: osixia/phpldapadmin:latest
    container_name: phpldapadmin
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      PHPLDAPADMIN_LDAP_HOSTS: "openldap"
      PHPLDAPADMIN_HTTPS: "false"
    depends_on:
      openldap:
        condition: service_healthy
    networks:
      - ldap_net

volumes:
  openldap_data:
  openldap_config:

networks:
  ldap_net:
    driver: bridge
```

> **Note:** The `bitnami/openldap` image does **not** exist on Docker Hub. Always use `osixia/openldap`.

---

## Step 2 — Start the Services

```bash
docker compose -f docker-compose.yml up -d
```

Wait ~20 seconds for initialization, then confirm both containers are healthy:

```bash
docker compose -f docker-compose.yml ps
```

Expected output:

```
NAME            STATUS
openldap        healthy
phpldapadmin    running
```

---

## Step 3 — Verify LDAP is Running

Run a test query **inside the container** (no extra tools needed):

```bash
docker exec openldap ldapsearch -x \
  -H ldap://localhost:389 \
  -b "dc=example,dc=com" \
  -D "cn=admin,dc=example,dc=com" \
  -w "Admin1234!"
```

A successful response looks like:

```
# example.com
dn: dc=example,dc=com
objectClass: top
objectClass: dcObject
objectClass: organization
o: Example Organisation
dc: example

# search result
result: 0 Success
```

---

## Step 4 — Access the Web UI (phpLDAPadmin)

Open **http://localhost:8080** in your browser.

1. Click **Login** in the left panel
2. Enter the following credentials:

| Field     | Value                          |
|-----------|-------------------------------|
| Login DN  | `cn=admin,dc=example,dc=com`  |
| Password  | `Admin1234!`                  |

> ⚠ The Login DN must be the **full DN string** — not just `admin`.

If phpLDAPadmin fails to connect, restart it:

```bash
docker compose -f docker-compose.yml restart phpldapadmin
docker logs phpldapadmin
```

---

## Step 5 — Add Your First User

Create a file named `user.ldif`:

```ldif
dn: cn=John Doe,dc=example,dc=com
objectClass: inetOrgPerson
cn: John Doe
sn: Doe
uid: jdoe
mail: jdoe@example.com
userPassword: Password123!
```

Import it into LDAP:

```bash
docker exec -i openldap ldapadd \
  -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" \
  -w "Admin1234!" < user.ldif
```

Verify the user was added:

```bash
docker exec openldap ldapsearch -x \
  -H ldap://localhost:389 \
  -b "dc=example,dc=com" \
  -D "cn=admin,dc=example,dc=com" \
  -w "Admin1234!" \
  "(uid=jdoe)"
```

---

## Step 6 — Install ldap-utils (Optional)

To run `ldapsearch`, `ldapadd`, etc. directly from your host machine:

```bash
# Debian / Ubuntu
sudo apt install ldap-utils -y

# RHEL / CentOS / Fedora
sudo dnf install openldap-clients -y

# macOS (via Homebrew)
brew install openldap
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `bitnami/openldap: not found` | Use `osixia/openldap:1.5.0` instead |
| `Unable to connect to LDAP server` | Run `docker compose restart phpldapadmin` and check `docker logs phpldapadmin` |
| `Invalid DN syntax (34)` in phpLDAPadmin | Enter the **full DN**: `cn=admin,dc=example,dc=com` — not just `admin` |
| `ldapsearch: command not found` | Install with `sudo apt install ldap-utils -y` or run inside the container |
| Port 389 already in use | Change host port in Compose: `"3389:389"` |

### Stop & Clean Up

```bash
# Stop containers (keep data)
docker compose -f docker-compose.yml down

# Stop and delete all data volumes
docker compose -f docker-compose.yml down -v
```

---

## Useful Tutorials & Resources

### Official Documentation

- 📘 [OpenLDAP Administrator's Guide](https://www.openldap.org/doc/admin26/) — Comprehensive official reference
- 📘 [osixia/openldap Docker Image Docs](https://github.com/osixia/docker-openldap) — All environment variables and configuration options
- 📘 [phpLDAPadmin Documentation](http://phpldapadmin.sourceforge.net/wiki/index.php/Main_Page) — Web UI usage guide

### Beginner Tutorials

- 🎓 [LDAP for Rocket Scientists](https://www.zytrax.com/books/ldap/) — Free online book, excellent for absolute beginners. Covers theory, schema, and practical examples
- 🎓 [DigitalOcean: Understanding LDAP](https://www.digitalocean.com/community/tutorials/understanding-the-ldap-protocol-data-hierarchy-and-entry-components) — Clear explanation of LDAP concepts (DN, DC, CN, OU, objectClass)
- 🎓 [TechTarget: LDAP Tutorial](https://www.techtarget.com/searchmobilecomputing/definition/LDAP) — High-level overview for newcomers

### Practical Guides

- 🛠 [DigitalOcean: How to Install OpenLDAP on Ubuntu](https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-openldap-and-phpldapadmin-on-ubuntu-16-04) — Step-by-step install without Docker
- 🛠 [Linode: OpenLDAP Setup Guide](https://www.linode.com/docs/guides/openldap-server-debian/) — Debian-focused walkthrough with schema examples
- 🛠 [Red Hat: LDAP Authentication Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_authentication_and_authorization_in_rhel/configuring-sssd-to-use-ldap_configuring-authentication-and-authorization-in-rhel) — Connecting LDAP to system authentication

### Schema & LDIF Reference

- 📄 [LDIF Format Explained](https://ldap.com/ldif-the-ldap-data-interchange-format/) — How to write `.ldif` files for imports/exports
- 📄 [Common LDAP Object Classes](https://ldap.com/ldap-oid-reference-guide/) — inetOrgPerson, posixAccount, groupOfNames and more

### Security & Production

- 🔒 [Securing OpenLDAP with TLS](https://ubuntu.com/server/docs/service-ldap-with-tls) — Ubuntu guide for enabling LDAPS (port 636)
- 🔒 [LDAP Authentication Best Practices](https://cheatsheetseries.owasp.org/cheatsheets/LDAP_Injection_Prevention_Cheat_Sheet.html) — OWASP guide to avoiding LDAP injection