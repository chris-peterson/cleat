#!/usr/bin/env bash
# The PreToolUse write gate: what it scopes itself to, the cases it allows
# silently, the deny reason's contents, and the re-issue escape.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# Run a payload through the hook and record stdout + exit in globals.
run_hook() {
  GATE_OUT="$(printf '%s' "$1" | python3 "$CLEAT" hook)"
  GATE_EXIT=$?
}

decision() {  # the permissionDecision in GATE_OUT, or "allow" when silent
  if [ -z "$GATE_OUT" ]; then echo allow; return; fi
  printf '%s' "$GATE_OUT" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])'
}

reason() {
  printf '%s' "$GATE_OUT" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])'
}

BODY='# Widget service\n\nBuild with `just build`; the integration suite needs a live database.\n'
body_file="$(tmpbody "$BODY")"

echo "== a substantive CLAUDE.md with no AGENTS.md sibling is denied =="
d="$(mkrepo "README.md:::# widget\n")"
p="$(payload PreToolUse Write "$d/CLAUDE.md" "content=@$body_file")"
run_hook "$p"
check "denied" "$(decision)" "deny"
check "the hook still exits 0" "$GATE_EXIT" "0"
r="$(reason)"
contains "names the AGENTS.md to write" "$r" "$d/AGENTS.md"
contains "names the CLAUDE.md to write" "$r" "$d/CLAUDE.md"
contains "carries the short-form rubric" "$r" "if Cursor or Codex would act correctly"
contains "names the full rubric's path" "$r" "guides/agents-vs-claude.md"
contains "shows the pointer shape" "$r" "@AGENTS.md"
contains "explains the re-issue escape" "$r" "re-issue the identical write"

echo "== an identical re-issue is allowed, once =="
run_hook "$p"
check "second attempt allowed" "$(decision)" "allow"
run_hook "$p"
check "the record is spent, so a third denies again" "$(decision)" "deny"

echo "== the record is content-specific =="
other="$(tmpbody "$BODY\nAnd one more paragraph of guidance.\n")"
run_hook "$(payload PreToolUse Write "$d/CLAUDE.md" "content=@$other")"
check "different content is not covered" "$(decision)" "deny"

echo "== the record is session-specific =="
d2="$(mkrepo "README.md:::# widget\n")"
p2="$(payload PreToolUse Write "$d2/CLAUDE.md" "content=@$body_file" "session=first")"
run_hook "$p2"
check "denied in the first session" "$(decision)" "deny"
run_hook "$(payload PreToolUse Write "$d2/CLAUDE.md" "content=@$body_file" "session=second")"
check "another session does not inherit the escape" "$(decision)" "deny"

echo "== the allow cases =="
d="$(mkrepo "AGENTS.md:::$BODY")"
run_hook "$(payload PreToolUse Write "$d/CLAUDE.md" "content=@$body_file")"
check "a sibling AGENTS.md allows anything" "$(decision)" "allow"

d="$(mkrepo "README.md:::# widget\n")"
pointer_file="$(tmpbody "$POINTER")"
run_hook "$(payload PreToolUse Write "$d/CLAUDE.md" "content=@$pointer_file")"
check "content already declaring AGENTS.md canonical" "$(decision)" "allow"

run_hook "$(payload PreToolUse Write "$d/CLAUDE.md" "content=")"
check "empty content" "$(decision)" "allow"

run_hook "$(payload PreToolUse Write "$d/CLAUDE.local.md" "content=@$body_file")"
check "CLAUDE.local.md is out of scope" "$(decision)" "allow"

run_hook "$(payload PreToolUse Write "$d/notes.md" "content=@$body_file")"
check "any other filename is out of scope" "$(decision)" "allow"

echo "== user-scope memory under ~/.claude is Claude-specific by nature =="
fake_home="$(mktemp -d "$TMP/cleat-home.XXXXXX")"
mkdir -p "$fake_home/.claude"
GATE_OUT="$(printf '%s' "$(payload PreToolUse Write "$fake_home/.claude/CLAUDE.md" "content=@$body_file")" \
  | env HOME="$fake_home" python3 "$CLEAT" hook)"
check "allowed" "$(decision)" "allow"

echo "== Edit is judged on the file the edit would leave behind =="
d="$(mkrepo "CLAUDE.md:::# Widget\n\nPLACEHOLDER\n")"
rm "$d/CLAUDE.md"; printf '%b' "# Widget\n\nPLACEHOLDER\n" > "$d/CLAUDE.md"
run_hook "$(payload PreToolUse Edit "$d/CLAUDE.md" \
  "old_string=PLACEHOLDER" "new_string=Build with just build; tests need a live database.")"
check "an edit leaving substantive content is denied" "$(decision)" "deny"
run_hook "$(payload PreToolUse Edit "$d/CLAUDE.md" \
  "old_string=PLACEHOLDER" "new_string=@AGENTS.md")"
check "an edit that inserts the ref is allowed" "$(decision)" "allow"

echo "== an Edit against a file that isn't there yet can't be judged =="
d="$(mkrepo "README.md:::# widget\n")"
run_hook "$(payload PreToolUse Edit "$d/CLAUDE.md" "old_string=a" "new_string=b")"
check "allowed rather than guessed at" "$(decision)" "allow"

echo "== an unparseable payload is surfaced, not swallowed =="
GATE_OUT="$(printf 'not json' | python3 "$CLEAT" hook)"
GATE_EXIT=$?
check "exits 0" "$GATE_EXIT" "0"
contains "says so in a systemMessage" "$GATE_OUT" "unparseable hook payload"

summary "gate"
