#!/usr/bin/env bash
# `cleat graph`'s vs ideal: each file against the budget for its tier, the
# scorecard per owner, and the improvements ranked by how often they're paid.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

USER_DIR="$(mktemp -d "$TMP/cleat-user.XXXXXX")"
PLUGIN="$(mktemp -d "$TMP/cleat-plugin.XXXXXX")"
export CLAUDE_CONFIG_DIR="$USER_DIR"

write() {  # $1 path  $2 printf %b body
  mkdir -p "$(dirname "$1")"
  printf '%b' "$2" > "$1"
}
lines() {  # $1 count  $2 text: count lines of text
  local i out=""
  for ((i = 0; i < $1; i++)); do out+="$2\n"; done
  printf '%s' "$out"
}

write "$USER_DIR/settings.json" '{"enabledPlugins": {"acme@market": true}}\n'
write "$USER_DIR/plugins/installed_plugins.json" '{"version": 2, "plugins": {
 "acme@market": [{"scope": "user", "installPath": "'"$PLUGIN"'"}]}}\n'
write "$USER_DIR/CLAUDE.md" 'Plain words.\n'
write "$USER_DIR/rules/style.md" "$(lines 60 'Keep every sentence short, and say what is, not what is not.')"

write "$PLUGIN/.claude-plugin/plugin.json" '{"name": "acme"}\n'
write "$PLUGIN/skills/wordy/SKILL.md" "---\nname: wordy\ndescription: $(printf 'Use this whenever anything at all happens. %.0s' $(seq 1 10))\n---\nShort body.\n"
write "$PLUGIN/skills/big/SKILL.md" "---\nname: big\ndescription: A large body.\n---\n$(lines 120 "$(printf 'x%.0s' $(seq 1 130))")"
write "$PLUGIN/skills/tall/SKILL.md" "---\nname: tall\ndescription: A long body.\n---\n$(lines 600 'one step')"
write "$PLUGIN/skills/deploy/SKILL.md" '---\nname: deploy\ndescription: Ship it.\n---\nRead guides/a.md, guides/plain.md, guides/headed.md, and guides/anchored.md.\n'
write "$PLUGIN/skills/direct/SKILL.md" '---\nname: direct\ndescription: Links both.\n---\nRead guides/a.md and guides/b.md.\n'
write "$PLUGIN/guides/a.md" 'The order. The edge cases are in b.md.\n'
write "$PLUGIN/guides/b.md" 'Edge cases.\n'
write "$PLUGIN/guides/plain.md" "# Plain\n\n$(lines 150 'a line')"
write "$PLUGIN/guides/headed.md" "# Headed\n\n## Contents\n\n$(lines 150 'a line')"
write "$PLUGIN/guides/anchored.md" "# Anchored\n\n- [One](#one)\n- [Two](#two)\n- [Three](#three)\n\n$(lines 150 'a line')"

REPO="$(mkrepo "CLAUDE.md:::$POINTER" "AGENTS.md:::# Widget\n\nSmall.\n")"
git -C "$REPO" config cleat.launchBudget 2000

GRAPH="$(mktemp "$TMP/cleat-graph.XXXXXX")"
graph_json() {
  python3 "$CLEAT" graph --json "$@" > "$GRAPH"
  GRAPH_EXIT=$?
}

# q EXPR: `d` the vs-ideal block, `g` the graph, `node(label)` a node, `fix(check,
# label)` the improvement for a check and node, `card(owner)` an owner's row.
q() {
  python3 - "$GRAPH" "$1" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
d = g["ideal"]
by_label = {n["label"]: n for n in g["nodes"]}
def node(label):
    return by_label[label]
def fix(check, label):
    hits = [x for x in d["improvements"] if x["check"] == check and x["label"] == label]
    return hits[0] if hits else None
def card(owner):
    return next(c for c in d["owners"] if c["owner"] == owner)
print(eval(sys.argv[2]))
PY
}

echo "== the checks name their ideal, when its excess is paid, and its source =="
graph_json "$REPO"
check "exits 0" "$GRAPH_EXIT" "0"
check "five checks" "$(q 'list(d["checks"])')" "['launch', 'entry', 'body', 'nested', 'toc']"
check "each paid on its occasion" "$(q '[c["paid"] for c in d["checks"].values()]')" \
  "['every session', 'every session', 'each invocation', 'each read', 'each read']"
check "Anthropic's pages are the skill checks' sources" \
  "$(q 'all(s.startswith("https://platform.claude.com/") for c in ("entry", "body", "nested", "toc") for s in d["checks"][c]["sources"])')" "True"

echo "== launch: repo and user scope, each against the launch budget =="
check "user scope is over, held by its largest launch piece" \
  "$(q '(fix("launch", "rules/style.md")["owner"], fix("launch", "rules/style.md")["excess"] == sum(n["size"] for n in g["nodes"] if n["scope"] == "user" and n["tier"] == "launch") - 2000)')" \
  "('user scope', True)"
check "the repo is within it" "$(q 'card("this repo")["checks"]["launch"]')" "{'failing': 0, 'of': 1}"

echo "== entry: a listed entry against about 100 tokens =="
check "a wordy description is over, by its bytes past 280" \
  "$(q 'fix("entry", "/acme:wordy")["excess"] == node("/acme:wordy")["size"] - 280')" "True"
check "a short one is not" "$(q 'fix("entry", "/acme:deploy")')" "None"

echo "== body: under 5,000 tokens and 500 lines =="
check "a large body is over, by its bytes past 14,000" \
  "$(q 'fix("body", "skills/big/SKILL.md")["excess"] == node("skills/big/SKILL.md")["size"] - 14000')" "True"
check "a tall one is over on lines, with no byte excess" \
  "$(q '(fix("body", "skills/tall/SKILL.md")["actual"]["lines"], fix("body", "skills/tall/SKILL.md")["excess"])')" "(600, 0)"
check "a short body is not" "$(q 'fix("body", "skills/deploy/SKILL.md")')" "None"

echo "== nested: a reference a body reaches only through another =="
check "b.md is two reads below deploy, which doesn't link it" \
  "$(q '(fix("nested", "guides/b.md")["actual"], fix("nested", "guides/b.md")["bodies"])')" \
  "({'depth': 2}, ['skills/deploy/SKILL.md'])"
check "a body linking it directly doesn't clear it for another" \
  "$(q 'card("acme@market")["checks"]["nested"]["failing"]')" "1"

echo "== toc: a reference over 100 lines needs contents at the top =="
check "a plain long guide has none" "$(q 'fix("toc", "guides/plain.md")["actual"]')" "{'lines': 152, 'toc': False}"
check "a contents heading counts" "$(q 'fix("toc", "guides/headed.md")')" "None"
check "three anchor links count" "$(q 'fix("toc", "guides/anchored.md")')" "None"

echo "== ranked by when it's paid, then by excess =="
check "every session, then each invocation, then each read, the larger file first" \
  "$(q '[(x["check"], x["label"]) for x in d["improvements"]]')" \
  "[('launch', 'rules/style.md'), ('entry', '/acme:wordy'), ('body', 'skills/big/SKILL.md'), ('body', 'skills/tall/SKILL.md'), ('toc', 'guides/plain.md'), ('nested', 'guides/b.md')]"

echo "== the scorecard per owner =="
check "acme's checks, failing of applicable" \
  "$(q '{k: (v["failing"], v["of"]) for k, v in card("acme@market")["checks"].items()}')" \
  "{'entry': (1, 5), 'body': (2, 5), 'nested': (1, 5), 'toc': (1, 3)}"
check "the session excess is the larger of launch and entry" \
  "$(q 'card("user scope")["excess"]["session"] == fix("launch", "rules/style.md")["excess"]')" "True"
check "the invocation excess sums the bodies'" \
  "$(q 'card("acme@market")["excess"]["invocation"] == fix("body", "skills/big/SKILL.md")["excess"]')" "True"
check "owners ordered by what every session pays" \
  "$(q '[c["owner"] for c in d["owners"]][:2]')" "['user scope', 'acme@market']"

echo "== a filter scores only what it shows =="
graph_json "$REPO" --plugin acme
check "user scope drops out" "$(q '[c["owner"] for c in d["owners"]]')" "['acme@market']"

echo "== the page carries a vs ideal view =="
PAGE="$(mktemp -u "$TMP/cleat-page.XXXXXX").html"
python3 "$CLEAT" graph "$REPO" --html "$PAGE" 2>/dev/null
page="$(cat "$PAGE")"
contains "the scorecard beside the radar" "$page" 'id="scorecard"'
contains "a halo on each file past its ideal" "$page" 'class: "halo"'
contains "and an owner's plan in the details panel" "$page" 'function showOwnerPlan(owner)'
contains "the data inline" "$page" '"improvements":'

echo "== the terminal lists the improvements under vs ideal =="
tui="$(python3 - "$CLEAT" "$REPO" <<'PY'
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["LINES"], os.environ["COLUMNS"] = "30", "160"
    os.execvp(sys.executable, [sys.executable, sys.argv[1], "graph", sys.argv[2]])
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
# Close Insights, down to vs ideal, open it, down to the first improvement.
for keys in (b" ", b"j", b" ", b"j", b"q"):
    drain(0.6)
    os.write(fd, keys)
drain(1.5)
_, status = os.waitpid(pid, 0)
text = seen.decode("utf-8", "replace")
print("exit", os.waitstatus_to_exitcode(status))
print("group" if "vs ideal (6 to improve)" in text else "no group")
print("first" if "launch" in text and "user scope" in text else "no first row")
print("fix" if "fix: move what only some sessions need" in text else "no fix line")
PY
)"
check "the browser quits cleanly" "$(echo "$tui" | sed -n 1p)" "exit 0"
check "a vs ideal group with its count" "$(echo "$tui" | sed -n 2p)" "group"
check "the costliest improvement first" "$(echo "$tui" | sed -n 3p)" "first"
check "its repair in the details strip" "$(echo "$tui" | sed -n 4p)" "fix"

summary "ideal"
