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
absent "without repeating the one already reported" "$c" "no-ref"

echo "== a finding that clears is forgotten, so its return is reported =="
rm "$d/.cursorrules"
run_hook "$p"
check "silent while only the reported finding remains" "$NUDGE_OUT" ""
printf '%b' "Prefer small commits.\n" > "$d/.cursorrules"
run_hook "$p"
contains "the returning finding" "$(context)" "foreign-config"

SETUP='Download the widget CLI from the project releases page.\nRun `widget init` in the project root to write the config.\nThen `widget serve` starts the development server on port 8080.\n'

echo "== a write to the documentation reports what it copied =="
dd="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" "docs/start.md:::# Start\n\n$SETUP")"
printf '%b' "# widget\n\n$SETUP" > "$dd/README.md"
run_hook "$(payload PostToolUse Write "$dd/README.md" "content=x")"
c="$(context)"
contains "restated, in the turn that made it" "$c" "restated"

echo "== the edit touched one of the copies, so it is fixed in the same change =="
contains "says to fix it now" "$c" "your edit touched README.md, so fix this in the same change"
absent "and not to defer it" "$c" "wrap-up"

echo "== a forge-rendered README is cut down and linked, not included =="
contains "names the cut" "$c" "cut README.md to what a repo reader needs"
contains "links to the docs page" "$c" "link to docs/start.md for the rest"
absent "and offers no include" "$c" "include"

echo "== a README finding carries no AGENTS.md footer =="
absent "footer omitted" "$c" "AGENTS.md is canonical"

echo "== the edit touched neither copy, so it is named, not fixed =="
printf '%b' "# Contributing\n\nOpen a pull request.\n" > "$dd/CONTRIBUTING.md"
run_hook "$(payload PostToolUse Write "$dd/CONTRIBUTING.md" "content=x" "session=bystander")"
c="$(context)"
contains "still reported" "$c" "restated"
contains "says to name it to the user" "$c" "name it to the user in your wrap-up"
absent "and not to fix it here" "$c" "fix this in the same change"

echo "== and a wrong-way link =="
printf '%b' "See [AGENTS.md](../AGENTS.md).\n" > "$dd/docs/links.md"
run_hook "$(payload PostToolUse Write "$dd/docs/links.md" "content=x")"
contains "narrowing-ref" "$(context)" "narrowing-ref"

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

echo "== an index finding hands over the rows rather than describing them =="
SCOPED='---\npaths:\n  - "src/**/*.ts"\n---\n\nValidate every endpoint input.\n'
d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
            ".claude/rules/api.md:::$SCOPED" "src/handler.ts:::export {}\n")"
run_hook "$(payload PostToolUse Write "$d/.claude/rules/api.md" "content=x")"
c="$(context)"
contains "names the finding" "$c" "unlisted-rule"
contains "carries the rendered index" "$c" "| \`src/**/*.ts\` | api.md |"
contains "and says what to do with it" "$c" "replace the rows that name rules"

echo "== toc-bloat hands over the rows too =="
ALWAYS='Prefer the concrete verb over the abstract noun.\n'
d="$(mkrepo "AGENTS.md:::$BODY\n- prose.md\n- commits.md\n- naming.md\n" "CLAUDE.md:::$POINTER" \
            ".claude/rules/prose.md:::$ALWAYS" ".claude/rules/commits.md:::$ALWAYS" \
            ".claude/rules/naming.md:::$ALWAYS" ".claude/rules/testing.md:::$ALWAYS")"
run_hook "$(payload PostToolUse Write "$d/AGENTS.md" "content=x")"
c="$(context)"
contains "names the finding" "$c" "toc-bloat"
contains "carries the one line that replaces them" "$c" "without \`paths:\` frontmatter"

echo "== but not rows that would still be over budget =="
args=("AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER")
for i in $(seq -w 1 40); do
  args+=(".claude/rules/module-$i-conventions.md:::---\npaths:\n  - \"src/module-$i/**/*.py\"\n---\n\nKeep handlers thin.\n"
         "src/module-$i/handler.py:::pass\n")
done
d="$(mkrepo "${args[@]}")"
printf '%b\n\n%s\n' "$BODY" "$(python3 "$CLEAT" index "$d")" > "$d/AGENTS.md"
run_hook "$(payload PostToolUse Write "$d/AGENTS.md" "content=x")"
c="$(context)"
contains "names the finding" "$c" "consolidate the path-scoped rules"
absent "and appends no index" "$c" "The index AGENTS.md should carry"

echo "== a pointer written before its AGENTS.md is reported as dangling =="
d="$(mkrepo "README.md:::# widget\n" "CLAUDE.md:::$POINTER")"
run_hook "$(payload PostToolUse Write "$d/CLAUDE.md" "content=x")"
contains "names the finding" "$(context)" "dangling-ref"

echo "== a finding with no index component carries no rows =="
d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::See [AGENTS.md](./AGENTS.md).\n")"
run_hook "$(payload PostToolUse Write "$d/CLAUDE.md" "content=x")"
absent "no index appended" "$(context)" "Applies to"

summary "nudge"
