#!/usr/bin/env python3
"""Notes summarizer Executa plugin for Mini Notes LLM summary."""

from __future__ import annotations

import json
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

try:
    import executa_sdk  # noqa: F401
except ModuleNotFoundError:
    _SDK_PATH = Path(__file__).resolve().parents[2] / "sdk" / "python"
    if _SDK_PATH.is_dir():
        sys.path.insert(0, str(_SDK_PATH))

import asyncio  # noqa: E402

from executa_sdk import (  # noqa: E402
    PROTOCOL_VERSION_V2,
    SamplingClient,
    SamplingError,
)

MANIFEST = {
    "name": "tool-test-notes-summarizer-12345678",
    "display_name": "Notes Summarizer",
    "version": "1.0.0",
    "description": "Summarize a list of short notes via host LLM sampling.",
    "host_capabilities": ["llm.sample"],
    "tools": [
        {
            "name": "summarize_notes",
            "description": "Summarize the user's notes into one concise paragraph.",
            "parameters": [
                {
                    "name": "notes",
                    "type": "array",
                    "description": "Notes to summarize; each item has order and content.",
                    "required": True,
                }
            ],
        }
    ],
    "runtime": {"type": "uv", "min_version": "0.1.0"},
}

_stdout_lock = threading.Lock()


def _write_frame(msg: dict) -> None:
    payload = json.dumps(msg, ensure_ascii=False)
    with _stdout_lock:
        sys.stdout.write(payload + "\n")
        sys.stdout.flush()


sampling = SamplingClient(write_frame=_write_frame)


def _format_notes(notes: list) -> str:
    lines: list[str] = []
    for item in notes:
        if not isinstance(item, dict):
            continue
        order = item.get("order", "?")
        content = str(item.get("content", "")).strip()
        if content:
            lines.append(f"{order}. {content}")
    return "\n".join(lines)


async def _summarize_notes(notes: list, *, invoke_id: str) -> dict:
    text = _format_notes(notes)
    if not text:
        return {"summary": "", "note": "empty notes"}

    result = await sampling.create_message(
        messages=[
            {
                "role": "user",
                "content": {
                    "type": "text",
                    "text": (
                        "Summarize the following numbered notes into one concise paragraph "
                        "(3-5 sentences). Return only the summary.\n\n" + text
                    ),
                },
            }
        ],
        max_tokens=512,
        system_prompt="You are a concise assistant helping the user review their notes.",
        metadata={"invoke_id": invoke_id, "tool": "summarize_notes"},
        timeout=60.0,
    )

    summary = ""
    content = result.get("content") or {}
    if isinstance(content, dict) and content.get("type") == "text":
        summary = content.get("text", "")

    return {
        "summary": summary,
        "model": result.get("model"),
        "usage": result.get("usage"),
        "stopReason": result.get("stopReason"),
    }


def _make_response(req_id, *, result=None, error=None) -> dict:
    out = {"jsonrpc": "2.0", "id": req_id}
    if error is not None:
        out["error"] = error
    else:
        out["result"] = result
    return out


def _handle_initialize(req_id, params: dict) -> dict:
    proto = (params or {}).get("protocolVersion") or "1.1"
    if proto != PROTOCOL_VERSION_V2:
        sampling.disable(
            f"host did not negotiate v2 (offered protocolVersion={proto!r}); "
            "sampling/createMessage requires Executa protocol 2.0"
        )
    return _make_response(
        req_id,
        result={
            "protocolVersion": proto if proto in ("1.1", "2.0") else "2.0",
            "serverInfo": {
                "name": MANIFEST["display_name"],
                "version": MANIFEST["version"],
            },
            "client_capabilities": {"sampling": {}} if proto == PROTOCOL_VERSION_V2 else {},
            "capabilities": {},
        },
    )


def _handle_describe(req_id) -> dict:
    return _make_response(req_id, result=MANIFEST)


def _handle_health(req_id) -> dict:
    return _make_response(
        req_id,
        result={
            "status": "healthy",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "version": MANIFEST["version"],
        },
    )


_loop = asyncio.new_event_loop()
_loop_thread = threading.Thread(target=_loop.run_forever, daemon=True)
_loop_thread.start()


def _handle_invoke(req_id, params: dict) -> dict:
    tool = params.get("tool")
    args = params.get("arguments") or {}
    invoke_id = params.get("invoke_id") or ""

    if tool != "summarize_notes":
        return _make_response(
            req_id,
            error={"code": -32601, "message": f"Unknown tool: {tool}"},
        )

    notes = args.get("notes") or []
    if not isinstance(notes, list):
        return _make_response(
            req_id,
            error={"code": -32602, "message": "notes must be an array"},
        )

    fut = asyncio.run_coroutine_threadsafe(
        _summarize_notes(notes, invoke_id=invoke_id),
        _loop,
    )
    try:
        data = fut.result(timeout=120.0)
    except SamplingError as e:
        return _make_response(
            req_id,
            error={"code": e.code, "message": e.message, "data": e.data},
        )
    except Exception as e:  # noqa: BLE001
        return _make_response(
            req_id,
            error={"code": -32603, "message": f"Tool execution failed: {e}"},
        )

    return _make_response(req_id, result={"success": True, "tool": tool, "data": data})


def _handle_message(line: str) -> None:
    try:
        msg = json.loads(line)
    except json.JSONDecodeError:
        _write_frame(_make_response(None, error={"code": -32700, "message": "Parse error"}))
        return

    if "method" not in msg:
        if not sampling.dispatch_response(msg):
            print(f"unmatched response id={msg.get('id')!r}", file=sys.stderr)
        return

    method = msg.get("method")
    req_id = msg.get("id")
    params = msg.get("params") or {}

    if method == "initialize":
        resp = _handle_initialize(req_id, params)
    elif method == "describe":
        resp = _handle_describe(req_id)
    elif method == "invoke":
        resp = _handle_invoke(req_id, params)
    elif method == "health":
        resp = _handle_health(req_id)
    elif method == "shutdown":
        resp = _make_response(req_id, result={"ok": True})
    else:
        resp = _make_response(req_id, error={"code": -32601, "message": f"Method not found: {method}"})

    if req_id is not None:
        _write_frame(resp)


def main() -> None:
    print("notes-summarizer plugin started", file=sys.stderr)
    pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix="invoke")
    try:
        for raw in sys.stdin:
            line = raw.strip()
            if not line:
                continue
            pool.submit(_handle_message, line)
    finally:
        pool.shutdown(wait=False, cancel_futures=True)
        _loop.call_soon_threadsafe(_loop.stop)


if __name__ == "__main__":
    main()
