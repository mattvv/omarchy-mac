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
check "style has 4 children" "$(python3 bin/menu.py rows style | wc -l | tr -d ' ')" "4"
check "bar submenu has 1"    "$(python3 bin/menu.py rows style.bar | wc -l | tr -d ' ')" "1"

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

echo
[ "$fail" -eq 0 ] && echo "all passed" || echo "$fail failed"
exit "$fail"
