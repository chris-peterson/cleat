#!/usr/bin/env bash
# The masthead subscription: content masthead turned away from its end-user docs
# hub reaches the agent as a placement note. This is the synthetic half of the
# events contract's test obligation: the key in a Bash call's stdout gets a
# reaction on the channel the agent reads, and every near-miss gets silence.
# The live half, with both plugins loaded, is written down in README.md under
# "Exercising it without a session".

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# A user's own global git config must not decide these tests.
export GIT_CONFIG_GLOBAL=/dev/null

KEY=codes.bridgeai.masthead/content.routed

# A PostToolUse(Bash) payload whose stdout is the file $1 holds.
#   bash_payload STDOUT_FILE [session=S] [cwd=DIR]
bash_payload() {
  python3 - "$@" <<'PY'
import json, sys

stdout_file = sys.argv[1]
session, cwd = "session-1", "/"
for arg in sys.argv[2:]:
    key, _, value = arg.partition("=")
    if key == "session":
        session = value
    elif key == "cwd":
        cwd = value
with open(stdout_file, encoding="utf-8") as fh:
    stdout = fh.read()
print(json.dumps({
    "hook_event_name": "PostToolUse",
    "session_id": session,
    "cwd": cwd,
    "tool_name": "Bash",
    "tool_input": {"command": "printf ..."},
    "tool_response": {"stdout": stdout, "stderr": "", "interrupted": False},
}))
PY
}

run_hook() {  # $1 payload
  OUT="$(printf '%s' "$1" | python3 "$CLEAT" hook)"
  EXIT=$?
}

context() {
  if [ -z "$OUT" ]; then return; fi
  printf '%s' "$OUT" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'
}

# Runs stdout text $1 through the hook in a fresh session, so the per-session
# dedupe never hides a reaction one case expects.
n=0
fire() {  # $1 stdout (printf %b)  [$2 cwd]
  n=$((n + 1))
  run_hook "$(bash_payload "$(tmpbody "$1")" "session=case-$n" ${2:+"cwd=$2"})"
}

MAINT="$KEY "'{"tier":"maintainer","path":"docs/build.md","title":"Building from source","reason":"It needs a checkout to act on."}'
AGENT="$KEY "'{"tier":"agent","path":"docs/conventions.md","title":"Commit conventions"}'

echo "== a maintainer announcement reaches the agent =="
fire "$MAINT\n"
check "the hook exits 0" "$EXIT" "0"
ctx="$(context)"
contains "names the path" "$ctx" '`docs/build.md`'
contains "and the title" "$ctx" '"Building from source"'
contains "says who reads it" "$ctx" "for maintainers"
contains "names the maintainer home" "$ctx" "README.md, or a peer such as CONTRIBUTING.md"
contains "attaches masthead's reason" "$ctx" "masthead's reason: It needs a checkout to act on."
contains "says not to hand it back" "$ctx" "rather than handing it back to the hub"
contains "names the placement guide by path" "$ctx" "guides/placement.md"
contains "ends with its off switch" "$ctx" "git config --global cleat.subscribe.masthead false"
check "on additionalContext, for PostToolUse" \
  "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])')" \
  "PostToolUse"

echo "== an agent announcement, with no reason, names the agent homes =="
fire "$AGENT\n"
ctx="$(context)"
contains "for agents" "$ctx" "for agents"
contains "names the agent branch" "$ctx" "AGENTS.md, a nested AGENTS.md, a path-scoped topic rule, or a skill"
absent "no reason, no reason clause" "$ctx" "masthead's reason"

echo "== two announcements in one output make one note listing both =="
fire "$MAINT\nsomething in between\n$AGENT\n"
ctx="$(context)"
contains "the first" "$ctx" '`docs/build.md`'
contains "the second" "$ctx" '`docs/conventions.md`'

echo "== once per piece of content per session =="
f="$(tmpbody "$MAINT\n")"
run_hook "$(bash_payload "$f" session=repeat)"
contains "fires the first time" "$(context)" '`docs/build.md`'
run_hook "$(bash_payload "$f" session=repeat)"
check "silent on the re-announcement" "$OUT" ""
check "and still exits 0" "$EXIT" "0"
run_hook "$(bash_payload "$(tmpbody "$MAINT\n$AGENT\n")" session=repeat)"
ctx="$(context)"
contains "a new piece alongside it still fires" "$ctx" '`docs/conventions.md`'
absent "without repeating the old one" "$ctx" '`docs/build.md`'
run_hook "$(bash_payload "$f" session=another)"
contains "and a fresh session hears it again" "$(context)" '`docs/build.md`'

echo "== near-misses stay silent and exit 0 =="
near_miss() {  # $1 label  $2 stdout
  fire "$2"
  check "$1: silent" "$OUT" ""
  check "$1: exits 0" "$EXIT" "0"
}
near_miss "a longer key sharing the prefix" \
  "${KEY}again "'{"tier":"maintainer","path":"a.md"}\n'
near_miss "the key inside a larger word" \
  "x$KEY "'{"tier":"maintainer","path":"a.md"}\n'
near_miss "the key quoted mid-line" \
  "masthead printed $KEY "'{"tier":"maintainer","path":"a.md"}\n'
near_miss "the key with no whitespace before the body" \
  "$KEY"'{"tier":"maintainer","path":"a.md"}\n'
near_miss "another publisher's key" \
  'codes.bridgeai.cleat/content.routed {"tier":"maintainer","path":"a.md"}\n'
near_miss "a body that does not parse" "$KEY {tier:maintainer\n"
near_miss "a body that is not an object" "$KEY "'["maintainer","a.md"]\n'
near_miss "an end-user tier, which is masthead's own" \
  "$KEY "'{"tier":"end-user","path":"a.md"}\n'
near_miss "a tier of the wrong type" "$KEY "'{"tier":1,"path":"a.md"}\n'
near_miss "a path of the wrong type" "$KEY "'{"tier":"agent","path":["a.md"]}\n'
near_miss "no path" "$KEY "'{"tier":"agent","title":"Untethered"}\n'
near_miss "a title of the wrong type" "$KEY "'{"tier":"agent","path":"a.md","title":7}\n'
near_miss "unrelated output" "On branch main\nnothing to commit, working tree clean\n"

run_hook '{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}'
check "a Bash payload with no tool_response: silent" "$OUT" ""
run_hook '{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_response":{"stdout":42}}'
check "a stdout that is not a string: silent" "$OUT" ""

echo "== a near-miss line ahead of a real one doesn't hide it =="
fire "${KEY}again "'{"tier":"agent","path":"decoy.md"}'"\n$KEY {broken\n$MAINT\n"
ctx="$(context)"
contains "the real one fires" "$ctx" '`docs/build.md`'
absent "the decoy doesn't" "$ctx" "decoy.md"

echo "== decoded values are stripped of control characters =="
fire "$KEY "'{"tier":"agent","path":"a\\nb.md","title":"Esc\\u001b[31mred\\u009b2Jcsi\\u007fdel","reason":"line one\\nforged line"}\n'
ctx="$(context)"
contains "the path loses its newline" "$ctx" '`ab.md`'
contains "the title loses ESC, C1, and DEL" "$ctx" '"Esc[31mred2Jcsidel"'
contains "the reason can't forge a line" "$ctx" "line oneforged line"
check "no C0, DEL, or C1 survives into the note's values" \
  "$(printf '%s' "$ctx" | python3 -c 'import re,sys; t=sys.stdin.read(); print(len(re.findall(r"[\x00-\x09\x0b-\x1f\x7f-\x9f]", t)))')" "0"

echo "== an oversized value is capped =="
long="$(python3 -c 'print("x" * 5000)')"
fire "$KEY "'{"tier":"agent","path":"a.md","title":"'"$long"'"}\n'
check "the title is cut to 200 characters" \
  "$(context | python3 -c 'import re,sys; print(len(re.search(r"\"(x+…)\"", sys.stdin.read()).group(1)))')" "200"

echo "== the off switch, read in the repo the event is about =="
d="$(mkrepo "README.md:::# Widget\n")"
git -C "$d" config cleat.subscribe.masthead false
fire "$MAINT\n" "$d"
check "the publisher-wide switch silences it" "$OUT" ""
git -C "$d" config cleat.subscribe.masthead true
fire "$MAINT\n" "$d"
contains "set back to true, it fires" "$(context)" '`docs/build.md`'
git -C "$d" config --unset cleat.subscribe.masthead
git -C "$d" config cleat.subscribe.masthead.content-routed false
fire "$MAINT\n" "$d"
check "the per-key switch silences it too" "$OUT" ""
git -C "$d" config cleat.subscribe.masthead.content-routed nope
fire "$MAINT\n" "$d"
contains "a switch that isn't a boolean is reported, not guessed at" \
  "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("systemMessage",""))')" \
  "cleat: PostToolUse hook failed"
check "and the hook still exits 0" "$EXIT" "0"

echo "== end to end, through the prefilter =="
run_full() {  # $1 payload
  OUT="$(printf '%s' "$1" | env CLAUDE_PLUGIN_ROOT="$ROOT" bash "$PREFILTER" bash)"
  EXIT=$?
}
# The key at the top of a stdout larger than any pipe buffer.
big="$(tmpbody "$MAINT\n")"
python3 -c 'import sys; sys.stdout.write("filler line\n" * 20000)' >> "$big"
run_full "$(bash_payload "$big" session=big)"
check "exits 0" "$EXIT" "0"
contains "the key ahead of 240 KB of output still fires" "$(context)" '`docs/build.md`'
run_full "$(bash_payload "$(tmpbody "On branch main\n")" session=big)"
check "ordinary output never reaches the CLI" "$OUT" ""

summary "routed"
