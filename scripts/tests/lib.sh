# Shared harness for cleat's test suites. Sourced, not run — `just test` globs
# *.test.sh, so this file is never executed on its own.
#
# Every suite is hermetic: fixtures are throwaway repos under $TMPDIR, and
# CLAUDE_PLUGIN_DATA points at a throwaway state dir so a test run never touches
# the real ~/.claude/plugins/data.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLEAT="$ROOT/scripts/cleat"
PREFILTER="$ROOT/hooks/prefilter.sh"

# Trailing slash stripped: pathlib collapses `//` in the paths it echoes back, so
# a fixture path built with one would never match the CLI's own rendering of it.
TMP="${TMPDIR:-/tmp}"
TMP="${TMP%/}"

CLAUDE_PLUGIN_DATA="$(mktemp -d "$TMP/cleat-state.XXXXXX")"
export CLAUDE_PLUGIN_DATA

pass=0
fail=0

check() {  # $1 label  $2 actual  $3 expected
  if [ "$2" = "$3" ]; then
    echo "  ok: $1"; pass=$((pass + 1))
  else
    echo "  FAIL: $1"; echo "        got:  $2"; echo "        want: $3"; fail=$((fail + 1))
  fi
}

contains() {  # $1 label  $2 haystack  $3 needle
  case "$2" in
    *"$3"*) echo "  ok: $1"; pass=$((pass + 1)) ;;
    *) echo "  FAIL: $1 (no '$3' in output)"; fail=$((fail + 1)) ;;
  esac
}

absent() {  # $1 label  $2 haystack  $3 needle
  case "$2" in
    *"$3"*) echo "  FAIL: $1 (unexpected '$3' in output)"; fail=$((fail + 1)) ;;
    *) echo "  ok: $1"; pass=$((pass + 1)) ;;
  esac
}

summary() {  # $1 suite name
  echo
  echo "$1: pass=$pass fail=$fail"
  [ "$fail" = 0 ]
}

# A throwaway git repo. Each argument is `relpath:::content`; `%b` expands \n so
# multi-line fixtures stay on one line here. Prints the repo path.
mkrepo() {
  local dir spec rel body
  dir="$(mktemp -d "$TMP/cleat-repo.XXXXXX")"
  git -C "$dir" init -q >/dev/null 2>&1
  for spec in "$@"; do
    rel="${spec%%:::*}"
    body="${spec#*:::}"
    mkdir -p "$dir/$(dirname "$rel")"
    printf '%b' "$body" > "$dir/$rel"
  done
  echo "$dir"
}

# The pointer shape, as a `printf %b` string.
POINTER='Agent instructions live in [AGENTS.md](./AGENTS.md).\n\n@AGENTS.md\n'

# A hook payload on stdout, built by python so no test has to hand-escape JSON.
#   payload EVENT TOOL FILE_PATH [session=S] [content=@FILE] [content=TEXT]
#                                [old_string=..] [new_string=..] [replace_all=true]
# `key=@path` reads the value from a file, which keeps multi-line content out of
# shell quoting entirely.
payload() {
  python3 - "$@" <<'PY'
import json, sys

event, tool, path = sys.argv[1:4]
session = "session-1"
tool_input = {"file_path": path}
for arg in sys.argv[4:]:
    key, _, value = arg.partition("=")
    if value.startswith("@"):
        with open(value[1:], encoding="utf-8") as fh:
            value = fh.read()
    if key == "session":
        session = value
    elif key == "replace_all":
        tool_input[key] = value == "true"
    else:
        tool_input[key] = value
print(json.dumps({
    "hook_event_name": event,
    "session_id": session,
    "tool_name": tool,
    "tool_input": tool_input,
}))
PY
}

# A file holding $1, so `content=@...` can carry multi-line bodies.
tmpbody() {
  local f
  f="$(mktemp "$TMP/cleat-body.XXXXXX")"
  printf '%b' "$1" > "$f"
  echo "$f"
}
