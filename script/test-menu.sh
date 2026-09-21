#!/usr/bin/env bash
# Menu tests. Every one of these failed at least once while being written.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
fail=0
ok()  { printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
check() { [ "$2" = "$3" ] && ok "$1" || bad "$1: expected [$3] got [$2]"; }

echo "menu.py"
# A GUI launch gets /usr/bin/python3 (3.9) and no Homebrew. That is the
# environment the menu really runs in, so it is the one to test in.
rows39=$(env -i HOME="$HOME" PATH=/usr/bin:/bin /usr/bin/python3 bin/menu.py rows root 2>&1 | wc -l | tr -d ' ')
[ "$rows39" -ge 3 ] && ok "root rows under python 3.9 ($rows39)" || bad "root rows under 3.9: $rows39"

check "alias theme -> style.theme" "$(python3 bin/menu.py resolve theme)" "style.theme"
check "alias power -> system"      "$(python3 bin/menu.py resolve power)" "system"
check "unknown alias is empty"     "$(python3 bin/menu.py resolve nope)"  ""

# The stripper must not treat // inside a string as a comment, or every action
# holding a URL is silently truncated to "open https:".
url=$(python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('m','bin/menu.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.load()['learn.omarchy']['action'])")
check "// inside a string survives" "$url" "open https://omarchy.org"

# A submenu lists one level of children, not the whole subtree.
style_children=$(python3 bin/menu.py rows style | wc -l | tr -d ' ')
[ "$style_children" -ge 4 ] && ok "style has $style_children children" \
  || bad "style: expected at least 4, got $style_children"
# Counts move as the menu grows; assert the shape, not a frozen number.
bar_children=$(python3 bin/menu.py rows style.bar | wc -l | tr -d ' ')
[ "$bar_children" -ge 3 ] && ok "bar submenu has $bar_children children" \
  || bad "bar submenu: expected at least 3, got $bar_children"
check "position submenu is 2" "$(python3 bin/menu.py rows style.bar.position | wc -l | tr -d ' ')" "2"

echo "actions"
# Every action's command must exist: a typo is invisible until someone picks
# that row and nothing happens. Tokenise with shlex, not awk -- paths contain
# escaped spaces, and splitting on whitespace turns
# "/System/Library/CoreServices/Menu\ Extras/..." into a path that is not there.
python3 - <<'PYEOF' > /tmp/menu-actions.txt
import importlib.util, os, shlex
spec = importlib.util.spec_from_file_location('m', 'bin/menu.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for key, value in m.load().items():
    action = value.get("action")
    if not action:
        continue
    action = action.replace("$OMARCHY_BIN", os.path.expanduser("~/.local/bin"))
    print("%s\t%s" % (key, shlex.split(action)[0]))
PYEOF
while IFS=$'\t' read -r key cmd; do
  if command -v "$cmd" >/dev/null 2>&1 || [ -x "$cmd" ]; then
    ok "$key -> $(basename "$cmd")"
  else
    bad "$key -> $cmd does not exist"
  fi
done < /tmp/menu-actions.txt

echo "dispatch"
# End to end, in the environment that keeps breaking things: no PATH, no USER.
# style.bar.toggle is the one action with a state you can read back, and running
# it twice leaves the bar as it was found.
pause() { python3 -c "import time;time.sleep($1)"; }
hidden_now() { sketchybar --query bar | python3 -c "import sys,json;print(json.load(sys.stdin)['hidden'])"; }
if command -v sketchybar >/dev/null 2>&1; then
  d0=$(hidden_now)
  env -i HOME="$HOME" PATH=/usr/bin:/bin /usr/bin/python3 bin/menu.py run style.bar.toggle >/dev/null 2>&1
  pause 1
  d1=$(hidden_now)
  env -i HOME="$HOME" PATH=/usr/bin:/bin /usr/bin/python3 bin/menu.py run style.bar.toggle >/dev/null 2>&1
  pause 1
  d2=$(hidden_now)
  if [ "$d0" != "$d1" ] && [ "$d0" = "$d2" ]; then
    ok "menu.py run works with no PATH and no USER ($d0 -> $d1 -> $d2)"
  else
    bad "menu.py run under a bare environment: $d0 -> $d1 -> $d2"
  fi
else
  ok "sketchybar absent, dispatch test skipped"
fi

echo "zed theme"
# Every palette must produce a theme whose every key exists in Zed's schema.
# One key (scrollbar_thumb.background) is spelled with an underscore while all
# its siblings use dots; emitting the pattern instead of the schema gives a
# silently default scrollbar, which is invisible until someone looks for it.
zed_bad=$(python3 - <<'PYEOF'
import sys, json, re, glob, os
sys.path.insert(0, "bin")
import zed
schema_path = "script/zed-schema.json"
if not os.path.exists(schema_path):
    print("SKIP no schema copy"); raise SystemExit
schema = json.load(open(schema_path))
defs = schema.get("definitions") or schema.get("$defs") or {}
props = set(defs.get("ThemeStyleContent", {}).get("properties", {}))
def load(path):
    out = {}
    for line in open(path):
        m = re.match(r'\s*([A-Za-z_]+)\s*=\s*"(.*)"\s*$', line)
        if m: out[m.group(1)] = m.group(2)
    return out
bad = []
for path in sorted(glob.glob("themes/*.toml")):
    style = zed.build(load(path))["themes"][0]["style"]
    for key in style:
        if key not in props:
            bad.append(os.path.basename(path) + ":" + key)
print(" ".join(sorted(set(bad))))
PYEOF
)
case "$zed_bad" in
  "")          ok "every palette generates schema-valid Zed keys" ;;
  SKIP*)       ok "zed schema check skipped (no local schema copy)" ;;
  *)           bad "zed keys not in schema: $zed_bad" ;;
esac

echo "icons"
# An icon the font has no glyph for renders as nothing or as a tofu box, and the
# menu looks broken without anything raising an error. Read the cmap and check.
missing=$(python3 -c "
import importlib.util, sys, os
sys.path.insert(0, 'script')
from fontcheck import supported
spec = importlib.util.spec_from_file_location('m','bin/menu.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
font = os.path.expanduser('~/Library/Fonts/HackNerdFont-Regular.ttf')
have = supported(font)
bad = []
for k, v in m.load().items():
    icon = v.get('icon','')
    if not icon:
        bad.append(k + ':empty')
    elif ord(icon[0]) not in have:
        bad.append('%s:U+%04X' % (k, ord(icon[0])))
print(' '.join(bad))")
[ -z "$missing" ] && ok "every icon has a glyph in Hack Nerd Font" || bad "icons without glyphs: $missing"

echo
[ "$fail" -eq 0 ] && echo "all passed" || echo "$fail failed"
exit "$fail"
