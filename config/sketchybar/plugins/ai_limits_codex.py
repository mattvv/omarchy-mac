#!/usr/bin/env python3
"""Codex rate limits, ported from omarchy-agent-usage-codex.

Same approach: drive `codex app-server` over JSON-RPC (initialize ->
initialized -> account/read -> account/rateLimits/read) and read the
primary/secondary windows. Percent is kept on a 0-100 scale here so it matches
the Claude collector (omarchy divides by 100 for its own panel's convention).
"""
from __future__ import annotations
import datetime as dt, json, os, select, shutil, subprocess, sys, time
from pathlib import Path

CACHE = Path.home() / ".cache" / "omarchy-mac" / "ai-limits-codex.json"
TTL = 300


def find_codex() -> str:
    for c in (Path.home()/".local/share/mise/shims/codex",
              Path("/opt/homebrew/bin/codex"),
              Path.home()/".local/bin/codex"):
        if c.exists() and os.access(c, os.X_OK):
            return str(c)
    return shutil.which("codex") or ""


def number(v):
    try: return int(v)
    except Exception: return 0


def limit_window(w):
    if not isinstance(w, dict): return None
    used = w.get("usedPercent")
    if used is None: return None
    mins = number(w.get("windowDurationMins"))
    if mins == 10080:      label = "Weekly (7-day)"
    elif mins and mins % 60 == 0: label = f"{mins//60}h window"
    elif mins:             label = f"{mins}m window"
    else:                  label = "Limit"
    reset = w.get("resetsAt")
    return {"label": label, "percent": float(used),
            "resetsAt": dt.datetime.fromtimestamp(number(reset), dt.timezone.utc).isoformat() if reset else ""}


def rpc(proc, rid, method, params=None, timeout=8):
    proc.stdin.write(json.dumps({"id": rid, "method": method, "params": params or {}}) + "\n")
    proc.stdin.flush()
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([proc.stdout], [], [], 0.25)
        if not r: continue
        line = proc.stdout.readline()
        if not line: break
        try: msg = json.loads(line)
        except Exception: continue
        if msg.get("id") == rid: return msg
    raise TimeoutError(method)


def fetch():
    codex = find_codex()
    if not codex:
        return {"ok": False, "plan": "", "limits": [], "helpText": "codex not found"}
    try:
        proc = subprocess.Popen([codex, "-s", "read-only", "-a", "on-request", "app-server"],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True)
    except Exception as e:
        return {"ok": False, "plan": "", "limits": [], "helpText": str(e)[:60]}
    try:
        rpc(proc, 1, "initialize", {"clientInfo": {"name": "omarchy-mac", "version": "1"}}, 8)
        proc.stdin.write(json.dumps({"method": "initialized", "params": {}}) + "\n"); proc.stdin.flush()
        acct = rpc(proc, 2, "account/read", timeout=5)
        lim  = rpc(proc, 3, "account/rateLimits/read", timeout=5)
        account = (acct.get("result") or {}).get("account") or {}
        limits  = (lim.get("result") or {}).get("rateLimits") or {}
        plan = limits.get("planType") or account.get("planType") or account.get("type") or ""
        out = []
        for w in (limits.get("primary"), limits.get("secondary")):
            e = limit_window(w)
            if e: out.append(e)
        return {"ok": True, "plan": str(plan), "limits": out}
    except Exception as e:
        return {"ok": False, "plan": "", "limits": [], "helpText": f"codex RPC: {type(e).__name__}"}
    finally:
        try: proc.kill()
        except Exception: pass


def main():
    force = "--force" in sys.argv
    if not force and CACHE.exists():
        try:
            c = json.loads(CACHE.read_text())
            if time.time() - c.get("generated", 0) < TTL:
                print(json.dumps(c)); return
        except Exception: pass
    rec = fetch(); rec["generated"] = time.time()
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(rec))
    print(json.dumps(rec))

main()
