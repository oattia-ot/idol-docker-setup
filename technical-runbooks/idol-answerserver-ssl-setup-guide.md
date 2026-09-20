# IDOL AnswerServer 26.1.0 — Setup Guide (SSL / Docker Compose)

> **Scope:** AnswerBank · RAG · FactBank
> **Environment:** Docker Compose with `IDOL_SSL` enabled

---

## Architecture

```
Browser / Admin UI
        │ HTTPS
        ▼
  idol-answerserver:12000
        ├──► idol-answerbank-agentstore:12200 (ACI) / :12201 (Index)
        ├──► idol-passageextractor-content:9103 (ACI)
        └──► idol-licenseserver:20000
```

---

## Step 1 — Configure the AnswerBank Section Correctly

Use `IdolHost` — **not** `AgentstoreHost` — for `Type=answerbank`.

```properties
[AnswerBank]
Type=answerbank
IdolHost=idol-answerbank-agentstore     # ← must be IdolHost
IdolAciPort=12200
IdolSslConfig=SSLSettings              # ← outbound SSL to agentstore
```

**Rules:**
- `AgentstoreHost` is only valid for `Type=passageextractor` — never for `answerbank`.
- Do **not** set `IdolIndexPort` — AnswerServer auto-derives it as `IdolAciPort + 1`.
- Do **not** place `SSLConfig` inside an answer system section — it belongs in `[Server]` only.

---

## Step 2 — Configure the RAG Section Correctly

Use `IdolSslConfig` for the outbound connection to the Content engine.

```properties
[RAG]
Type=RAG
IdolHost=idol-passageextractor-content
IdolAciPort=9103
IdolSslConfig=BackendSSL               # ← outbound SSL to Content engine
ModuleID=RAGLLMModule
ACIMaxResults=3
RetrievalType=mixed
PromptTemplatePath=./rag/prompt_template.txt
PromptTokenLimit=3000
MaxQuestionSize=70
CandidateRetrievalDefaults=RAGRetrievalParams

[RAGRetrievalParams]
MinScore=0

[RAGLLMModule]
Type=GenerativePython
Script=./rag/ollama_server.py
```

> `SSLConfig` controls the **inbound** listener — using it for outbound connections
> causes silent failures where RAG returns zero answers.

---

## Step 3 — Configure SSL Sections in `answerserver.cfg`

```properties
# Own inbound listener — referenced by [Server]
[SSLSettings]
SSLMethod=Negotiate
SSLCertificate=/ssl/certs/idol-answerserver-fullchain.cert.pem
SSLPrivateKey=/ssl/certs/idol-answerserver.key.pem
SSLCACertificate=/ssl/certs/ca-chain.cert.pem
SSLCheckCertificate=0

# Outbound client SSL — used by RAG to reach Content engine
[BackendSSL]
SSLMethod=Negotiate
SSLCACertificate=/ssl/certs/ca-chain.cert.pem
SSLVerifyClient=0
```

---

## Step 4 — Configure the Agentstore `idol_ssl.cfg`

`SSLCACertificate` is **mandatory** — without it the TLS handshake fails.

```properties
[EnableSSL]
SSLConfig=SSLSettings
IdolSslConfig=SSLSettings
AgentstoreSslConfig=SSLSettings

[SSLSettings]
SSLMethod=Negotiate
SSLCertificate=/ssl/certs/idol-answerbank-agentstore-fullchain.cert.pem
SSLPrivateKey=/ssl/certs/idol-answerbank-agentstore.key.pem
SSLCACertificate=/ssl/certs/ca-chain.cert.pem   # ← required — do not omit
SSLCheckCertificate=0
```

---

## SSL Parameter Reference

Understanding which parameter to use **where** is the most critical concept:

| Parameter | Direction | Where to Use |
|---|---|---|
| `SSLConfig` | **Inbound** | `[Server]` only — AnswerServer's own ACI listener |
| `IdolSslConfig` | **Outbound** | Connecting to a Content / DRE / Agentstore engine |
| `AgentstoreSslConfig` | **Outbound** | Connecting to Agentstore (`passageextractor` type only) |
| `LicenseSSL` | **Outbound** | Connecting to License server |

> **Rule of thumb:** AnswerServer *receiving* → `SSLConfig`.
> AnswerServer *connecting* → use the appropriate `Idol-` prefixed variant.

---

## Step 5 — Validate Startup Log

After starting AnswerServer, confirm these lines are **present**:

```
✅ Created answer system 'AnswerBank' (type: answerbank)
✅ Starting background stats update thread
✅ Starting background likelihood update thread
✅ Deleted 0 old stats records from stats DB
✅ Created answer system 'RAG' (type: rag)
✅ Created answer system 'FactBank' (type: factbank)
✅ ACI Server starting at <ip>:12000
```

And confirm these errors are **absent**:

```
❌ Can't construct IdolIndexer without a valid hostname
❌ IDOLIndexer: HTTP error sending command to ...:0
❌ No dummy document indexed! Much functionality will not work.
❌ Failed to set knowledge from concept DRE.
❌ ssl/tls alert certificate unknown  (from backend services — browser errors are harmless)
```

---

## Common Errors & Fixes

| Error | Cause | Fix |
|---|---|---|
| `Can't construct IdolIndexer without a valid hostname` | Used `AgentstoreHost` instead of `IdolHost` | Change to `IdolHost=` in `[AnswerBank]` |
| `DREADDDATA sent to port 0` | `IdolIndexPort` explicitly set | Remove `IdolIndexPort` — auto-derived as `IdolAciPort + 1` |
| `ssl/tls alert certificate unknown` | `SSLCACertificate` missing in agentstore `idol_ssl.cfg` | Add `SSLCACertificate=/ssl/certs/ca-chain.cert.pem` |
| `Failed to set knowledge from concept DRE` | Used `SSLConfig` instead of `IdolSslConfig` in `[RAG]` | Change to `IdolSslConfig=BackendSSL` |

---

## Browser SSL Errors (Non-Critical)

Log entries like:
```
SSL handshake failed on connection from client 172.19.0.1
```
come from the **Admin UI browser**, not backend services, and do not affect functionality.
To resolve, install `ca-chain.cert.pem` into your browser or OS trust store.