# Setting Up a Local LLM with Ollama for IDOL Answer Server (RAG)

## Overview

This guide summarises the steps required to connect a local LLM (via Ollama) to an
OpenText IDOL Answer Server RAG system using a custom Python `generate` script.

---

## 1. Prerequisites

- Ollama installed and running on the target host (e.g. `172.25.112.1`)
- IDOL Answer Server configured with a RAG answer system
- Local `.gguf` model files available on disk
- Python environment with `requests` and `transformers` packages

---

## 2. Verify Ollama is Running

```bash
# Check Ollama is reachable and returning model list
curl -v http://<OLLAMA_HOST>:11434/api/tags

# Check Ollama version (must be >= 0.1.14 for /api/chat support)
curl -s http://<OLLAMA_HOST>:11434/api/version
```

> `/api/chat` was introduced in Ollama **v0.1.14**. Older versions only support `/api/generate`.
> If needed, upgrade: `curl -fsSL https://ollama.com/install.sh | sh`

---

## 3. Register Local GGUF Models with Ollama

`ollama pull` only fetches from the cloud registry. For local `.gguf` files you must
use `ollama create` with a `Modelfile`.

### 3.1 Create a Modelfile

```bash
cat > /tmp/Modelfile-gemma4e4b << 'EOF'
FROM /path/to/models/Gemma-4-E4B.gguf
PARAMETER temperature 0
PARAMETER num_predict 256
EOF
```

### 3.2 Register the Model

```bash
ollama create gemma-4-e4b -f /tmp/Modelfile-gemma4e4b
```

### 3.3 Verify Registration

```bash
ollama list
# Expected output:
# NAME                 ID              SIZE     MODIFIED
# gemma-4-e4b:latest   c8c60d34e86b    13 GB    X minutes ago
```

> **Important:** If Ollama runs inside **Docker**, `ollama create` must be run
> **inside the container**, not on the host — otherwise the service won't see the model.
>
> ```bash
> docker cp /path/to/Gemma-4-E4B.gguf ollama:/tmp/
> docker exec ollama ollama create gemma-4-e4b -f /tmp/Modelfile
> docker exec ollama ollama list
> ```

---

## 4. Test the Ollama API Directly

Before touching IDOL, confirm the model responds correctly:

```bash
curl -s -X POST http://<OLLAMA_HOST>:11434/api/chat \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemma-4-e4b:latest",
    "messages": [{"role": "user", "content": "hello"}],
    "stream": false
  }'
```

Expected response shape:
```json
{
  "model": "gemma-4-e4b:latest",
  "message": { "role": "assistant", "content": "Hello! How can I help you?" },
  "done": true,
  "done_reason": "stop"
}
```

> If `done_reason` is `load` or `length` with empty content, see Section 6.

---

## 5. Configure the IDOL Python Script

### 5.1 Key Variables

The script reads two environment variables:

| Variable | Purpose | Example Value |
|---|---|---|
| `IDOL_LLM_ENDPOINT` | Ollama API URL | `http://172.25.112.1:11434/api/chat` |
| `IDOL_LLM_MODEL` | Registered model name | `gemma-4-e4b:latest` |

### 5.2 Critical Rules

| | Correct | Wrong |
|---|---|---|
| Endpoint | `/api/chat` | `/api/generate` |
| Payload format | `messages[]` array | `prompt` string |
| Response key | `message.content` | `response` |
| Model name | Exact name from `ollama list` | `.gguf` filename |

> `/api/chat` and `/api/generate` are **incompatible** — mixing endpoint and payload
> format causes silent failures or runtime errors.

### 5.3 Final Working Script

```python
import os
from typing import Tuple
import requests
from transformers import AutoTokenizer

LLM_ENDPOINT = os.getenv('IDOL_LLM_ENDPOINT') or 'http://172.25.112.1:11434/api/chat'
LLM_MODEL    = os.getenv('IDOL_LLM_MODEL')    or 'gemma-4-e4b:latest'


def generate(prompt: str) -> str:
    if 'Question:' in prompt:
        context, question = prompt.split('Question:', 1)
    else:
        context  = ''
        question = prompt

    chat_history = question.split('+')
    messages = [{"role": "system", "content": context.strip()}]

    n = 0
    for chat in chat_history:
        n += 1
        role = "user" if n % 2 == 1 else "assistant"
        if chat.strip():
            messages.append({"role": role, "content": chat.strip()})

    if not any(m["role"] == "user" for m in messages):
        messages.append({"role": "user", "content": prompt.strip()})

    headers = {'Content-Type': 'application/json'}
    data = {
        "model":    LLM_MODEL,
        "messages": messages,
        "stream":   False,
        "options": {
            "temperature": 0,
            "num_predict": 512,
            "num_ctx":     4096,
        }
    }

    total_chars = sum(len(m['content']) for m in messages)
    print(f"[DEBUG] Endpoint={LLM_ENDPOINT}, model={LLM_MODEL}, prompt_chars={total_chars}")

    response = requests.post(LLM_ENDPOINT, headers=headers, json=data, timeout=300)
    response.raise_for_status()

    response_json = response.json()
    print(f"[DEBUG] Response: {response_json}")

    if 'message' not in response_json:
        raise RuntimeError(f"Unable to find 'message' in response:\n{response.text}")

    if 'content' not in (message := response_json['message']):
        raise RuntimeError(f"'content' not found in 'message':\n{response.text}")

    content = message['content'].strip()

    if not content:
        raise RuntimeError(
            f"Model returned empty content. done_reason={response_json.get('done_reason')}. "
            f"Messages sent: {messages}"
        )

    return content


def get_token_count(text: str, token_limit: int) -> Tuple[str, int]:
    tokenizer_cache_dir = os.path.join(os.path.dirname(__file__), "tokenizer_cache")
    tokenizer = AutoTokenizer.from_pretrained(tokenizer_cache_dir)

    chat_completion_tokenized = tokenizer.encode(
        f'[INST] {text} [/INST]', add_special_tokens=True
    )
    original_token_count = len(chat_completion_tokenized)

    truncated_text = text
    if original_token_count > token_limit:
        tokenized_text_no_specials = tokenizer.encode(text, add_special_tokens=False)
        special_token_count = original_token_count - len(tokenized_text_no_specials)
        truncated_text_token_limit = max(token_limit - special_token_count, 1)
        truncated_text_tokenized   = tokenized_text_no_specials[:truncated_text_token_limit]
        truncated_text             = tokenizer.decode(
            truncated_text_tokenized, clean_up_tokenization_spaces=True
        )

    return truncated_text, original_token_count
```

---

## 6. Common Errors & Fixes

### 6.1 `404 Not Found` on `/api/chat`

| Cause | Fix |
|---|---|
| Ollama version < 0.1.14 | Upgrade Ollama |
| Model not registered | Run `ollama create` (see Section 3) |
| Wrong model name in env var | Match exactly to `ollama list` output |
| Proxy/Docker instance mismatch | Run `ollama create` inside the container |

### 6.2 `405 Method Not Allowed`

A reverse proxy (nginx, Caddy, Traefik) is intercepting the request and blocking POST.
Check what is actually bound to port 11434:

```bash
ss -tlnp | grep 11434
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep 11434
```

### 6.3 `Unable to find 'response' in response`

Script is using `/api/generate` response parsing but calling `/api/chat`.
Fix: ensure endpoint and response key are consistent (use `/api/chat` + `message.content`).

### 6.4 `done_reason=load` with Empty Content

Model loaded but produced no output — prompt/payload mismatch. Ensure `messages[]`
is sent to `/api/chat`, not `/api/generate`.

### 6.5 `done_reason=length` with Empty Content

System prompt is consuming the entire context window. Fix: increase `num_ctx`:

```python
"options": {
    "num_predict": 512,
    "num_ctx":     4096,
}
```

---

## 7. Environment Variables — How to Set Permanently

`export` only applies to the current shell session and is **not inherited** by IDOL
system services. Use one of these methods instead:

### Option A — Hardcode defaults in the Python script (simplest)
```python
LLM_ENDPOINT = os.getenv('IDOL_LLM_ENDPOINT') or 'http://172.25.112.1:11434/api/chat'
LLM_MODEL    = os.getenv('IDOL_LLM_MODEL')    or 'gemma-4-e4b:latest'
```

### Option B — Set in IDOL Answer Server config
```ini
[RAG]
PythonEnvironmentVariables=IDOL_LLM_ENDPOINT=http://172.25.112.1:11434/api/chat,IDOL_LLM_MODEL=gemma-4-e4b:latest
```

---

## 8. Restart & Validate

```bash
# Restart IDOL Answer Server
systemctl restart answerserver

# Tail the log
tail -f /path/to/answerserver.log | grep -E "RAG|LLM|error|warn|DEBUG"
```

Test via the IDOL Admin console:
```
https://<IDOL_HOST>:12000/a=admin#page/console/test-action/action=ask&text=what+is+management%27s+responsibility%3F&systemnames=RAG
```

Expected: A concise answer drawn from the ingested document context with no errors in the warnings panel.

---

## 9. Models Used in This Setup

| File | Registered Name | Size |
|---|---|---|
| `Gemma-4-E4B.gguf` | `gemma-4-e4b:latest` | ~13 GB |
| `Gemma-4-E2B.gguf` | `gemma-4-e2b:latest` | ~3 GB |
| `DeepSeek-R1-7B.gguf` | `deepseek-r1-7b:latest` | ~4.7 GB |
| `Qwen2.5-1.5B-Instruct.gguf` | `qwen2.5-1.5b-instruct:latest` | ~1.1 GB |
