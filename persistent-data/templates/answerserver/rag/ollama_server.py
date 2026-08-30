import os
from typing import Tuple

import requests
from transformers import AutoTokenizer

LLM_ENDPOINT = os.getenv("IDOL_LLM_ENDPOINT") or "http://ollama:11434/api/chat"
LLM_MODEL = os.getenv("IDOL_LLM_MODEL") or "gemma4:e4b"
LLM_TIMEOUT = int(os.getenv("IDOL_LLM_TIMEOUT") or "600")


def generate(prompt: str) -> str:
    if "Question:" in prompt:
        context, question = prompt.split("Question:", 1)
    else:
        context = ""
        question = prompt

    chat_history = question.split("+")
    messages = [{"role": "system", "content": context.strip()}]

    n = 0
    for chat in chat_history:
        n += 1
        role = "user" if n % 2 == 1 else "assistant"
        if chat.strip():
            messages.append({"role": role, "content": chat.strip()})

    if not any(m["role"] == "user" for m in messages):
        messages.append({"role": "user", "content": prompt.strip()})

    data = {
        "model": LLM_MODEL,
        "messages": messages,
        "stream": False,
        "think": False,
        "keep_alive": "60m",
        "options": {
            "temperature": 0,
            "num_predict": 256,
            "num_ctx": 4096,
        },
    }

    total_chars = sum(len(m["content"]) for m in messages)
    print(f"[DEBUG] Endpoint={LLM_ENDPOINT}, model={LLM_MODEL}, prompt_chars={total_chars}")
    print(f"[DEBUG] Messages: {messages}")

    response = requests.post(
        LLM_ENDPOINT,
        headers={"Content-Type": "application/json"},
        json=data,
        timeout=(10, LLM_TIMEOUT),
    )
    response.raise_for_status()
    response_json = response.json()
    print(f"[DEBUG] Response: {response_json}")

    message = response_json.get("message") or {}
    content = (message.get("content") or "").strip()

    # Gemma 4 sometimes parks the answer in thinking if think was not honored
    if not content:
        content = (message.get("thinking") or "").strip()

    if not content:
        raise RuntimeError(
            "Model returned empty content. "
            f"done_reason={response_json.get('done_reason')}. "
            f"eval_count={response_json.get('eval_count')}. "
            f"total_duration={response_json.get('total_duration')}. "
            f"Messages sent: {messages}"
        )

    return content


def get_token_count(text: str, token_limit: int) -> Tuple[str, int]:
    tokenizer_cache_dir = os.path.join(os.path.dirname(__file__), "tokenizer_cache")
    tokenizer = AutoTokenizer.from_pretrained(tokenizer_cache_dir)

    tokenized = tokenizer.encode(text, add_special_tokens=True)
    original_token_count = len(tokenized)

    truncated_text = text
    if original_token_count > token_limit:
        tokenized_no_specials = tokenizer.encode(text, add_special_tokens=False)
        special_token_count = original_token_count - len(tokenized_no_specials)
        keep = max(token_limit - special_token_count, 1)
        truncated_text = tokenizer.decode(
            tokenized_no_specials[:keep],
            clean_up_tokenization_spaces=True,
        )

    return truncated_text, original_token_count