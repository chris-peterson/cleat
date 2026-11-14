#!/usr/bin/env bash
# `cleat graph --probe TERM --deep`: past what a session loads, the repo's other
# files and commits, then the transcripts agentsview keeps, in the JSON, the
# terminal browser, and the page `--serve` answers for.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

USER_DIR="$(mktemp -d "$TMP/cleat-user.XXXXXX")"
export CLAUDE_CONFIG_DIR="$USER_DIR"
export XDG_CACHE_HOME="$(mktemp -d "$TMP/cleat-cache.XXXXXX")"

REPO="$(mkrepo "CLAUDE.md:::$POINTER" \
  "AGENTS.md:::# Widget\n\nThe [design notes](docs/design.md) are here.\n" \
  "docs/design.md:::Design notes. The rollout is staged.\n" \
  "docs/notes/rollout.md:::# Rollout plan\n\nOne.\nTwo.\nThe widget rollout plan goes region by region.\nSee docs/notes/regions.md and https://example.com/rollout for the dashboard.\nThree.\n" \
  "docs/notes/regions.md:::Regions, in order.\n" \
  "docs/notes/later.md:::A rollout, one day.\n" \
  "src/app.ts:::export {}\n")"
printf 'rollout\0plan\n' > "$REPO/blob.bin"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q -m "Start the widget"
git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty \
  -m "Stage the rollout plan by region" -m "The plan lives in docs/notes/rollout.md."
SHA="$(git -C "$REPO" rev-parse HEAD)"

OUT="$(mktemp "$TMP/cleat-deep.XXXXXX")"
deep_json() {  # args to cleat graph; JSON lands in $OUT
  python3 "$CLEAT" graph --json "$@" > "$OUT"
  DEEP_EXIT=$?
}
q() {  # q EXPR: EXPR with `d` the deep probe and `hits(ring)` its hits by label
  python3 - "$OUT" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["probe"]["deep"]
def ring(n):
    return next(r for r in d["rings"] if r["ring"] == n)
def hits(n):
    return {h["label"]: h for h in ring(n)["hits"]}
print(eval(sys.argv[2]))
PY
}

echo "== --deep needs a term and a git repo =="
out="$(python3 "$CLEAT" graph "$REPO" --json --probe --deep 2>&1)"
check "with no term it exits 2" "$?" "2"
contains "and says it needs one" "$out" "--deep needs a probe term"
PLAIN="$(mktemp -d "$TMP/cleat-plain.XXXXXX")"
printf '@AGENTS.md\n' > "$PLAIN/CLAUDE.md"
printf '# Plain\n' > "$PLAIN/AGENTS.md"
out="$(python3 "$CLEAT" graph "$PLAIN" --json --probe rollout --deep 2>&1)"
check "outside a git repo it exits 2" "$?" "2"
contains "and says ring 1 is a repo's files" "$out" "is not in a git repo"

echo "== ring 1: the repo's other files and its commits =="
deep_json "$REPO" --probe "rollout plan" --deep
check "exits 0" "$DEEP_EXIT" "0"
check "the tracked text files no node holds, and the commits saying the term" \
  "$(q 'sorted(hits(1))')" "['$(git -C "$REPO" rev-parse --short HEAD) Stage the rollout plan by region', 'docs/notes/later.md', 'docs/notes/rollout.md']"
check "a file a node holds is not a deep hit" "$(q '"docs/design.md" in hits(1)')" "False"
check "nor is a file that isn't text" "$(q '"blob.bin" in hits(1)')" "False"
check "most of the prompt's words first, files before commits" \
  "$(q '[h["label"] for h in ring(1)["hits"]][0]')" "docs/notes/rollout.md"
check "a file hit carries its matching lines, a web address's words not among them" \
  "$(q '[l["line"] for l in hits(1)["docs/notes/rollout.md"]["lines"]]')" "[1, 5]"
check "a commit hit its sha, date, and subject" \
  "$(q 'next((h["target"], len(h["date"]), h["subject"]) for h in ring(1)["hits"] if h["kind"] == "commit")')" \
  "('$SHA', 10, 'Stage the rollout plan by region')"
check "its context is the lines around each match" \
  "$(q '[l["line"] for l in hits(1)["docs/notes/rollout.md"]["context"]["lines"]]')" "[1, 2, 3, 4, 5, 6, 7]"
check "and the hops those lines name" \
  "$(q '[(h["kind"], h["target"]) for h in hits(1)["docs/notes/rollout.md"]["context"]["hops"]]')" \
  "[('url', 'https://example.com/rollout'), ('file', 'docs/notes/regions.md')]"
check "a commit's hops are the files it names" \
  "$(q 'next([(h["kind"], h["target"]) for h in h["context"]["hops"]] for h in ring(1)["hits"] if h["kind"] == "commit")')" \
  "[('file', 'docs/notes/rollout.md')]"
check "with nothing lit, the fix is the repo's own instruction file, AGENTS.md behind the pointer" \
  "$(q 'd["fix"]["label"]')" "AGENTS.md"
contains "each hit says where to name it" "$(q 'hits(1)["docs/notes/later.md"]["advice"]')" \
  "Name docs/notes/later.md in AGENTS.md"
contains "the summary counts each ring's hits and what reading them costs" "$(q 'd["summary"]')" "Ring 1: 3 hits, ~"

echo "== rings 2 and 3: the transcripts agentsview keeps =="
BIN="$(mktemp -d "$TMP/cleat-bin.XXXXXX")"
CALLS="$BIN/calls"
S1="11111111-1111-4111-8111-111111111111"
S2="22222222-2222-4222-8222-222222222222"
cat > "$BIN/agentsview" <<PY
#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
open("$CALLS", "a").write(json.dumps(args) + "\n")
if os.environ.get("AGENTSVIEW_FAIL"):
    sys.stderr.write("fatal: database data version 167 is newer than this binary's\n")
    sys.exit(1)
def match(session, project, ordinal, snippet, **extra):
    m = dict(session_id=session, project=project, ordinal=ordinal, snippet=snippet,
             timestamp="2026-11-0{}T10:00:00Z".format(ordinal), role="user", location="message")
    m.update(extra)
    return m
if args[:2] == ["session", "list"]:
    out = {"sessions": [{"id": "$S1", "project": "widget", "cwd": "$REPO"},
                        {"id": "$S2", "project": "elsewhere", "cwd": "/somewhere/else"}]}
elif args[:2] == ["session", "search"] and "--regex" in args:
    out = {"matches": [match("$S1", "widget", 4, "Published https://claude.ai/artifact/abc-123 for you", tool_name="Artifact", location="tool_result")]}
elif args[:2] == ["session", "search"]:
    here = [match("$S1", "widget", 2, "Where did the rollout plan land? It was in the dashboard.")]
    there = [match("$S2", "elsewhere", 3, "A rollout plan for the other team")]
    out = {"matches": here if "--project" in args else here + there}
elif args[:2] == ["session", "tool-calls"]:
    out = {"tool_calls": [{"tool_name": "Artifact", "ordinal": 3, "input_json": json.dumps(
        {"title": "Rollout plan", "description": "The widget rollout, by region.", "file_path": "/x/rollout.html"})}]}
elif args[:2] == ["session", "messages"]:
    out = {"messages": [{"ordinal": 2, "role": "user", "timestamp": "2026-11-02T10:00:00Z",
                         "content": "Where did the rollout plan land? See docs/notes/rollout.md"}]}
elif args[:2] == ["session", "get"]:
    out = {"id": args[2], "project": "widget", "cwd": "$REPO", "display_name": "Plan the rollout"}
else:
    sys.stderr.write("unexpected: {}\n".format(args)); sys.exit(3)
print(json.dumps(out))
PY
chmod +x "$BIN/agentsview"
PATH="$BIN:$PATH" deep_json "$REPO" --probe "rollout plan" --deep 3
check "exits 0" "$DEEP_EXIT" "0"
check "ring 2 holds the sessions run in this directory, artifacts first" \
  "$(q '[(h["kind"], h["session"]) for h in ring(2)["hits"]]')" "[('artifact', '$S1'), ('transcript', '$S1')]"
check "an artifact carries its address and the title its publish gave" \
  "$(q 'next((h["target"], h["title"]) for h in ring(2)["hits"] if h["kind"] == "artifact")')" \
  "('https://claude.ai/artifact/abc-123', 'Rollout plan')"
check "ring 3 holds every other project's, less ring 2's" \
  "$(q '[(h["kind"], h["project"]) for h in ring(3)["hits"]]')" "[('transcript', 'elsewhere')]"
check "a transcript hit's context is the messages around it" \
  "$(q 'next(h["context"]["lines"][1]["text"] for h in ring(2)["hits"] if h["kind"] == "transcript")')" \
  "Where did the rollout plan land? See docs/notes/rollout.md"
check "and its hops include the files they name and the session" \
  "$(q 'next([(x["kind"], x["target"]) for x in h["context"]["hops"]] for h in ring(2)["hits"] if h["kind"] == "transcript")')" \
  "[('file', 'docs/notes/rollout.md'), ('session', '$S1')]"
contains "ring 2 searched agentsview by project" "$(cat "$CALLS")" '"--project", "widget"'
contains "a prompt searches by meaning and words together" "$(cat "$CALLS")" '"--hybrid"'
absent "and never with secrets revealed" "$(cat "$CALLS")" "--reveal"
: > "$CALLS"
PATH="$BIN:$PATH" deep_json "$REPO" --probe '"rollout plan"' --deep 2
contains "a quoted term searches as typed, across messages and tool calls" "$(cat "$CALLS")" \
  '"rollout plan", "--limit", "50", "--context", "1", "--exclude-system", "--in", "messages,tool_input,tool_result"'

echo "== when agentsview can't answer, the ring says why =="
out="$(PATH="$BIN:$PATH" AGENTSVIEW_FAIL=1 python3 "$CLEAT" graph "$REPO" --json --probe rollout --deep 2 2>&1 >/dev/null)"
check "it exits 2" "$?" "2"
contains "with agentsview's own message" "$out" "ring 2: agentsview session list: fatal: database data version 167"
EMPTY="$(mktemp -d "$TMP/cleat-empty.XXXXXX")"
for tool in git python3; do printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v "$tool")" > "$EMPTY/$tool"; chmod +x "$EMPTY/$tool"; done
out="$(PATH="$EMPTY" python3 "$CLEAT" graph "$REPO" --json --probe rollout --deep 2 2>&1 >/dev/null)"
check "without agentsview on the PATH it exits 2" "$?" "2"
contains "and says so" "$out" "agentsview is not on the PATH"

echo "== in the terminal, P looks deeper and enter follows a hop =="
tui="$(python3 - "$CLEAT" "$REPO" <<'PY'
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["LINES"], os.environ["COLUMNS"] = "40", "160"
    os.execvp(sys.executable, [sys.executable, sys.argv[1], "graph", sys.argv[2], "--probe", "rollout plan"])
seen = b""
def drain(seconds):
    global seen
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                seen += os.read(fd, 65536)
            except OSError:
                return
# P opens ring 1 with the cursor on it; j to its first hit, rollout.md, whose
# context fills the right pane. Enter moves there; nine rows down is its first
# hop past the "Where it points" row, the regions file, which enter follows.
# Esc steps back to rollout.md's context, then out of the pane.
steps = [(b"P", "ring"), (b"j", "hit"), (b"\n", "pane"), (b"j" * 9, "down"), (b"\n", "hop"),
         (b"\x1b", "back"), (b"\x1b", "out"), (b"q", "quit")]
marks = {}
for keys, name in steps:
    drain(0.6)
    marks[name] = len(seen)
    try:
        os.write(fd, keys)
    except OSError:
        print("exited before", name)
        break
drain(1.5)
_, status = os.waitpid(pid, 0)
text = seen.decode("utf-8", "replace")
print("exit", os.waitstatus_to_exitcode(status))
print(("ok:" if "P deeper" in text else "fail:") + "key")
print(("ok:" if "Ring 1  This repo's other files and commits" in text else "fail:") + "ring")
print(("ok:" if "docs/notes/rollout.md" in text and "2 of 2 words" in text else "fail:") + "hit")
print(("ok:" if "Where it points (2)" in text and "regions.md" in text else "fail:") + "context")
print(("ok:" if "hop 1: docs/notes/regions.md" in text else "fail:") + "follow")
print(("ok:" if "Name docs/notes/rollout.md in AGENTS.md" in text else "fail:") + "advice")
after = seen[marks["back"]:].decode("utf-8", "replace")
print(("ok:" if "docs/notes/rollout.md: its context" in after else "fail:") + "esc back")
PY
)"
contains "exits 0" "$tui" "exit 0"
contains "the key line offers P" "$tui" "ok:key"
contains "P adds ring 1 as a group" "$tui" "ok:ring"
contains "its hits tagged with the prompt's words they say" "$tui" "ok:hit"
contains "a hit's context and hops fill the right pane" "$tui" "ok:context"
contains "enter follows a hop" "$tui" "ok:follow"
contains "the strip says where to name the hit" "$tui" "ok:advice"
contains "esc steps back to the hit's own context" "$tui" "ok:esc back"

echo "== --serve answers the page's deep searches, behind a token =="
page="$(python3 "$CLEAT" graph "$REPO" --probe rollout --html "$(mktemp -u "$TMP/cleat-page.XXXXXX").html" 2>&1 | sed -n 's/^cleat: wrote \(.*\.html\) (.*/\1/p')"
contains "a page opened as a file says the deep rings need the server" "$(cat "$page")" "Looking there needs the page served"
contains "and has no server to ask" "$(cat "$page")" "const SERVE = null;"
served="$(BROWSER=true PATH="$BIN:$PATH" python3 - "$CLEAT" "$REPO" <<'PY'
import json, re, signal, subprocess, sys, urllib.error, urllib.parse, urllib.request
proc = subprocess.Popen([sys.executable, sys.argv[1], "graph", sys.argv[2], "--serve", "--probe", "rollout plan"],
                        stderr=subprocess.PIPE, text=True)
try:
    base, token = re.search(r"(http://127\.0\.0\.1:\d+)/\?t=(\S+)", proc.stderr.readline()).groups()
    def get(path, **params):
        try:
            with urllib.request.urlopen("{}{}?{}".format(base, path, urllib.parse.urlencode(params))) as r:
                return r.status, r.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8")
    status, page = get("/", t=token)
    print(("ok:" if status == 200 and '"deepest": 3' in page else "fail:") + "page")
    print(("ok:" if get("/deep", term="rollout", ring=1)[0] == 403 else "fail:") + "token")
    status, body = get("/deep", t=token, term="rollout plan", ring=2)
    d = json.loads(body)
    print(("ok:" if status == 200 and [r["ring"] for r in d["rings"]] == [1, 2] else "fail:") + "deep")
    status, body = get("/context", t=token, term="rollout plan", kind="file", target="docs/notes/rollout.md")
    print(("ok:" if status == 200 and json.loads(body)["hops"][0]["target"] == "https://example.com/rollout" else "fail:") + "context")
    print(("ok:" if get("/context", t=token, term="x", kind="file", target="../../etc/passwd")[0] == 502 else "fail:") + "outside")
    print(("ok:" if get("/context", t=token, term="x", kind="commit", target="--output=/tmp/x")[0] == 502 else "fail:") + "flag")
finally:
    proc.send_signal(signal.SIGINT)
    print("exit", proc.wait(10))
PY
)"
contains "serves the page with its token and rings" "$served" "ok:page"
contains "refuses a request without the token" "$served" "ok:token"
contains "answers a deep search, ring by ring" "$served" "ok:deep"
contains "answers a hop's context" "$served" "ok:context"
contains "refuses a file outside the repo" "$served" "ok:outside"
contains "and a commit that is a flag" "$served" "ok:flag"
contains "ctrl-c stops it cleanly" "$served" "exit 0"
out="$(python3 "$CLEAT" graph "$REPO" --serve --json 2>&1)"
check "--serve with --json exits 2" "$?" "2"

summary deep
