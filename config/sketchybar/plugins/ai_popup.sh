#!/usr/bin/env bash
PLUG="$HOME/.config/sketchybar/plugins-omarchy"
"$PLUG/popup_close.sh"
CL=$(python3 "$PLUG/ai_limits.py" 2>/dev/null)
CX=$(python3 "$PLUG/ai_limits_codex.py" 2>/dev/null)
python3 - "$CL" "$CX" <<'PY'
import sys, json, subprocess, datetime as dt
def when(iso):
    if not iso: return ''
    try: t=dt.datetime.fromisoformat(iso).astimezone()
    except Exception: return ''
    now=dt.datetime.now().astimezone()
    return t.strftime('%H:%M') if t.date()==now.date() else t.strftime('%a %H:%M')
def load(s):
    try: return json.loads(s)
    except Exception: return {}
rows=[]
for name, d in (("Claude", load(sys.argv[1])), ("Codex", load(sys.argv[2]))):
    plan=(d.get('plan') or '').strip()
    if d.get('ok') and d.get('limits'):
        rows.append(f"{name} {plan}".rstrip())
        for l in d['limits'][:4]:
            rows.append(f"  {l['label']:<18}{l['percent']:>4.0f}%  {when(l.get('resetsAt')):>9}")
    else:
        rows.append(f"{name}: {(d.get('helpText') or 'unavailable')[:28]}")
items=[f'ai.r{n}' for n in range(1,10)]
for i,t in enumerate(rows[:9]):
    subprocess.run(['sketchybar','--set',items[i],f'label={t}','drawing=on'],capture_output=True)
for j in range(len(rows),9):
    subprocess.run(['sketchybar','--set',items[j],'label=','drawing=off'],capture_output=True)
PY
sketchybar --set ai popup.drawing=toggle
