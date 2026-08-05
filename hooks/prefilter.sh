#!/usr/bin/env bash
# The prefilter in front of every cleat hook registration.
#
# Read is the highest-frequency tool in a session, and Write/Edit are not far
# behind, so the registrations point here instead of straight at the python CLI.
# This reads the payload, tests it against a fixed set of substrings, and exits
# without starting an interpreter unless the payload names a file cleat has an
# opinion about. No jq, no python, no JSON parsing on the common path.
#
# Matching the raw payload deliberately over-admits: a source file whose content
# merely mentions CLAUDE.md gets through, and `cleat hook` decides. The reverse
# error — a real candidate filtered out here — would be silent.

set -u

# Names cleat acts on: the two instruction files, the two files a repo with no
# guidance is likely read from first, and the foreign single-tool configs.
needles=(
  CLAUDE.md
  AGENTS.md
  README.md
  CONTRIBUTING.md
  .cursorrules
  .cursor/rules
  copilot-instructions.md
  .windsurfrules
  GEMINI.md
)

payload="$(cat)"

for needle in "${needles[@]}"; do
  case "$payload" in
    *"$needle"*)
      printf '%s' "$payload" | python3 "${CLAUDE_PLUGIN_ROOT}/scripts/cleat" hook
      exit 0
      ;;
  esac
done

exit 0
