# Mailpit Email Testing Server - Complete Setup & Usage Guide

> **Purpose**: This guide provides a complete, step-by-step tutorial for deploying and using **Mailpit** as a lightweight email testing server with full REST API support. It is designed to support the **OpenText Knowledge Discovery PoC for Email** (see the accompanying `OpenText_Knowledge_Discovery_Email_PoC_Plan.docx`).

Mailpit captures all emails sent to it via SMTP, provides a beautiful web interface, and exposes a powerful REST API — perfect for development, testing, and PoC demonstrations.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Quick Start (Recommended)](#2-quick-start-recommended)
3. [Understanding the Docker Compose File](#3-understanding-the-docker-compose-file)
4. [Accessing Mailpit](#4-accessing-mailpit)
5. [Sending Test Emails](#5-sending-test-emails)
   - [5.1 Via SMTP (Recommended)](#51-via-smtp-recommended)
   - [5.2 Via HTTP REST API](#52-via-http-rest-api)
6. [Using the REST API](#6-using-the-rest-api)
7. [Integration with OpenText Knowledge Discovery PoC](#7-integration-with-opentext-knowledge-discovery-poc)
8. [Advanced Configuration](#8-advanced-configuration)
9. [Troubleshooting](#9-troubleshooting)
10. [Stopping and Cleaning Up](#10-stopping-and-cleaning-up)

---

## 1. Prerequisites

- Docker & Docker Compose installed
- Basic knowledge of terminal / command line
- (Optional) `jq` for pretty-printing JSON: `sudo apt install jq` (Linux) or `brew install jq` (macOS)
- (Optional) Python 3 for SMTP examples

---

## 2. Quick Start (Recommended)

```bash
# 1. Clone or download this repository (or just copy the files)

# 2. Start Mailpit
docker compose -f docker-compose-mailpit.yml up -d

# 3. Verify it's running
docker compose -f docker-compose-mailpit.yml ps

# 4. Open the web interface
# http://localhost:8025
```

You should now see the Mailpit dashboard. Any email sent to `localhost:1025` will appear here instantly.

---

## 3. Understanding the Docker Compose File

The file `docker-compose-mailpit.yml` contains everything needed:

| Setting                    | Value                  | Purpose                                      |
|---------------------------|------------------------|----------------------------------------------|
| **Image**                 | `axllent/mailpit:latest` | Official, actively maintained image         |
| **Web UI + API**          | Port `8025`            | Browser interface + REST API                 |
| **SMTP Server**           | Port `1025`            | Where applications send test emails          |
| **Persistent Storage**    | Named volume `mailpit-data` | Keeps emails between restarts         |
| **Testing Optimizations** | `MP_SMTP_AUTH_ACCEPT_ANY=1` | No authentication required for testing |

**Key Environment Variables** (already set for easy testing):
- `MP_MAX_MESSAGES=5000`
- `MP_DATABASE=/data/mailpit.db`
- `MP_SMTP_AUTH_ACCEPT_ANY=1`
- `MP_SMTP_AUTH_ALLOW_INSECURE=1`

---

## 4. Accessing Mailpit

| Service                    | URL / Address             | Description                              |
|---------------------------|---------------------------|------------------------------------------|
| **Web UI**                | http://localhost:8025     | View, search, and manage captured emails |
| **Interactive API Docs**  | http://localhost:8025/api/v1/ | Explore all REST endpoints live       |
| **SMTP (for sending)**    | `localhost:1025`          | Send emails from your app / scripts here |
| **REST API Base**         | http://localhost:8025/api/v1 | Programmatic access                     |

---

## 5. Sending Test Emails

### 5.1 Via SMTP (Recommended)

This is the **easiest and most reliable** method.

#### Method A: Python (Copy & Paste)

```bash
python3 -c '
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

msg = MIMEMultipart("alternative")
msg["Subject"] = "Welcome to the PoC!"
msg["From"] = "sender@company.com"
msg["To"] = "recipient@example.com"

html_content = """
<h1>Hello from Mailpit!</h1>
<p>This email was captured by Mailpit running in Docker.</p>
<p><strong>Great for testing OpenText Knowledge Discovery!</strong></p>
"""
msg.attach(MIMEText(html_content, "html"))

with smtplib.SMTP("localhost", 1025) as server:
    server.send_message(msg)
    print("✅ Email sent successfully via SMTP to Mailpit!")
'
```

#### Method B: Using `swaks` (if installed)

```bash
swaks --to recipient@example.com \
      --from sender@company.com \
      --server localhost:1025 \
      --header "Subject: PoC Test Email" \
      --body "This is a test email sent via SMTP."
```

#### Method C: Any Email Client

Configure your email client (Thunderbird, Outlook, etc.) with:
- **SMTP Server**: `localhost`
- **Port**: `1025`
- **No authentication** (or any username/password)

---

### 5.2 Via HTTP REST API

Mailpit supports sending emails directly via HTTP (available since v1.26+).

**Correct payload** (addresses must be objects):

```bash
curl -X POST http://localhost:8025/api/v1/send \
  -H "Content-Type: application/json" \
  -d '{
    "from": {
      "name": "PoC Test Sender",
      "email": "test@company.com"
    },
    "to": [
      {
        "name": "Test Recipient",
        "email": "user@example.com"
      }
    ],
    "subject": "PoC Test Email via HTTP API",
    "html": "<h1>Hello from Mailpit API!</h1><p>This works correctly.</p>"
  }'
```

> **Note**: If you get a JSON unmarshal error, make sure you are using the object format shown above (not plain strings).

---

## 6. Using the REST API

### Common Useful Endpoints

| Method | Endpoint                              | Description                        | Example |
|--------|---------------------------------------|------------------------------------|--------|
| GET    | `/api/v1/messages`                    | List all messages                  | `curl http://localhost:8025/api/v1/messages` |
| GET    | `/api/v1/search`                      | Search messages                    | `curl "http://localhost:8025/api/v1/search?query=subject:invoice"` |
| GET    | `/api/v1/message/{ID}`                | Get full message details           | `curl http://localhost:8025/api/v1/message/abc123` |
| DELETE | `/api/v1/messages`                    | Delete all messages                | `curl -X DELETE http://localhost:8025/api/v1/messages` |
| POST   | `/api/v1/send`                        | Send email via HTTP                | See section 5.2 |
| GET    | `/api/v1/info`                        | Server information                 | `curl http://localhost:8025/api/v1/info` |

**Pro Tip**: Visit `http://localhost:8025/api/v1/` in your browser for interactive documentation with "Try it out" buttons.

---

## 7. Integration with OpenText Knowledge Discovery PoC

This Mailpit setup is specifically designed to work with the **OpenText Knowledge Discovery Email PoC**.

### Recommended Workflow

1. Start Mailpit using this `docker-compose-mailpit.yml`
2. Use the Python generation scripts (from the PoC plan) to create realistic email data and send it to `localhost:1025`
3. Point OpenText Knowledge Discovery to index the captured emails (via filesystem connector on Mailpit's data directory or by exporting EML files)
4. Demonstrate entity extraction, search, classification, and security features on realistic email content

**Example**: Modify your email generation script to send directly to Mailpit:

```python
# In your generation script, replace the final delivery with:
with smtplib.SMTP("localhost", 1025) as server:
    server.send_message(email_message)
```

This creates a clean, repeatable, self-contained demo environment.

---

## 8. Advanced Configuration

You can customize behavior by editing environment variables in `docker-compose-mailpit.yml`:

```yaml
environment:
  MP_MAX_MESSAGES: 10000          # Increase capacity
  MP_VERBOSE: 1                   # Enable detailed logging
  MP_UI_AUTH: "admin:secret123"   # Add basic auth to the UI
```

After changing, restart with:

```bash
docker compose -f docker-compose-mailpit.yml up -d --force-recreate
```

---

## 9. Troubleshooting

| Problem                              | Solution                                                                 |
|--------------------------------------|--------------------------------------------------------------------------|
| Cannot connect to `localhost:1025`   | Make sure the container is running: `docker compose ps`                  |
| Emails not appearing in UI           | Check SMTP port (must be 1025). Try the Python example exactly.          |
| JSON error on `/api/v1/send`         | Use object format for `from` and `to` (see corrected example above)      |
| Port 8025 or 1025 already in use     | Change the ports in `docker-compose-mailpit.yml` (e.g., `8026:8025`)     |
| Want to start fresh                  | `docker compose down -v` (removes data volume)                           |
| Container keeps restarting           | Check logs: `docker compose logs mailpit`                                |

**View logs**:
```bash
docker compose -f docker-compose-mailpit.yml logs -f mailpit
```

---

## 10. Stopping and Cleaning Up

```bash
# Stop the server (keeps data)
docker compose -f docker-compose-mailpit.yml stop

# Stop and remove container (keeps data volume)
docker compose -f docker-compose-mailpit.yml down

# Stop and remove everything including emails
docker compose -f docker-compose-mailpit.yml down -v
```

---

## Summary

You now have a fully functional, production-grade email testing environment with:

- ✅ Easy Docker deployment
- ✅ Web UI for manual inspection
- ✅ Powerful REST API
- ✅ SMTP server for realistic testing
- ✅ Persistent storage
- ✅ Ready for OpenText Knowledge Discovery PoC demonstrations

**Next Steps**:
1. Start Mailpit
2. Send a few test emails using the Python example
3. Explore the UI and API
4. Integrate with your OpenText Knowledge Discovery PoC workflow

For the full PoC plan, refer to:  
`OpenText_Knowledge_Discovery_Email_PoC_Plan.docx`

---

*Document generated for the OpenText Knowledge Discovery Email PoC – June 2026*