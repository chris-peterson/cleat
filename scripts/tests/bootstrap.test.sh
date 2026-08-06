#!/usr/bin/env bash
# The PostToolUse Read triggers: the three moments a repo without the convention
# gets offered one, and the once-per-session-per-directory budget that keeps them
# from becoming chatter.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

run_hook() {
  BOOT_OUT="$(printf '%s' "$1" | python3 "$CLEAT" hook)"
  BOOT_EXIT=$?
}

field() {  # $1 a python expression over the parsed payload, bound to `d`
  if [ -z "$BOOT_OUT" ]; then return; fi
  printf '%s' "$BOOT_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"
}

sysmsg() { field 'd.get("systemMessage","")'; }
context() { field 'd["hookSpecificOutput"]["additionalContext"]'; }

BODY='# Widget service\n\nBuild with `just build`; the integration suite needs a live database.\n'

echo "== reading AGENTS.md where nothing imports it =="
d="$(mkrepo "AGENTS.md:::$BODY")"
p="$(payload PostToolUse Read "$d/AGENTS.md")"
run_hook "$p"
check "the hook exits 0" "$BOOT_EXIT" "0"
contains "the user sees it" "$(sysmsg)" "Claude Code loads CLAUDE.md"
contains "the model gets the action" "$(context)" "Offer to add CLAUDE.md"
contains "and the rubric's path" "$(context)" "guides/agents-vs-claude.md"

echo "== and only once per session per directory =="
run_hook "$p"
check "silent the second time" "$BOOT_OUT" ""
run_hook "$(payload PostToolUse Read "$d/AGENTS.md" "session=elsewhere")"
contains "but a fresh session gets it" "$(sysmsg)" "Claude Code loads CLAUDE.md"

echo "== a CLAUDE.md that only links, without the ref, still counts as unlinked =="
d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::See [AGENTS.md](./AGENTS.md).\n")"
run_hook "$(payload PostToolUse Read "$d/AGENTS.md")"
contains "reported" "$(sysmsg)" "never reaches a session at startup"

echo "== once the pointer is in place, reading AGENTS.md is unremarkable =="
d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER")"
run_hook "$(payload PostToolUse Read "$d/AGENTS.md")"
check "silent" "$BOOT_OUT" ""

echo "== reading a repo root's README where neither file exists =="
d="$(mkrepo "README.md:::# widget\n")"
run_hook "$(payload PostToolUse Read "$d/README.md")"
contains "the user sees it" "$(sysmsg)" "neither AGENTS.md nor CLAUDE.md"
contains "the model gets the action" "$(context)" "Offer to write AGENTS.md"

echo "== CONTRIBUTING.md is the same moment =="
d="$(mkrepo "CONTRIBUTING.md:::# contributing\n")"
run_hook "$(payload PostToolUse Read "$d/CONTRIBUTING.md")"
contains "reported" "$(sysmsg)" "neither AGENTS.md nor CLAUDE.md"

echo "== a README in a subdirectory is not the repo's front door =="
d="$(mkrepo "README.md:::# widget\n" "packages/api/README.md:::# api\n")"
run_hook "$(payload PostToolUse Read "$d/packages/api/README.md")"
check "silent" "$BOOT_OUT" ""

echo "== nor is a README outside a repo at all =="
loose="$(mktemp -d "$TMP/cleat-loose.XXXXXX")"
printf '%b' "# notes\n" > "$loose/README.md"
run_hook "$(payload PostToolUse Read "$loose/README.md")"
check "silent" "$BOOT_OUT" ""

echo "== a repo that already has guidance needs no offer =="
d="$(mkrepo "README.md:::# widget\n" "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER")"
run_hook "$(payload PostToolUse Read "$d/README.md")"
check "silent" "$BOOT_OUT" ""

echo "== reading a rival tool's config =="
d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" ".cursorrules:::Prefer small commits.\n")"
run_hook "$(payload PostToolUse Read "$d/.cursorrules")"
contains "names the file" "$(sysmsg)" ".cursorrules"
contains "the model gets the action" "$(context)" "Offer to consolidate it into AGENTS.md"

run_hook "$(payload PostToolUse Read "$d/.cursor/rules/style.md")"
contains "a file inside .cursor/rules counts" "$(sysmsg)" ".cursor/rules"

run_hook "$(payload PostToolUse Read "$d/GEMINI.md" "session=g")"
contains "GEMINI.md counts" "$(sysmsg)" "GEMINI.md"

echo "== an ordinary source file is not a trigger =="
run_hook "$(payload PostToolUse Read "$d/src/widget.py")"
check "silent" "$BOOT_OUT" ""

summary "bootstrap"
