"""A local open model, through Ollama (https://ollama.com), for the tools in
this folder. Nothing leaves this computer.

    ollama pull qwen2.5:14b        # once
    LLM_MODEL=qwen2.5:7b ...       # another model for one run
"""
import json
import os
import re
import time
import urllib.request

HOST = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
MODEL = os.environ.get("LLM_MODEL", "qwen2.5:14b")


def ask(system: str, prompt: str, *, json_mode: bool = False,
        temperature: float = 0.3, context: int = 8192, retries: int = 2):
    """The model's answer to [prompt]; a dict when [json_mode]."""
    body = {
        "model": MODEL,
        "stream": False,
        "messages": [{"role": "system", "content": system},
                     {"role": "user", "content": prompt}],
        "options": {"temperature": temperature, "num_ctx": context},
        # kept loaded between calls of one run
        "keep_alive": "15m",
    }
    if json_mode:
        body["format"] = "json"
    # reasoning models (qwen3…) think before they answer: LLM_THINK=off
    # skips it (faster, weaker); the thinking is kept apart from the answer
    if "LLM_THINK" in os.environ:
        body["think"] = os.environ["LLM_THINK"] != "off"
    last = None
    for attempt in range(retries + 1):
        try:
            request = urllib.request.Request(
                f"{HOST}/api/chat", json.dumps(body).encode("utf-8"),
                {"Content-Type": "application/json"})
            # a CPU reads a long game for minutes before it answers
            with urllib.request.urlopen(request, timeout=3600) as response:
                text = json.load(response)["message"]["content"]
            # older servers leave the thinking in the answer
            text = re.sub(r"(?s)<think>.*?</think>", "", text).strip()
            return json.loads(text) if json_mode else text
        except (OSError, ValueError, KeyError) as error:
            last = error
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"no answer from {MODEL} at {HOST}: {last}")


def available() -> bool:
    try:
        with urllib.request.urlopen(f"{HOST}/api/tags", timeout=5) as response:
            names = [m["name"] for m in json.load(response)["models"]]
        return any(n == MODEL or n.startswith(MODEL + ":") for n in names)
    except OSError:
        return False
