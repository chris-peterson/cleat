#!/usr/bin/env bash
# `cleat cost`: what a session started in a directory loads at launch, by tier,
# and the budget that `cleat cost` gates on and `cleat check` advises against.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

run_cost() {
  COST_OUT="$(python3 "$CLEAT" cost "$@" 2>&1)"
  COST_EXIT=$?
  # Columns are padded to the longest path; squeezed, a row matches on content.
  COST_OUT="$(printf '%s' "$COST_OUT" | tr -s ' ')"
}

total() {  # $1 dir
  python3 "$CLEAT" cost --json "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["total"])'
}

BODY='# Widget service\n\nBuild with `just build`.\n'

echo "== the pointer and the file it imports both load at launch =="
run_cost "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER")"
contains "CLAUDE.md is a launch row" "$COST_OUT" "CLAUDE.md"
contains "AGENTS.md is imported by it" "$COST_OUT" "AGENTS.md imported by CLAUDE.md"
contains "the total is against the default budget" "$COST_OUT" "of a 16,384-byte budget"
check "under budget exits 0" "$COST_EXIT" "0"

echo "== with no CLAUDE.md, AGENTS.md is read directly =="
run_cost "$(mkrepo "AGENTS.md:::$BODY")"
contains "AGENTS.md is a launch row" "$COST_OUT" "AGENTS.md"
absent "and nothing imports it" "$COST_OUT" "imported by"

echo "== an import inside code, or an address, names nothing =="
d="$(mkrepo "CLAUDE.md:::See \`@extra.md\`, mail a@extra.md.\n\n\`\`\`\n@extra.md\n\`\`\`\n" \
            "extra.md:::should not load\n")"
run_cost "$d"
absent "extra.md is not loaded" "$COST_OUT" "extra.md "

echo "== imports are followed four hops and no further =="
d="$(mkrepo "CLAUDE.md:::@h1.md\n" "h1.md:::@h2.md\n" "h2.md:::@h3.md\n" \
            "h3.md:::@h4.md\n" "h4.md:::@h5.md\n" "h5.md:::too deep\n")"
run_cost "$d"
contains "the fourth hop loads" "$COST_OUT" "h4.md imported by h3.md"
absent "the fifth does not" "$COST_OUT" "h5.md"

echo "== a block-level HTML comment costs nothing =="
plain="$(mkrepo "CLAUDE.md:::Build with just.\n")"
noted="$(mkrepo "CLAUDE.md:::<!-- maintainer note\nspanning lines -->\nBuild with just.\n")"
check "same total with and without the comment" "$(total "$noted")" "$(total "$plain")"

echo "== an always-on rule loads without its frontmatter; a scoped one waits =="
d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
            ".claude/rules/prose.md:::---\nnote: x\n---\nPlain words.\n" \
            ".claude/rules/api.md:::---\npaths:\n  - \"src/**/*.ts\"\n---\nValidate input.\n")"
run_cost "$d"
contains "the always-on rule is a launch row of 13 bytes" "$COST_OUT" "launch 13 .claude/rules/prose.md"
contains "the scoped rule is on demand" "$COST_OUT" "on demand"
contains "with its globs" "$COST_OUT" "paths: src/**/*.ts"

echo "== skills and commands: listed, scoped, typed only, and shadowed =="
d="$(mkrepo "CLAUDE.md:::x\n" \
            ".claude/skills/alpha/SKILL.md:::---\nname: alpha\ndescription: Listed skill.\n---\nBody.\n" \
            ".claude/skills/beta/SKILL.md:::---\nname: beta\ndescription: Scoped.\npaths:\n  - \"src/**\"\n---\nBody.\n" \
            ".claude/skills/gamma/SKILL.md:::---\nname: gamma\ndescription: Typed.\ndisable-model-invocation: true\n---\nBody.\n" \
            ".claude/commands/delta.md:::First line describes it.\n\nMore.\n" \
            ".claude/commands/alpha.md:::A command the skill shadows.\n")"
run_cost "$d"
contains "a plain skill is listed, entry and newline" "$COST_OUT" "listing 23 .claude/skills/alpha/SKILL.md"
contains "a scoped skill waits" "$COST_OUT" "/beta, paths: src/**"
contains "a typed-only skill waits" "$COST_OUT" "/gamma, typed only"
contains "a command lists its first line" "$COST_OUT" "listing 34 .claude/commands/delta.md"
absent "the shadowed command is not counted" "$COST_OUT" ".claude/commands/alpha.md"

echo "== the budget gates the exit code =="
d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER")"
run_cost --budget 10 "$d"
check "--budget past the total exits 1" "$COST_EXIT" "1"
git -C "$d" config cleat.launchBudget 10
run_cost "$d"
check "cleat.launchBudget is read" "$COST_EXIT" "1"
contains "and shown" "$COST_OUT" "of a 10-byte budget"
git -C "$d" config cleat.launchBudget lots
run_cost "$d"
check "a budget that isn't a byte count exits 2" "$COST_EXIT" "2"
contains "naming it" "$COST_OUT" "cleat.launchBudget is 'lots'"

echo "== check: launch-cost is an advisory naming the largest piece and the guide =="
d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER")"
git -C "$d" config cleat.launchBudget 10
out="$(python3 "$CLEAT" check "$d")"
code=$?
contains "reports launch-cost" "$out" "launch-cost"
contains "on the largest piece" "$out" "the largest piece is AGENTS.md"
contains "names the tiering guide" "$out" "guides/tiering.md"
check "an advisory leaves the check green" "$code" "0"

echo "== a missing directory exits 2 =="
run_cost "$TMP/cleat-no-such-dir"
check "exits 2" "$COST_EXIT" "2"

summary "cost"
