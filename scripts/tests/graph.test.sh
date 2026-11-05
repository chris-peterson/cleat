#!/usr/bin/env bash
# `cleat graph`: the context graph across the repo, user scope, and enabled
# plugins, with each node's reach and closure cost, as JSON, a page, or a
# terminal browser.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# User scope and the plugin cache live in throwaway directories, so the suite
# never reads the real ~/.claude.
USER_DIR="$(mktemp -d "$TMP/cleat-user.XXXXXX")"
PLUGIN="$(mktemp -d "$TMP/cleat-plugin.XXXXXX")"
export CLAUDE_CONFIG_DIR="$USER_DIR"

write() {  # $1 path  $2 printf %b body
  mkdir -p "$(dirname "$1")"
  printf '%b' "$2" > "$1"
}

write "$USER_DIR/settings.json" '{"enabledPlugins": {"acme@market": true, "off@market": false},
 "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "echo hello"}]}]}}\n'
write "$USER_DIR/plugins/installed_plugins.json" '{"version": 2, "plugins": {
 "acme@market": [{"scope": "user", "installPath": "'"$PLUGIN"'"}],
 "off@market": [{"scope": "user", "installPath": "/nonexistent"}]}}\n'
write "$USER_DIR/CLAUDE.md" 'Plain words in every reply.\n'
write "$USER_DIR/rules/tone.md" 'Short sentences.\n'

DEPLOY_BODY='Read `${CLAUDE_PLUGIN_ROOT}/guides/deploy.md` first.\n\n```bash\nbash "${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh"\n```\n\nThen run /acme:verify.\n'
write "$PLUGIN/.claude-plugin/plugin.json" '{"name": "acme"}\n'
write "$PLUGIN/skills/deploy/SKILL.md" "---\nname: deploy\ndescription: Ship the build.\n---\n$DEPLOY_BODY"
write "$PLUGIN/skills/verify/SKILL.md" '---\nname: verify\ndescription: Check the build.\ndisable-model-invocation: true\n---\nCheck it. The long form is in guides/verify.md, mirrored in guides/verify-copy.md.\n'
write "$PLUGIN/guides/deploy.md" 'Deploy in order. The edge cases are in more.md.\n'
write "$PLUGIN/guides/more.md" 'Edge cases. Back to deploy.md for the order.\n'
write "$PLUGIN/guides/verify.md" 'How to verify, at length.\n'
write "$PLUGIN/guides/verify-copy.md" 'How to verify, at length.\n'
write "$PLUGIN/scripts/ship.sh" '#!/bin/sh\necho shipped\n'
write "$PLUGIN/hooks/hooks.json" '{"hooks": {"PostToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh"}]}]}}\n'

REPO="$(mkrepo "CLAUDE.md:::$POINTER" "AGENTS.md:::# Widget\n\nThe [design notes](docs/design.md) are here.\n" \
               "docs/design.md:::Design notes.\n" "src/app.ts:::export {}\n" \
               ".claude/rules/api.md:::---\npaths:\n  - \"src/**/*.ts\"\n---\nValidate input.\n" \
               ".claude/rules/old.md:::---\npaths:\n  - \"nothing/**\"\n---\nNo longer applies.\n")"

GRAPH="$(mktemp "$TMP/cleat-graph.XXXXXX")"
graph_json() {  # args to cleat graph; JSON lands in $GRAPH
  python3 "$CLEAT" graph --json "$@" > "$GRAPH"
  GRAPH_EXIT=$?
}

# q EXPR: evaluate EXPR with `g` the parsed graph, `node(label)` a node by
# label, and `edge(src, dst)` the kind of the edge between two labels or None.
q() {
  python3 - "$GRAPH" "$1" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
by_label = {}
for n in g["nodes"]:
    by_label.setdefault(n["label"], n)
ids = {n["id"]: n["label"] for n in g["nodes"]}
def node(label):
    return by_label[label]
def edge(src, dst):
    for e in g["edges"]:
        if ids[e["source"]] == src and ids[e["target"]] == dst:
            return e["kind"]
    return None
def size(text):
    return len(text.encode("utf-8"))
print(eval(sys.argv[2]))
PY
}

echo "== the walk covers the repo, user scope, and the enabled plugins =="
graph_json "$REPO"
check "exits 0" "$GRAPH_EXIT" "0"
check "the scopes it found" "$(q 'sorted({n["scope"] for n in g["nodes"]})')" "['plugin', 'repo', 'user']"
check "a disabled plugin is left out" "$(q 'any(n["plugin"] == "off" for n in g["nodes"])')" "False"
check "its plugin and marketplace label each plugin node" \
  "$(q '(node("/acme:deploy")["plugin"], node("/acme:deploy")["marketplace"])')" "('acme', 'market')"

echo "== each node carries its load tier and its size as loaded =="
check "a listing entry loads at launch" "$(q 'node("/acme:deploy")["tier"]')" "launch"
check "a skill body loads on invoke" "$(q 'node("skills/deploy/SKILL.md")["tier"]')" "on invoke"
check "measured without its frontmatter" \
  "$(q 'node("skills/deploy/SKILL.md")["size"] == size(open("'"$PLUGIN"'/skills/deploy/SKILL.md").read().split("---\n", 2)[2])')" "True"
check "a guide loads on read" "$(q 'node("guides/deploy.md")["tier"]')" "on read"
check "a path-scoped rule is a root on path match" "$(q '(node(".claude/rules/api.md")["tier"], node(".claude/rules/api.md")["root"])')" "('on path match', True)"
check "an always-on user rule loads at launch" "$(q 'node("rules/tone.md")["tier"]')" "launch"

echo "== edges are the references each file states =="
check "an entry opens its body" "$(q 'edge("/acme:deploy", "skills/deploy/SKILL.md")')" "invoke"
check "a plugin-root path is a read" "$(q 'edge("skills/deploy/SKILL.md", "guides/deploy.md")')" "read"
check "a script path is a run" "$(q 'edge("skills/deploy/SKILL.md", "scripts/ship.sh")')" "run"
check "a named skill is an invoke" "$(q 'edge("skills/deploy/SKILL.md", "skills/verify/SKILL.md")')" "invoke"
check "a plugin-relative path from a skill is a read" "$(q 'edge("skills/verify/SKILL.md", "guides/verify.md")')" "read"
check "a bare name beside the file is a read" "$(q 'edge("guides/deploy.md", "guides/more.md")')" "read"
check "and so is the reference back, a cycle" "$(q 'edge("guides/more.md", "guides/deploy.md")')" "read"

echo "== an @ import folds into the file that imports it =="
check "no node of its own" "$(q '"AGENTS.md" in by_label')" "False"
check "CLAUDE.md carries both sizes" \
  "$(q 'node("CLAUDE.md")["size"] == size(open("'"$REPO"'/CLAUDE.md").read()) + size(open("'"$REPO"'/AGENTS.md").read())')" "True"
check "and the imported file's references" "$(q 'edge("CLAUDE.md", "docs/design.md")')" "read"

echo "== hooks are roots on event, and unmeasured =="
check "a plugin hook" "$(q '[ (n["tier"], n["root"], n["measured"]) for n in g["nodes"] if n["kind"] == "hook" and n["scope"] == "plugin"]')" "[('on event', True, False)]"
check "a settings hook" "$(q 'sum(1 for n in g["nodes"] if n["kind"] == "hook" and n["scope"] == "user")')" "1"

echo "== each node says when it loads; each edge, the line that opens it =="
check "an instruction file loads every session" "$(q 'node("CLAUDE.md")["when"]')" "every session, at launch"
check "a path-scoped rule names its globs" \
  "$(q '(node(".claude/rules/api.md")["trigger"], node(".claude/rules/api.md")["when"])')" \
  "('src/**/*.ts', 'when a file matching src/**/*.ts is read, written, or edited')"
check "a rule whose globs match nothing here is retired" "$(q 'node(".claude/rules/old.md")["trigger"]')" "retired"
check "a typed-only skill waits for you to type it" "$(q 'node("/acme:verify")["when"]')" "only when you type /acme:verify"
check "a hook names its event and matcher" \
  "$(q '[n["when"] for n in g["nodes"] if n["kind"] == "hook" and n["scope"] == "plugin"]')" "['on PostToolUse for Write']"
check "a reference carries its file, line, and text" \
  "$(q '[(e["file"], e["line"], e["text"]) for e in g["edges"] if ids[e["source"]] == "skills/deploy/SKILL.md" and ids[e["target"]] == "guides/deploy.md"]')" \
  "[('skills/deploy/SKILL.md', 5, 'Read \`\${CLAUDE_PLUGIN_ROOT}/guides/deploy.md\` first.')]"
check "an imported file's link is quoted from that file" \
  "$(q '[(e["file"], e["line"], e["text"]) for e in g["edges"] if ids[e["target"]] == "docs/design.md"]')" \
  "[('AGENTS.md', 3, 'The [design notes](docs/design.md) are here.')]"

echo "== reach cost: the cheapest path from a root, the node excluded =="
check "a root costs nothing to reach" "$(q 'node("/acme:deploy")["reach"]')" "0"
check "a guide costs the entry and the body before it" \
  "$(q 'node("guides/deploy.md")["reach"] == node("/acme:deploy")["size"] + node("skills/deploy/SKILL.md")["size"]')" "True"
check "and names the node it is reached through" \
  "$(q 'node("guides/deploy.md")["via"] == node("skills/deploy/SKILL.md")["id"]')" "True"

echo "== closure cost: what a node pulls in, each once, invoked skills excluded =="
check "the entry, its body, both guides, and nothing of verify" \
  "$(q 'node("/acme:deploy")["closure"] == sum(node(l)["size"] for l in ("/acme:deploy", "skills/deploy/SKILL.md", "guides/deploy.md", "guides/more.md"))')" "True"
check "the cycle counts each guide once" \
  "$(q 'node("guides/deploy.md")["closure"] == node("guides/deploy.md")["size"] + node("guides/more.md")["size"]')" "True"

echo "== next cost: what opening a node one level adds =="
check "an entry's next is its body" \
  "$(q 'node("/acme:deploy")["next"] == node("skills/deploy/SKILL.md")["size"]')" "True"
check "a body's next is the children it pulls in, the skill it invokes left to its own root" \
  "$(q 'node("skills/deploy/SKILL.md")["next"] == node("guides/deploy.md")["size"]')" "True"
check "so next never exceeds what the closure holds below the node" \
  "$(q 'all(n["next"] <= n["closure"] - n["size"] for n in g["nodes"])')" "True"
check "a leaf adds nothing" "$(q 'node("guides/verify.md")["next"]')" "0"
check "the JSON names the ratio the views convert with" "$(q 'g["bytesPerToken"]')" "2.8"

echo "== an unmeasured node counts as zero, and the totals say how many =="
check "the script is unmeasured" "$(q '(node("scripts/ship.sh")["measured"], node("scripts/ship.sh")["size"])')" "(False, 0)"
check "the closure names it" "$(q 'node("/acme:deploy")["closureUnmeasured"]')" "1"
check "the totals count it with the hooks" "$(q 'g["totals"]["unmeasured"]')" "3"

echo "== every view reports launch, the deepest path, and every file =="
check "the deepest path is the largest spent-plus-size" \
  "$(q 'g["totals"]["deepest"] == max((n["reach"] or 0) + n["size"] for n in g["nodes"])')" "True"
check "every file is the sum of sizes" "$(q 'g["totals"]["reachable"] == sum(n["size"] for n in g["nodes"])')" "True"
check "owners split the same totals" \
  "$(q '(sum(o["reachable"] for o in g["owners"]) == g["totals"]["reachable"], sorted(o["owner"] for o in g["owners"]))')" \
  "(True, ['acme@market', 'this repo', 'user scope'])"
check "each owner carries its own deepest path" \
  "$(q '[o["deepest"] for o in g["owners"] if o["owner"] == "acme@market"] == [max((n["reach"] or 0) + n["size"] for n in g["nodes"] if n["plugin"] == "acme")]')" "True"

echo "== insights: findings with how they were computed and what Show narrows to =="
check "every insight has a title, text, query, and focus" \
  "$(q 'all(set(i) == {"title", "text", "query", "focus"} for i in g["insights"])')" "True"
contains "the biggest share of launch" "$(q '[i["text"] for i in g["insights"]]')" "tokens every session loads at launch"
check "the heaviest skill, focused on its entry" \
  "$(q '[i["focus"] for i in g["insights"] if i["title"].startswith("Heaviest skill")] == [{"type": "node", "id": node("/acme:deploy")["id"]}]')" "True"
check "byte-identical copies, as a set" \
  "$(q 'sorted(ids[x] for i in g["insights"] if i["title"].startswith("Duplicate") for x in i["focus"]["ids"])')" "['guides/verify-copy.md', 'guides/verify.md']"
contains "a body naming a typed-only skill" "$(q '[i["text"] for i in g["insights"]]')" "names /acme:verify, which is typed-only"
check "the SessionStart hooks cleat can't size" \
  "$(q '[i["title"] for i in g["insights"] if i["title"].startswith("Unsized")]')" "['Unsized at launch: 1 hook']"
graph_json "$REPO" --scope repo
check "computed over what the filter shows" "$(q 'any("acme" in i["text"] for i in g["insights"])')" "False"
graph_json "$REPO"

echo "== a filter changes what is shown, not what a node costs =="
whole="$(q 'node("/acme:deploy")["closure"]')"
graph_json "$REPO" --plugin acme
check "only the plugin's nodes" "$(q 'sorted({n["scope"] for n in g["nodes"]})')" "['plugin']"
check "the closure is unchanged" "$(q 'node("/acme:deploy")["closure"]')" "$whole"
check "edges stay between kept nodes" "$(q 'all(e["source"] in {n["id"] for n in g["nodes"]} for e in g["edges"])')" "True"
graph_json "$REPO" --tier launch --tier "on path match"
check "tiers combine" "$(q 'sorted({n["tier"] for n in g["nodes"]})')" "['launch', 'on path match']"
graph_json "$REPO" --scope repo --marketplace market
check "filters intersect" "$(q 'len(g["nodes"])')" "0"

echo "== --html writes the page with the graph inline =="
page="$(mktemp -u "$TMP/cleat-page.XXXXXX").html"
html_err="$(python3 "$CLEAT" graph "$REPO" --html "$page" 2>&1)"
check "exits 0" "$?" "0"
contains "names what it wrote" "$html_err" "$page"
contains "with launch, every file, and the deepest path" "$html_err" "deepest path"
contains "carries the graph" "$(cat "$page")" '"label":"/acme:deploy"'
contains "and its insights" "$(cat "$page")" '"title":"Heaviest skill: /acme:deploy"'
contains "and each reference's line" "$(cat "$page")" '"text":"The [design notes](docs/design.md) are here."'
absent "with the placeholder filled" "$(cat "$page")" "/*GRAPH*/null"

echo "== --html with no path writes a temporary page and opens it =="
# BROWSER names the opener Python's webbrowser runs; this one records the URL.
opened="$(mktemp -u "$TMP/cleat-opened.XXXXXX")"
opener="$(mktemp "$TMP/cleat-opener.XXXXXX")"
printf '#!/bin/sh\nprintf "%%s" "$1" > %s\n' "$opened" > "$opener"
chmod +x "$opener"
html_err="$(BROWSER="$opener" python3 "$CLEAT" graph "$REPO" --html 2>&1)"
check "exits 0" "$?" "0"
written="$(printf '%s' "$html_err" | sed -n 's/^cleat: wrote \(.*\.html\) (.*/\1/p')"
contains "writes an .html file" "$written" ".html"
contains "with the graph in it" "$(cat "$written" 2>/dev/null)" '"label":"/acme:deploy"'
contains "and opens it" "$(cat "$opened" 2>/dev/null)" "file://"
out="$(python3 "$CLEAT" graph --html "$REPO" 2>&1)"
check "a directory where the page path goes exits 2" "$?" "2"
contains "and says to put DIR first" "$out" "put DIR before --html"

echo "== outside a terminal the browser can't open =="
out="$(python3 "$CLEAT" graph "$REPO" < /dev/null 2>&1)"
check "exits 2" "$?" "2"
contains "names --json" "$out" "--json"
contains "names --html" "$out" "--html"

echo "== in a terminal it opens, browses, and quits =="
tui="$(python3 - "$CLEAT" "$REPO" <<'PY'
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["LINES"], os.environ["COLUMNS"] = "30", "120"
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
# Insights opens first; close it, then Instructions, Rules, Plugins: down three
# to Plugins, open it, down to acme, open that. xterm sends the arrows in keypad
# mode as ESC O <letter>.
for keys in (b" ", b"jjj", b" ", b"j", b"\n", b"j", b"s", b"\t", b"\x1bOD", b"g", b"q"):
    drain(0.6)
    try:
        os.write(fd, keys)
    except OSError:
        print("exited before", keys)
        break
drain(1.5)
_, status = os.waitpid(pid, 0)
text = seen.decode("utf-8", "replace")
print("exit", os.waitstatus_to_exitcode(status))
print("by type" if "by artifact type" in text else "no type rollup")
print("insights" if "Insights (" in text and "Heaviest skill" in text else "no insights")
print("categories" if all(c in text for c in ("Instructions", "Rules", "Plugins", "Hooks")) else "missing a category")
print("deploy" if "acme:deploy" in text else "no deploy root")
# curses redraws only the cells that change, so the heading's new word arrives
# without the "by " it shares with the old one.
print("by owner" if "owner" in text else "no owner rollup")
print("footer" if "launch" in text and "unmeasured" in text else "no footer")
print("token columns" if all(c in text for c in ("spent", "+next", "~tokens")) else "no token columns")
print("deep column" if "deep" in text and "deepest path" in text and "every file" in text else "no depth or breadth")
print("details strip" if " when " in text and " via " in text else "no details strip")
PY
)"
contains "exits 0" "$tui" "exit 0"
contains "opens on the rollup by artifact type" "$tui" "by type"
contains "with the insights open at the top" "$tui" "insights"
contains "with a row per category" "$tui" "categories"
contains "enter and space open a plugin to its roots" "$tui" "deploy"
contains "g switches the rollup to owners" "$tui" "by owner"
contains "draws the footer totals" "$tui" "footer"
contains "costs in tokens: spent, this, +next, all" "$tui" "token columns"
contains "launch, every file, and the deepest path, as the page reports them" "$tui" "deep column"
contains "a strip saying when the selection loads and what opens it" "$tui" "details strip"

echo "== broken inputs exit 2 and name the cause =="
good_settings="$(cat "$USER_DIR/settings.json")"
printf '{ not json' > "$USER_DIR/settings.json"
out="$(python3 "$CLEAT" graph --json "$REPO" 2>&1)"
check "a settings file that doesn't parse" "$?" "2"
contains "names it" "$out" "settings.json does not parse"
printf '%s' "$good_settings" | sed 's/"off@market": false/"off@market": true/' > "$USER_DIR/settings.json"
out="$(python3 "$CLEAT" graph --json "$REPO" 2>&1)"
check "an enabled plugin whose install path is missing" "$?" "2"
contains "names the plugin" "$out" "off@market"
printf '%s' "$good_settings" > "$USER_DIR/settings.json"

echo "== DIR defaults to the current directory =="
here="$(cd "$REPO" && python3 "$CLEAT" graph --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["directory"])')"
check "the repo it ran in" "$here" "$(cd "$REPO" && pwd -P)"

summary graph
