#!/usr/bin/env python3
"""Collect local AI agent usage into one JSON record.

Ports the local-transcript half of omarchy's `omarchy-agent-usage-claude`:
token counts come from ~/.claude/projects/**/*.jsonl, where each assistant
message carries message.usage with input/output/cache token fields.

Deliberately does NOT touch credentials or the Anthropic OAuth usage endpoint
that omarchy uses for authoritative rate limits -- this reads local files only.
"""
import json, os, sys, time, datetime as dt
from pathlib import Path

CACHE = Path.home() / ".cache" / "omarchy-mac" / "ai-usage.json"
TTL = 60

def empty():
    return {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "msgs": 0}

def add(b, u):
    b["input"]       += u.get("input_tokens", 0) or 0
    b["output"]      += u.get("output_tokens", 0) or 0
    b["cache_read"]  += u.get("cache_read_input_tokens", 0) or 0
    b["cache_write"] += u.get("cache_creation_input_tokens", 0) or 0
    b["msgs"]        += 1

def collect():
    today = dt.date.today()
    tot, day = empty(), empty()
    by_model, days = {}, set()

    root = Path.home() / ".claude" / "projects"
    for f in root.rglob("*.jsonl"):
        try:
            with f.open(errors="ignore") as fh:
                for line in fh:
                    if '"usage"' not in line:
                        continue
                    try:
                        e = json.loads(line)
                    except Exception:
                        continue
                    msg = e.get("message") or {}
                    u = msg.get("usage") or e.get("usage")
                    if not isinstance(u, dict):
                        continue
                    ts = e.get("timestamp")
                    d = None
                    if ts:
                        try:
                            d = dt.datetime.fromisoformat(
                                ts.replace("Z", "+00:00")).astimezone().date()
                        except Exception:
                            pass
                    add(tot, u)
                    if d:
                        days.add(d.isoformat())
                        if d == today:
                            add(day, u)
                    m = msg.get("model") or "unknown"
                    if m != "unknown":
                        add(by_model.setdefault(m, empty()), u)
        except Exception:
            continue

    # Codex: best effort -- rollouts may carry token_count events
    codex = empty()
    croot = Path.home() / ".codex" / "sessions"
    if croot.exists():
        for f in list(croot.rglob("*.jsonl"))[-40:]:
            # total_token_usage is CUMULATIVE per session, so keep only the
            # last snapshot per file -- summing every event double-counts.
            last = None
            try:
                with f.open(errors="ignore") as fh:
                    for line in fh:
                        if "token" not in line:
                            continue
                        try:
                            e = json.loads(line)
                        except Exception:
                            continue
                        p_ = e.get("payload") or {}
                        info = p_.get("info") or p_
                        u = info.get("total_token_usage")
                        if isinstance(u, dict):
                            last = u
            except Exception:
                continue
            if last:
                codex["input"]      += last.get("input_tokens", 0) or 0
                codex["output"]     += last.get("output_tokens", 0) or 0
                codex["cache_read"] += last.get("cached_input_tokens", 0) or 0
                codex["msgs"]       += 1

    top = sorted(by_model.items(),
                 key=lambda kv: -(kv[1]["input"] + kv[1]["output"] +
                                  kv[1]["cache_read"] + kv[1]["cache_write"]))
    return {
        "generated": time.time(),
        "today": day, "total": tot,
        "days": len(days),
        "models": [{"model": k, **v} for k, v in top[:3]],
        "codex": codex,
    }

def main():
    force = "--force" in sys.argv
    if not force and CACHE.exists():
        try:
            c = json.loads(CACHE.read_text())
            if time.time() - c.get("generated", 0) < TTL:
                print(json.dumps(c)); return
        except Exception:
            pass
    rec = collect()
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(rec))
    print(json.dumps(rec))

main()
