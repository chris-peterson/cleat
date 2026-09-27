#!/usr/bin/env bash
# Topic rules under .claude/rules and the AGENTS.md index over them: which rules
# need a row, which must not have one, and the two ways an index grows past what
# every reader pays for it at launch.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

run_check() {
  CHECK_OUT="$(python3 "$CLEAT" check "$1")"
  CHECK_EXIT=$?
  CHECK_CODES="$(printf '%s' "$CHECK_OUT" | awk '/^[a-z]/ {print $1}' | sort -u | paste -sd, -)"
}

BODY='# Widget service\n\nBuild with `just build`; the suite needs a live database.\n'
SCOPED='---\npaths:\n  - "src/**/*.ts"\n---\n\nValidate every endpoint input.\n'
ALWAYS='Prefer the concrete verb over the abstract noun.\n'
RETIRED='---\npaths:\n  - "__retired__/never-match"\n---\n\nSuperseded.\n'

echo "== a repo with no rules directory is unaffected =="
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER")"
check "no findings" "$CHECK_CODES" ""
check "exits 0" "$CHECK_EXIT" "0"

echo "== an always-on rule needs no row of its own =="
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/prose.md:::$ALWAYS")"
check "no findings" "$CHECK_CODES" ""

echo "== unlisted-rule: a path-scoped rule no row names =="
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/api.md:::$SCOPED" "src/handler.ts:::export {}\n")"
check "code" "$CHECK_CODES" "unlisted-rule"
check "error exits 1" "$CHECK_EXIT" "1"
contains "names the rule" "$CHECK_OUT" ".claude/rules/api.md"

echo "== and is clear once the index names it =="
run_check "$(mkrepo "AGENTS.md:::$BODY\n| \`src/**/*.ts\` | api.md |\n" \
                    "CLAUDE.md:::$POINTER" \
                    ".claude/rules/api.md:::$SCOPED" "src/handler.ts:::export {}\n")"
check "no findings" "$CHECK_CODES" ""

echo "== a nested rule may be named by its basename alone =="
run_check "$(mkrepo "AGENTS.md:::$BODY\n| \`src/**/*.ts\` | api.md |\n" \
                    "CLAUDE.md:::$POINTER" \
                    ".claude/rules/backend/api.md:::$SCOPED" "src/handler.ts:::export {}\n")"
check "no findings" "$CHECK_CODES" ""

echo "== brace expansion decides whether a rule can fire =="
BRACE='---\npaths:\n  - "**/*.{ts,tsx}"\n---\n\nOne component per file.\n'
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/ui.md:::$BRACE" "app/Button.tsx:::export {}\n")"
check "the tsx branch matches, so the rule is live" "$CHECK_CODES" "unlisted-rule"

echo "== an inline paths list is read the same way =="
INLINE='---\npaths: ["docs/**/*.md"]\n---\n\nLead with why.\n'
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/docs.md:::$INLINE" "docs/guide.md:::# guide\n")"
check "code" "$CHECK_CODES" "unlisted-rule"

echo "== dead-rule-listed: the index names a rule that cannot fire =="
run_check "$(mkrepo "AGENTS.md:::$BODY\n| \`__retired__\` | old.md |\n" \
                    "CLAUDE.md:::$POINTER" ".claude/rules/old.md:::$RETIRED")"
check "code" "$CHECK_CODES" "dead-rule-listed"
check "error exits 1" "$CHECK_EXIT" "1"

echo "== a retired rule nobody indexed costs nothing =="
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/old.md:::$RETIRED")"
check "no findings" "$CHECK_CODES" ""

echo "== toc-bloat: the index enumerates the always-on rules =="
run_check "$(mkrepo "AGENTS.md:::$BODY\n- prose.md\n- commits.md\n- naming.md\n" \
                    "CLAUDE.md:::$POINTER" \
                    ".claude/rules/prose.md:::$ALWAYS" \
                    ".claude/rules/commits.md:::$ALWAYS" \
                    ".claude/rules/naming.md:::$ALWAYS" \
                    ".claude/rules/testing.md:::$ALWAYS")"
check "code" "$CHECK_CODES" "toc-bloat"
check "advisory leaves the check green" "$CHECK_EXIT" "0"
contains "marked advisory" "$CHECK_OUT" "(advisory)"

echo "== toc-bloat: the index outgrows what every session pays for it =="
big_repo() {
  local args=("AGENTS.md:::$BODY") i row=""
  for i in $(seq 1 40); do
    args+=(".claude/rules/r$i.md:::$SCOPED")
    row="$row| \`src/**/*.ts\` — the long-form glob list this row carries | r$i.md |\n"
  done
  args[0]="AGENTS.md:::$BODY$row"
  args+=("CLAUDE.md:::$POINTER" "src/handler.ts:::export {}\n")
  mkrepo "${args[@]}"
}
run_check "$(big_repo)"
contains "reported" "$CHECK_OUT" "toc-bloat"
check "still an advisory" "$CHECK_EXIT" "0"
contains "names the byte cost" "$CHECK_OUT" "bytes"
contains "the rendered index would fit, so the repair points at it" "$CHECK_OUT" \
  "index the path-scoped rules and their globs"

echo "== toc-bloat: rules whose smallest index is over budget =="
distinct_repo() {
  local args=("AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER") i
  for i in $(seq -w 1 40); do
    args+=(".claude/rules/module-$i-conventions.md:::---\npaths:\n  - \"src/module-$i/**/*.py\"\n---\n\nKeep handlers thin.\n"
           "src/module-$i/handler.py:::pass\n")
  done
  mkrepo "${args[@]}"
}
DISTINCT="$(distinct_repo)"
printf '%b\n\n%s\n' "$BODY" "$(python3 "$CLEAT" index "$DISTINCT")" > "$DISTINCT/AGENTS.md"
run_check "$DISTINCT"
check "the projector's own index trips it" "$CHECK_CODES" "toc-bloat"
contains "and the repair is to consolidate" "$CHECK_OUT" "consolidate the path-scoped rules"

echo "== a directory symlink cycle cannot stall classification =="
LOOP="$(mkrepo "AGENTS.md:::$BODY\n| \`**/no-such-file.xyz\` | loop.md |\n" "CLAUDE.md:::$POINTER" \
               ".claude/rules/loop.md:::---\npaths:\n  - \"**/no-such-file.xyz\"\n---\n\nNever fires.\n" \
               "src/keep.txt:::x\n")"
ln -s .. "$LOOP/src/a"
ln -s .. "$LOOP/src/b"
# perl's alarm bounds the run, so a regression fails this case instead of
# hanging the suite.
LOOP_OUT="$(perl -e 'alarm shift; exec @ARGV' 10 python3 "$CLEAT" check "$LOOP")"
check "finishes, and the rule is retired" "$(printf '%s' "$LOOP_OUT" | awk '/^[a-z]/ {print $1}')" "dead-rule-listed"

echo "== bad-glob: a glob cleat cannot evaluate =="
bad_rule() { printf -- '---\npaths:\n  - "%s"\n---\n\nRule.\n' "$1"; }
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/wide.md:::$(bad_rule '{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}/*.md')")"
check "past the brace cap" "$CHECK_CODES" "bad-glob"
check "error exits 1" "$CHECK_EXIT" "1"
contains "says how to fix it" "$CHECK_OUT" "fewer brace groups"
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/abs.md:::$(bad_rule '/etc/*')")"
check "an absolute glob" "$CHECK_CODES" "bad-glob"
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/up.md:::$(bad_rule '../**/*.md')")"
check "a glob that climbs out with .." "$CHECK_CODES" "bad-glob"

echo "== globs keep glob's own matching rules =="
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/ci.md:::$(bad_rule '**/*.yml')" ".github/workflows/ci.yml:::on: push\n")"
check "** skips dot-named directories" "$CHECK_CODES" ""
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/ci.md:::$(bad_rule '.github/**/*.yml')" ".github/workflows/ci.yml:::on: push\n")"
check "unless the glob names one" "$CHECK_CODES" "unlisted-rule"
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".claude/rules/docs.md:::$(bad_rule 'docs/*.md')" "docs/deep/guide.md:::# guide\n")"
check "a glob without ** matches only at its own depth" "$CHECK_CODES" ""

echo "== with no AGENTS.md the pointer repair comes first, alone =="
run_check "$(mkrepo "CLAUDE.md:::$BODY" ".claude/rules/api.md:::$SCOPED" \
                    "src/handler.ts:::export {}\n")"
check "no rules findings pile on" "$CHECK_CODES" "no-agents"

echo "== user-scope rules have no AGENTS.md to be indexed from =="
# With HOME pointed at the fixture, its .claude/rules IS ~/.claude/rules, which
# is the shape `cleat check ~` would otherwise report on.
HOME_FIXTURE="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                       ".claude/rules/api.md:::$SCOPED" "src/handler.ts:::export {}\n")"
HOME_OUT="$(HOME="$HOME_FIXTURE" python3 "$CLEAT" check "$HOME_FIXTURE")"
absent "no unlisted-rule under ~/.claude" "$HOME_OUT" "unlisted-rule"
run_check "$HOME_FIXTURE"
check "the same fixture elsewhere does report it" "$CHECK_CODES" "unlisted-rule"

echo "== cleat index renders what the check wants to see =="
IDX_REPO="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                   ".claude/rules/api.md:::$SCOPED" \
                   ".claude/rules/errors.md:::$SCOPED" \
                   ".claude/rules/old.md:::$RETIRED" \
                   ".claude/rules/prose.md:::$ALWAYS" \
                   "src/handler.ts:::export {}\n")"
IDX="$(python3 "$CLEAT" index "$IDX_REPO")"
contains "covers the always-on rules in one line" "$IDX" "without \`paths:\` frontmatter"
absent "and does not name them" "$IDX" "prose.md"
contains "groups rules sharing a glob" "$IDX" "| api.md, errors.md |"
absent "omits the retired rule" "$IDX" "old.md"

echo "== and that output clears the findings it was rendered for =="
printf '%s\n\n%s\n' "$(cat "$IDX_REPO/AGENTS.md")" "$IDX" > "$IDX_REPO/AGENTS.md"
run_check "$IDX_REPO"
check "round trip is clean" "$CHECK_CODES" ""
check "exits 0" "$CHECK_EXIT" "0"

echo "== the projector writes nothing =="
BEFORE="$(cat "$IDX_REPO/AGENTS.md")"
python3 "$CLEAT" index "$IDX_REPO" >/dev/null
check "AGENTS.md untouched" "$(cat "$IDX_REPO/AGENTS.md")" "$BEFORE"

echo "== a repo with no rules has no index to print =="
check "empty" "$(python3 "$CLEAT" index "$(mkrepo "AGENTS.md:::$BODY")")" ""

summary "rules"
