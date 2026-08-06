#!/usr/bin/env bash
# The PostToolUse repair nudge: what it reports after a write, and the
# per-session suppression that stops a finding the model won't clear from looping.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

run_hook() {
  NUDGE_OUT="$(printf '%s' "$1" | python3 "$CLEAT" hook)"
  NUDGE_EXIT=$?
}

context() {  # the additionalContext in NUDGE_OUT, or "" when silent
  if [ -z "$NUDGE_OUT" ]; then return; fi
  printf '%s' "$NUDGE_OUT" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'
}

BODY='# Widget service\n\nBuild with `just build`; the integration suite needs a live database.\n'

echo "== a write leaving a dangling shape is reported for in-turn repair =="
d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::See [AGENTS.md](./AGENTS.md).\n")"
p="$(payload PostToolUse Write "$d/CLAUDE.md" "content=x")"
run_hook "$p"
c="$(context)"
contains "names the finding" "$c" "no-ref"
contains "carries its repair" "$c" "a markdown link alone does not import it"
contains "states which file is canonical" "$c" "AGENTS.md is canonical"
check "the hook exits 0" "$NUDGE_EXIT" "0"

echo "== an unchanged finding set is not reported twice =="
run_hook "$p"
check "silent" "$NUDGE_OUT" ""

echo "== a write to AGENTS.md is nudged too =="
run_hook "$(payload PostToolUse Write "$d/AGENTS.md" "content=x" "session=other")"
contains "same finding, fresh session" "$(context)" "no-ref"

echo "== once the shape is clean the nudge stops =="
printf '%b' "$POINTER" > "$d/CLAUDE.md"
run_hook "$p"
check "silent" "$NUDGE_OUT" ""

echo "== and a regression is reported again =="
printf '%b' "See [AGENTS.md](./AGENTS.md).\n" > "$d/CLAUDE.md"
run_hook "$p"
contains "reported" "$(context)" "no-ref"

echo "== a changed finding set is reported even within one session =="
printf '%b' "Prefer small commits.\n" > "$d/.cursorrules"
run_hook "$p"
c="$(context)"
contains "the new finding" "$c" "foreign-config"
contains "alongside the old one" "$c" "no-ref"

echo "== writes to other files are none of the nudge's business =="
run_hook "$(payload PostToolUse Write "$d/notes.md" "content=x")"
check "silent" "$NUDGE_OUT" ""

echo "== nor is user-scope memory under ~/.claude =="
fake_home="$(mktemp -d "$TMP/cleat-home.XXXXXX")"
mkdir -p "$fake_home/.claude"
printf '%b' "$BODY" > "$fake_home/.claude/CLAUDE.md"
NUDGE_OUT="$(printf '%s' "$(payload PostToolUse Write "$fake_home/.claude/CLAUDE.md" "content=x")" \
  | env HOME="$fake_home" python3 "$CLEAT" hook)"
check "silent" "$NUDGE_OUT" ""

summary "nudge"
