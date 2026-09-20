#!/usr/bin/env python3
"""Authoritative Claude usage limits, ported from omarchy-agent-usage-claude.

Same endpoint, headers, bucket precedence and percent-scale detection as
omarchy. Only difference: macOS Claude Code keeps credentials in the login
Keychain, not ~/.claude/.credentials.json (which is Linux-only).

The access token goes nowhere but the Authorization header of the probe. It is
never printed, logged, or written to the cache.
"""
from __future__ import annotations
import datetime as dt, json, re, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path
from typing import Any

USAGE_ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
CACHE = Path.home() / ".cache" / "omarchy-mac" / "ai-limits.json"
TTL = 300


def number(v: Any) -> int:
    try: return int(v)
    except Exception: return 0


def plan_label(tier: str, subscription: str) -> str:
    if tier:
        m = re.search(r"max_(\d+x)", tier, re.IGNORECASE)
        if m: return "Max " + m.group(1)
    if subscription: return subscription[0].upper() + subscription[1:]
    return ""


def oauth_login() -> tuple[str, int, str]:
    """macOS: credentials live in the login Keychain."""
    try:
        raw = subprocess.run(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
            capture_output=True, text=True, timeout=10).stdout.strip()
        data = json.loads(raw)
    except Exception:
        return "", 0, ""
    login = data.get("claudeAiOauth")
    if not isinstance(login, dict): return "", 0, ""
    plan = plan_label(str(login.get("rateLimitTier") or ""),
                      str(login.get("subscriptionType") or ""))
    return str(login.get("accessToken") or ""), number(login.get("expiresAt")), plan


def parse_utilization(v: Any) -> float:
    try: return float(str(v).strip().replace("%", ""))
    except Exception: return float("nan")


def normalize_utilization(v: Any, percent_scale: bool) -> float:
    n = parse_utilization(v)
    if n != n: return -1.0
    if percent_scale or n > 1: return n
    return n * 100.0


def normalize_reset_at(raw: Any) -> str:
    if not raw: return ""
    raw = str(raw)
    try: return dt.datetime.fromisoformat(raw.replace("Z", "+00:00")).isoformat()
    except Exception: return raw


def usage_bucket(payload: dict, key: str):
    b = payload.get(key)
    return b if isinstance(b, dict) else None


def scoped_window(kind: str) -> str:
    t = kind.lower()
    if "month" in t: return "Monthly"
    if "week" in t or "day" in t: return "Weekly"
    if "hour" in t or "session" in t: return "Session"
    return ""


def scoped_limits(payload: dict, percent_scale: bool) -> list[dict]:
    entries = payload.get("limits")
    if not isinstance(entries, list): return []
    out, seen = [], set()
    for e in entries:
        if not isinstance(e, dict): continue
        scope = e.get("scope")
        model = scope.get("model") if isinstance(scope, dict) else None
        if not isinstance(model, dict): continue
        name = str(model.get("display_name") or model.get("id") or "").strip()
        kind = str(e.get("kind") or "").strip()
        if name == "" or (name, kind) in seen: continue
        pct = normalize_utilization(e.get("percent"), percent_scale)
        if pct < 0: continue
        seen.add((name, kind))
        w = scoped_window(kind)
        out.append({"label": (name + " " + w) if w else name,
                    "percent": pct, "resetsAt": normalize_reset_at(e.get("resets_at"))})
    return out


def probe(token: str) -> dict:
    req = urllib.request.Request(USAGE_ENDPOINT, headers={
        "Authorization": "Bearer " + token,
        "anthropic-beta": "oauth-2025-04-20",
        "Accept": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            payload = json.loads(r.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as e:
        return {"ok": False, "helpText": f"usage endpoint returned {e.code}"}
    except Exception:
        return {"ok": False, "helpText": "couldn't reach usage endpoint"}

    weekly = usage_bucket(payload, "seven_day_oauth_apps") or usage_bucket(payload, "seven_day")
    session = usage_bucket(payload, "five_hour")
    raw = [session.get("utilization") if session else None,
           weekly.get("utilization") if weekly else None]
    entries = payload.get("limits")
    if isinstance(entries, list):
        raw += [e.get("percent") for e in entries if isinstance(e, dict)]
    percent_scale = any(parse_utilization(v) >= 1 for v in raw)

    limits = []
    if session is not None:
        p = normalize_utilization(session.get("utilization"), percent_scale)
        if p >= 0: limits.append({"label": "Session (5-hour)", "percent": p,
                                  "resetsAt": normalize_reset_at(session.get("resets_at"))})
    if weekly is not None:
        p = normalize_utilization(weekly.get("utilization"), percent_scale)
        if p >= 0: limits.append({"label": "Weekly (7-day)", "percent": p,
                                  "resetsAt": normalize_reset_at(weekly.get("resets_at"))})
    limits += scoped_limits(payload, percent_scale)
    return {"ok": True, "limits": limits}


def main():
    force = "--force" in sys.argv
    if not force and CACHE.exists():
        try:
            c = json.loads(CACHE.read_text())
            if time.time() - c.get("generated", 0) < TTL:
                print(json.dumps(c)); return
        except Exception:
            pass
    token, expires, plan = oauth_login()
    if not token:
        rec = {"generated": time.time(), "ok": False, "plan": "",
               "helpText": "no Claude credentials found", "limits": []}
    else:
        rec = probe(token)
        rec["plan"] = plan
        rec["generated"] = time.time()
    del token
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(rec))
    print(json.dumps(rec))


main()
