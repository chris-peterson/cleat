#!/usr/bin/env bash
# `cleat check`: one case per finding code, the severity split that drives the
# exit code, the two duplication tiers, and the ten-repo grading table from the
# founding issue reproduced as fixtures (so the assertion doesn't depend on which
# repos happen to be checked out next to this one).

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# Sets CHECK_OUT, CHECK_EXIT, and CHECK_CODES for a fixture directory. Not a
# command substitution, so the exit code survives.
run_check() {
  CHECK_OUT="$(python3 "$CLEAT" check "$1")"
  CHECK_EXIT=$?
  CHECK_CODES="$(printf '%s' "$CHECK_OUT" | awk '/^[a-z]/ {print $1}' | sort -u | paste -sd, -)"
}

BODY='# Widget service\n\nBuild with `just build`; the integration suite needs a live database.\n'
STUB='# AGENTS.md\n\nProject guidance lives in [CLAUDE.md](./CLAUDE.md).\n'

echo "== unguided: neither file =="
run_check "$(mkrepo "README.md:::# widget\n")"
check "code" "$CHECK_CODES" "unguided"
check "advisory leaves the check green" "$CHECK_EXIT" "0"
contains "marked advisory" "$CHECK_OUT" "(advisory)"

echo "== no-agents: CLAUDE.md carries the guidance =="
run_check "$(mkrepo "CLAUDE.md:::$BODY")"
check "code" "$CHECK_CODES" "no-agents"
check "error exits 1" "$CHECK_EXIT" "1"

echo "== no-claude: AGENTS.md with nothing Claude Code reads =="
run_check "$(mkrepo "AGENTS.md:::$BODY")"
check "code" "$CHECK_CODES" "no-claude"
check "error exits 1" "$CHECK_EXIT" "1"

echo "== a blank CLAUDE.md loads nothing, so it counts as absent =="
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::\n \n")"
check "code" "$CHECK_CODES" "no-claude"

echo "== no-ref: both files, but nothing imports AGENTS.md =="
run_check "$(mkrepo "AGENTS.md:::$BODY" \
                    "CLAUDE.md:::See [AGENTS.md](./AGENTS.md) for the details.\n")"
check "a markdown link is not an import" "$CHECK_CODES" "no-ref"
check "error exits 1" "$CHECK_EXIT" "1"

echo "== the target shape is clean =="
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER")"
check "no findings" "$CHECK_CODES" ""
check "exits 0" "$CHECK_EXIT" "0"
check "and prints nothing" "$CHECK_OUT" ""

echo "== the pointer tolerates a Claude-specific remainder =="
run_check "$(mkrepo "AGENTS.md:::$BODY" \
  "CLAUDE.md:::$POINTER\n## Claude Code\n\n- \`/deploy\` needs AWS_PROFILE set.\n")"
check "no findings" "$CHECK_CODES" ""

echo "== inverted: AGENTS.md is a stub pointing back =="
run_check "$(mkrepo "AGENTS.md:::$STUB" "CLAUDE.md:::$BODY")"
check "code" "$CHECK_CODES" "inverted"
check "error exits 1" "$CHECK_EXIT" "1"
absent "no-ref is not also reported — one repair covers both" "$CHECK_OUT" "no-ref"

echo "== inverted: an explicit @CLAUDE.md import, whatever the length =="
long='# AGENTS.md\n\n@CLAUDE.md\n'
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  long="$long\nParagraph $i of a file long enough not to read as a stub.\n"
done
run_check "$(mkrepo "AGENTS.md:::$long" "CLAUDE.md:::$BODY")"
contains "code" "$CHECK_CODES" "inverted"

echo "== a long AGENTS.md that merely mentions CLAUDE.md is not inverted =="
mentions='# Widget\n\nClaude-specific notes stay in CLAUDE.md, below the ref.\n'
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  mentions="$mentions\nParagraph $i, well past the stub threshold, with real content.\n"
done
run_check "$(mkrepo "AGENTS.md:::$mentions" "CLAUDE.md:::$POINTER")"
check "no findings" "$CHECK_CODES" ""

echo "== duplicated: a shared line of guidance is the substantive tier =="
shared='Every request carries the tenant id in the X-Tenant header.'
run_check "$(mkrepo "AGENTS.md:::$BODY\n$shared\n" "CLAUDE.md:::$POINTER\n$shared\n")"
check "code" "$CHECK_CODES" "duplicated"
check "error exits 1" "$CHECK_EXIT" "1"
contains "repair points at CLAUDE.md" "$CHECK_OUT" "delete them from CLAUDE.md"

echo "== duplicated: a shared heading alone is advisory =="
run_check "$(mkrepo \
  "AGENTS.md:::$BODY\n## Commands\n\nRun the unit suite before pushing anything.\n" \
  "CLAUDE.md:::$POINTER\n## Commands\n\nThe /verify command wraps it.\n")"
check "code" "$CHECK_CODES" "duplicated"
check "advisory leaves the check green" "$CHECK_EXIT" "0"
contains "marked advisory" "$CHECK_OUT" "(advisory)"

echo "== a short shared line is boilerplate, not duplication =="
run_check "$(mkrepo "AGENTS.md:::$BODY\nSee SPEC.md.\n" "CLAUDE.md:::$POINTER\nSee SPEC.md.\n")"
check "no findings" "$CHECK_CODES" ""

echo "== foreign-config =="
run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".cursorrules:::Prefer small commits.\n")"
check "a rival tool's config is an error" "$CHECK_CODES" "foreign-config"
check "exits 1" "$CHECK_EXIT" "1"

run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".cursor/rules/style.md:::Prefer small commits.\n")"
check ".cursor/rules is scanned as a directory" "$CHECK_CODES" "foreign-config"

d="$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER")"
mkdir -p "$d/.cursor/rules"
run_check "$d"
check "an empty .cursor/rules holds no guidance" "$CHECK_CODES" ""

run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" \
                    ".github/copilot-instructions.md:::Prefer small commits.\n")"
check "copilot-instructions.md" "$CHECK_CODES" "foreign-config"

run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" "GEMINI.md:::Prefer small commits.\n")"
check "GEMINI.md" "$CHECK_CODES" "foreign-config"

run_check "$(mkrepo "AGENTS.md:::$BODY" "CLAUDE.md:::$POINTER" ".windsurfrules:::Prefer small commits.\n")"
check ".windsurfrules" "$CHECK_CODES" "foreign-config"

echo "== --json =="
d="$(mkrepo "CLAUDE.md:::$BODY")"
json="$(python3 "$CLEAT" check "$d" --json)"
check "parses, and carries code/severity/repair" \
  "$(printf '%s' "$json" | python3 -c 'import json,sys; f=json.load(sys.stdin)["findings"][0]; print(f["code"], f["severity"], bool(f["repair"]))')" \
  "no-agents error True"
python3 "$CLEAT" check "$d" --json >/dev/null
check "--json keeps the same exit code" "$?" "1"

echo "== a missing directory is a usage error, not a finding =="
python3 "$CLEAT" check "$d/nope" >/dev/null 2>&1
check "exits 2" "$?" "2"

echo "== the founding issue's grading table, as fixtures =="
big="$BODY"
for i in 1 2 3 4 5 6 7 8 9 10; do
  big="$big\nSection $i covering a real part of the system.\n"
done

run_check "$(mkrepo "AGENTS.md:::$big" "CLAUDE.md:::$POINTER")"
check "A — docs hub: pointer plus canonical AGENTS.md" "$CHECK_CODES" ""
run_check "$(mkrepo "AGENTS.md:::$big" \
                    "CLAUDE.md:::$POINTER\n## Claude Code\n\nHooks live in hooks/.\n")"
check "A — pointer plus Claude-only extras below the ref" "$CHECK_CODES" ""
run_check "$(mkrepo "AGENTS.md:::$STUB" "CLAUDE.md:::$big")"
check "D — inverted" "$CHECK_CODES" "inverted"
run_check "$(mkrepo "AGENTS.md:::$big")"
check "C — AGENTS.md Claude Code never loads" "$CHECK_CODES" "no-claude"
run_check "$(mkrepo "README.md:::# widget\n")"
check "F — neither file" "$CHECK_CODES" "unguided"

summary "check"
