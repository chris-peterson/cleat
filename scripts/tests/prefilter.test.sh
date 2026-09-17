#!/usr/bin/env bash
# The prefilter: which payloads reach the CLI at all. The load-bearing assertion
# is the negative one — an ordinary Read must not start a python interpreter,
# because Read is the highest-frequency tool in a session.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# Stand in for the real CLI with a script that records the payload it received,
# so "did python start?" is observable rather than inferred.
fake_root="$(mktemp -d "$TMP/cleat-fake.XXXXXX")"
mkdir -p "$fake_root/scripts"
cat > "$fake_root/scripts/cleat" <<'PY'
import os, sys
open(os.environ["CLEAT_MARKER"], "w").write(sys.stdin.read())
PY
export CLEAT_MARKER="$fake_root/received"

# Sets REACHED (yes/no) and PREFILTER_EXIT for a payload.
run_prefilter() {
  rm -f "$CLEAT_MARKER"
  printf '%s' "$1" | env CLAUDE_PLUGIN_ROOT="$fake_root" bash "$PREFILTER"
  PREFILTER_EXIT=$?
  if [ -f "$CLEAT_MARKER" ]; then REACHED=yes; else REACHED=no; fi
}

echo "== an ordinary Read costs one bash process and nothing else =="
run_prefilter "$(payload PostToolUse Read /repo/src/widget.py)"
check "src/widget.py does not reach the CLI" "$REACHED" "no"
check "and the prefilter still exits 0" "$PREFILTER_EXIT" "0"

run_prefilter '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
check "nor does a Bash payload with no path" "$REACHED" "no"

echo "== every name cleat has an opinion about gets through =="
for name in CLAUDE.md AGENTS.md README.md CONTRIBUTING.md .cursorrules GEMINI.md .windsurfrules; do
  run_prefilter "$(payload PostToolUse Read "/repo/$name")"
  check "$name" "$REACHED" "yes"
done
run_prefilter "$(payload PostToolUse Read /repo/.cursor/rules/style.md)"
check ".cursor/rules/style.md" "$REACHED" "yes"
run_prefilter "$(payload PostToolUse Write /repo/.claude/rules/api-design.md)"
check ".claude/rules/api-design.md" "$REACHED" "yes"
run_prefilter "$(payload PostToolUse Read /repo/.github/copilot-instructions.md)"
check ".github/copilot-instructions.md" "$REACHED" "yes"

echo "== a Write whose content mentions one of them gets through too =="
# The filter deliberately over-admits: the CLI decides, and a real candidate
# filtered out here would fail silently.
run_prefilter "$(payload PreToolUse Write /repo/notes.md "content=see CLAUDE.md")"
check "admitted on content alone" "$REACHED" "yes"

echo "== the payload reaches the CLI intact =="
p="$(payload PostToolUse Read /repo/AGENTS.md)"
run_prefilter "$p"
check "byte-identical" "$(cat "$CLEAT_MARKER")" "$p"

summary "prefilter"
