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
# Web address measurements are cached here, never in the real ~/.cache.
export XDG_CACHE_HOME="$(mktemp -d "$TMP/cleat-cache.XXXXXX")"

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
write "$USER_DIR/skills/synced/acct_1/docx/SKILL.md" '---\nname: docx\ndescription: Word files.\n---\nMake a .docx.\n'
write "$USER_DIR/skills/synced/acct_1/tone/SKILL.md" '---\nname: tone\ndescription: Synced tone.\n---\nShadowed by the local one.\n'
write "$USER_DIR/skills/tone/SKILL.md" '---\nname: tone\ndescription: Local tone.\n---\nThe local one wins.\n'
write "$USER_DIR/agents/focus/focus.md" '---\nname: focus\ndescription: Plan the day.\n---\nRead the board. Past standups are in notes/.\n'
write "$USER_DIR/agents/focus/board.py" 'print(1)\n'
write "$USER_DIR/agents/focus/notes/monday.md" 'Monday standup.\n'

DEPLOY_BODY='Read `${CLAUDE_PLUGIN_ROOT}/guides/deploy.md` first.\n\n```bash\nbash "${CLAUDE_PLUGIN_ROOT}/scripts/ship.sh"\n```\n\nThen run /acme:verify.\n'
write "$PLUGIN/.claude-plugin/plugin.json" '{"name": "acme"}\n'
write "$PLUGIN/skills/deploy/SKILL.md" "---\nname: deploy\ndescription: Ship the build.\n---\n$DEPLOY_BODY"
write "$PLUGIN/skills/verify/SKILL.md" '---\nname: verify\ndescription: Check the build.\ndisable-model-invocation: true\n---\nCheck it. The long form is in guides/verify.md, mirrored in guides/verify-copy.md.\n'
write "$PLUGIN/guides/deploy.md" 'Deploy in order. The edge cases are in more.md.\n'
write "$PLUGIN/guides/more.md" 'Edge cases. Retry the build. Back to deploy.md for the order. Release notes: https://example.com/releases, not https://host/notes.\n'
write "$PLUGIN/guides/verify.md" 'How to verify, at length.\n'
write "$PLUGIN/guides/verify-copy.md" 'How to verify, at length.\n'
write "$PLUGIN/scripts/ship.sh" '#!/bin/sh\necho shipped\ncat "$(dirname "$0")/../guides/notice.md"\n'
# Beside the guides, and nothing links to them: one a guide's line is about,
# one nothing talks about, one for people, and one the hook's script prints.
write "$PLUGIN/guides/edge-cases.md" '# Edge cases\n\nWhen a deploy half lands.\n'
write "$PLUGIN/guides/stale.md" '# Stale\n\nNothing current.\n'
write "$PLUGIN/guides/README.md" 'For people browsing the folder.\n'
write "$PLUGIN/guides/notice.md" 'Shown by the hook.\n'
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
check "a skill the account syncs is listed" "$(q 'node("/docx")["path"].endswith("skills/synced/acct_1/docx/SKILL.md")')" "True"
check "labeled without the account id" "$(q '"skills/synced/docx/SKILL.md" in by_label')" "True"
check "and one in skills/ shadows a synced one of the same name" "$(q 'node("/tone")["path"].endswith("skills/tone/SKILL.md")')" "True"
check "an agent in its own folder is listed" "$(q '(node("/focus")["kind"], node("agents/focus/focus.md")["kind"])')" "('entry', 'agent')"

echo "== edges are the references each file states =="
check "an entry opens its body" "$(q 'edge("/acme:deploy", "skills/deploy/SKILL.md")')" "invoke"
check "a plugin-root path is a read" "$(q 'edge("skills/deploy/SKILL.md", "guides/deploy.md")')" "read"
check "a script path is a run" "$(q 'edge("skills/deploy/SKILL.md", "scripts/ship.sh")')" "run"
check "a named skill is an invoke" "$(q 'edge("skills/deploy/SKILL.md", "skills/verify/SKILL.md")')" "invoke"
check "a plugin-relative path from a skill is a read" "$(q 'edge("skills/verify/SKILL.md", "guides/verify.md")')" "read"
check "a bare name beside the file is a read" "$(q 'edge("guides/deploy.md", "guides/more.md")')" "read"
check "and so is the reference back, a cycle" "$(q 'edge("guides/more.md", "guides/deploy.md")')" "read"

echo "== a file's web addresses are its remote references =="
check "the URL, trimmed of the comma, with its host and line" \
  "$(q '[(r["url"], r["host"], r["line"]) for r in node("guides/more.md")["remotes"]]')" \
  "[('https://example.com/releases', 'example.com', 1)]"
check "a file with none carries none" "$(q '"remotes" in node("guides/deploy.md")')" "False"
check "--json lists each site the shown files name, with the files naming it" \
  "$(q '[(s["host"], len(s["refs"]), [ids[i] for i in s["sources"]]) for s in g["sites"]]')" \
  "[('example.com', 1, ['guides/more.md'])]"

echo "== --probe follows a term out from the loaded context =="
graph_json "$REPO" --probe deploy
check "the entry, its body, the guide, and the guide's neighbor light in turn" \
  "$(q '[(h["label"], h["hop"], h["signposted"]) for h in g["probe"]["hits"]]')" \
  "[('/acme:deploy', 0, True), ('skills/deploy/SKILL.md', 1, True), ('guides/deploy.md', 2, True), ('guides/more.md', 3, True)]"
check "with the lines that mention it" "$(q 'g["probe"]["hits"][2]["lines"]')" "['Deploy in order. The edge cases are in more.md.']"
check "the site a lit line names" "$(q '[(s["host"], len(s["refs"])) for s in g["probe"]["sites"]]')" "[('example.com', 1)]"
contains "and the summary every view gives" "$(q 'g["probe"]["summary"]')" "Following them lights 3 more over 3 hops"
contains "counting the roots a session has at launch" "$(q 'g["probe"]["summary"]')" "1 of 7 loaded files"
graph_json "$REPO" --probe "Please deploy it to production!"
check "a prompt probes for its words, less the ones that say nothing" "$(q 'g["probe"]["words"]')" "['deploy', 'production']"
check "and lights what any of them reaches" \
  "$(q '[h["label"] for h in g["probe"]["hits"]]')" \
  "['/acme:deploy', 'skills/deploy/SKILL.md', 'guides/deploy.md', 'guides/more.md']"
contains "the summary names the words" "$(q 'g["probe"]["summary"]')" "mention “deploy” or “production”"
check "each hit says which of the words it says, to rank by" "$(q 'g["probe"]["hits"][0]["matched"]')" "['deploy']"
graph_json "$REPO" --probe ploy
check "a word matches only where a word starts" "$(q '(len(g["probe"]["hits"]), len(g["probe"]["islands"]))')" "(0, 0)"
graph_json "$REPO" --probe '"deploy in order"'
check "a quoted phrase is looked for as typed" "$(q '(g["probe"]["words"], [i["label"] for i in g["probe"]["islands"]])')" "(['deploy in order'], ['guides/deploy.md'])"
graph_json "$REPO" --probe release
check "a term nothing loaded mentions leaves an island" \
  "$(q '(len(g["probe"]["hits"]), [i["label"] for i in g["probe"]["islands"]])')" "(0, ['guides/more.md'])"
contains "and the summary says so" "$(q 'g["probe"]["summary"]')" "Nothing loaded mentions"
check "the island names the file that links it, which the term never opens" \
  "$(q '(g["probe"]["islands"][0]["fix"]["fix"], ids[g["probe"]["islands"][0]["fix"]["id"]], g["probe"]["islands"][0]["fix"]["line"])')" \
  "('behind', 'guides/deploy.md', 1)"
check "and says so" "$(q 'g["probe"]["islands"][0]["advice"]')" \
  "guides/deploy.md links here, and asking about “release” never opens it."
graph_json "$REPO" --probe build
check "where a lit file links a file that links the island, the fix is naming the term on that line" \
  "$(q '[(i["label"], i["fix"]["fix"], ids[i["fix"]["id"]], i["fix"]["line"], ids[i["fix"]["opens"]]) for i in g["probe"]["islands"]]')" \
  "[('guides/more.md', 'name', 'skills/deploy/SKILL.md', 5, 'guides/deploy.md')]"
contains "and says so" "$(q 'g["probe"]["islands"][0]["advice"]')" \
  "skills/deploy/SKILL.md is lit, but its line opening guides/deploy.md never says “build”. Say it there, and both light."
graph_json "$REPO" --probe
check "with no term, every reached node at its hop" "$(q 'sorted({h["hop"] for h in g["probe"]["hits"]})')" "[0, 1, 2, 3]"
check "and every site" "$(q '[s["host"] for s in g["probe"]["sites"]]')" "['example.com']"
contains "the roots waiting on a trigger counted apart" "$(q 'g["probe"]["summary"]')" "7 files are loaded or listed at launch and 5 wait on a trigger"

echo "== orphans: files beside the guidance that nothing links to =="
graph_json "$REPO"
check "each, with how it is orphaned" \
  "$(q 'sorted((o["label"], o["status"]) for o in g["orphans"])')" \
  "[('agents/focus/notes/monday.md', 'folder'), ('guides/edge-cases.md', 'unlinked'), ('guides/stale.md', 'unlinked')]"
check "a README, and a file a hook's script names, are not" \
  "$(q 'any(o["label"] in ("guides/README.md", "guides/notice.md") for o in g["orphans"])')" "False"
check "nor in any total" "$(q 'any(n["label"] == "guides/stale.md" for n in g["nodes"])')" "False"
check "one a reachable line is about: link it there" \
  "$(q '[(o["fix"]["file"], o["fix"]["line"], o["advice"]) for o in g["orphans"] if o["label"] == "guides/edge-cases.md"]')" \
  "[('guides/deploy.md', 1, 'Nothing links to it. guides/deploy.md talks about cases, edge too: link it there, with when to read it.')]"
check "one nothing talks about: link it from the folder's linker, or delete it" \
  "$(q '[(o["fix"], o["advice"]) for o in g["orphans"] if o["label"] == "guides/stale.md"]')" \
  "[(None, 'Nothing links to it, and nothing a session reaches talks about stale. Link it from skills/verify/SKILL.md if it is still needed, or delete it.')]"
check "one only its folder is named for: name it on that line" \
  "$(q '[(o["fix"]["file"], o["fix"]["line"], o["folder"]) for o in g["orphans"] if o["status"] == "folder"]')" \
  "[('agents/focus/focus.md', 5, 'notes')]"
graph_json "$REPO" --scope repo
check "filtered like the nodes" "$(q 'g["orphans"]')" "[]"
graph_json "$REPO"

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
absent "and the stopwords the CLI probes with" "$(cat "$page")" "/*STOPWORDS*/null"
contains "so the page reads a prompt as the CLI does" "$(cat "$page")" 'function keywords(term)'
contains "the details panel links the file and its folder" "$(cat "$page")" 'function fileLinks(path)'
contains "double-clicking a file narrows the radar to what it pulls in" "$(cat "$page")" 'sky.addEventListener("dblclick"'
absent "the page loads no script from outside itself" "$(cat "$page")" '<script src='
absent "nor a font" "$(cat "$page")" 'fonts.googleapis'
contains "a key says what a dashed star means" "$(cat "$page")" 'Dashed: loads only on a trigger'
contains "an owner's fixes become a plan" "$(cat "$page")" 'function drawPlan(owner)'
contains "with a starter prompt to copy" "$(cat "$page")" 'id="copy-prompt"'
contains "the page is the radar" "$(cat "$page")" '<div id="radar">'
absent "with no other view to switch to" "$(cat "$page")" 'role="tablist"'
contains "a day and night switch" "$(cat "$page")" 'id="theme"'
contains "a meter fills with what loads at start, then what a prompt opens" "$(cat "$page")" 'function spendOrder(keep, P, shown, beyond)'
contains "Escape steps back" "$(cat "$page")" 'function stepBack()'
contains "along one trail, kept in the browser's history" "$(cat "$page")" 'history.pushState({ cleat: depth }'
contains "that the mouse's back button walks too" "$(cat "$page")" 'ev.button === 3'
contains "orphans are marked as unknown contacts" "$(cat "$page")" 'el("path", { class: cls, d: quatrefoil(x, y, size * 0.5) }'
contains "a radar control opens the web addresses" "$(cat "$page")" 'id="sites-open"'
contains "as does the perimeter" "$(cat "$page")" 'class: "perimeter-hit", r: perimeterR, "data-sites": ""'
contains "a home control at the top left resets the view" "$(cat "$page")" '<header>
  <button id="home" class="icon" aria-label="Reset the view"'
contains "back to the trail's start" "$(cat "$page")" 'if (depth > 0) history.go(-depth);'
contains "the repo's name returns home too" "$(cat "$page")" '$("repo").addEventListener("click", goHome);'
absent "the header names no path on disk" "$(cat "$page")" 'id="source"'
contains "the details panel opens on what to look at first" "$(cat "$page")" 'function focusPanel()'
contains "and a file's particulars wait behind More" "$(cat "$page")" 'More about this file'
contains "filters and findings wait in a drawer" "$(cat "$page")" '<aside id="drawer" hidden>'
absent "nothing plays by itself" "$(cat "$page")" 'id="play"'
contains "the legend sits on the radar" "$(cat "$page")" '<summary>Legend</summary>'
absent "examples are offered in the walkthrough alone" "$(cat "$page")" 'parts.push(tryChips'
contains "with a probe to type a term into" "$(cat "$page")" 'id="probe"'
absent "and leaves the terms to the reader" "$(cat "$page")" 'class="chip"'
contains "the meter marks each common context window" "$(cat "$page")" 'const LIMITS = [200000, 1000000];'
contains "a site panel says what following it costs" "$(cat "$page")" 'function siteCost(site)'
contains "a web addresses panel lists every site, as the terminal's external rollup does" "$(cat "$page")" 'function sitesPanel()'
contains "reached from the opening panel" "$(cat "$page")" '<button id="all-sites">All ${siteOf.size} web'
contains "day and night switch by icon" "$(cat "$page")" '<svg class="moon"'
contains "that follows references hop by hop" "$(cat "$page")" 'function probe(term, keep)'
contains "and draws the returns, the horizon, and the remote sites" "$(cat "$page")" 'function drawRadar(keep)'
contains "with a wedge only for an owner the term touches" "$(cat "$page")" '(n.root && matched.has(ownerOf(n)))'
contains "an island's card names the line that would connect it" "$(cat "$page")" 'function islandFix(P, id, keep)'
contains "the orphans sit past the horizon as their own mark" "$(cat "$page")" 'class="mark-orphan"'
contains "each with a card saying where to name it" "$(cat "$page")" 'function orphanCard(o)'
contains "and all of them in a list by owner" "$(cat "$page")" 'function orphansPanel()'
contains "carrying the orphans" "$(cat "$page")" '"label":"guides/stale.md"'
contains "unpacking each file's text in the browser" "$(cat "$page")" 'new DecompressionStream("gzip")'
absent "with the text placeholder filled" "$(cat "$page")" "/*TEXT*/null"
texts="$(python3 - "$page" <<'PY'
import base64, gzip, json, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
packed = re.search(r'const TEXT_B64 = ("[^"]+");', page).group(1)
print(json.dumps(json.loads(gzip.decompress(base64.b64decode(json.loads(packed))).decode("utf-8"))))
PY
)"
contains "the text payload carries each file as loaded" "$texts" "Deploy in order."
contains "and each listing entry as listed" "$texts" "- acme:deploy: Ship the build."

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
# It opens compact; d shows the cost columns and the details strip. Insights
# opens first; close it, then vs ideal, Orphans, Instructions, Rules, Skills,
# Plugins: down six to Plugins, open it, down to acme, open that. xterm sends the
# arrows in keypad mode as ESC O <letter>. After the probe, a bare Esc leaves
# the right pane, and a second steps back to the view before the probe.
for keys in (b"d", b" ", b"jjjjjj", b" ", b"j", b"\n", b"j", b"s", b"\t", b"\x1bOD", b"g", b"p", b"deploy\n",
             b"\x1b", b"\x1b", b"q"):
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
print(("ok:" if "by artifact type" in text else "fail:") + "by type")
print(("ok:" if "at start" in text and "│ 200k" in text and "▏ 1M" in text else "fail:") + "meter")
print(("ok:" if "esc back" in text and "d details" in text else "fail:") + "compact keys")
print(("ok:" if "asking about \u201cdeploy\u201d" in text else "fail:") + "meter probe")
print(("ok:" if text.rfind("can load, by owner") > text.rfind("asking about \u201cdeploy\u201d") else "fail:") + "esc back")
print(("ok:" if "Insights (" in text and "Heaviest skill" in text else "fail:") + "insights")
print(("ok:" if "Orphans (3)" in text else "fail:") + "orphans")
print(("ok:" if all(c in text for c in ("Instructions", "Rules", "Plugins", "Hooks")) else "fail:") + "categories")
print(("ok:" if "acme:deploy" in text else "fail:") + "deploy")
# curses redraws only the cells that change, so the heading's new word arrives
# without the "by " it shares with the old one.
print(("ok:" if "owner" in text else "fail:") + "by owner")
print(("ok:" if "launch" in text and "unmeasured" in text else "fail:") + "footer")
print(("ok:" if all(c in text for c in ("spent", "+next", "~tokens")) else "fail:") + "token columns")
print(("ok:" if "deep" in text and "deepest path" in text and "every file" in text else "fail:") + "deep column")
print(("ok:" if " when" in text and "via" in text else "fail:") + "details strip")
print(("ok:" if "by distance" in text and "Loaded (1)" in text else "fail:") + "probe")
print(("ok:" if "On a trigger" not in text else "fail:") + "no trigger group for a term none of them mention")
print(("ok:" if "Remote sites (1)" in text else "fail:") + "sites")
print(("ok:" if "loaded files mention" in text else "fail:") + "probe summary")
PY
)"
contains "exits 0" "$tui" "exit 0"
contains "opens on the rollup by artifact type" "$tui" "ok:by type"
contains "under a meter of what loads at start, marked at the 200k and 1M windows" "$tui" "ok:meter"
contains "compact, naming the keys for back and for details" "$tui" "ok:compact keys"
contains "the meter adds what asking about a term opens" "$tui" "ok:meter probe"
contains "a bare Esc steps back to the view before the probe" "$tui" "ok:esc back"
contains "with the insights open at the top" "$tui" "ok:insights"
contains "and the orphans in a group of their own" "$tui" "ok:orphans"
contains "with a row per category" "$tui" "ok:categories"
contains "enter and space open a plugin to its roots" "$tui" "ok:deploy"
contains "g switches the rollup to owners" "$tui" "ok:by owner"
contains "draws the footer totals" "$tui" "ok:footer"
contains "costs in tokens: spent, this, +next, all" "$tui" "ok:token columns"
contains "launch, every file, and the deepest path, as the page reports them" "$tui" "ok:deep column"
contains "a strip saying when the selection loads and what opens it" "$tui" "ok:details strip"
contains "p probes for a term and rolls up by distance" "$tui" "ok:probe"
contains "with the roots waiting on a trigger apart from the loaded ones" "$tui" "ok:no trigger group for a term none of them mention"
contains "with the remote sites as a group" "$tui" "ok:sites"
contains "and the probe's summary in the footer" "$tui" "ok:probe summary"

echo "== g, or e directly, reaches a rollup of what a session reaches off the machine =="
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
# e jumps to the external rollup, g's fourth; d for the footer. Close
# Insights, and the host sits under vs ideal, Orphans, and the sites group.
for keys in (b"e", b"d", b" ", b"jjjj", b"q"):
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
print(("ok:" if "off the machine, by web address" in text else "fail:") + "title")
print(("ok:" if "Web addresses (1)" in text and "example.com" in text else "fail:") + "sites")
print(("ok:" if "1 host, 1 address named on 1 line of 1 file" in text else "fail:") + "footer")
print(("ok:" if "example.com: the file that sends a session there" in text else "fail:") + "right pane")
PY
)"
contains "exits 0" "$tui" "exit 0"
contains "titled for what leaves the machine" "$tui" "ok:title"
contains "a row per host, open from the start" "$tui" "ok:sites"
contains "the footer sums the hosts, addresses, lines, and files" "$tui" "ok:footer"
contains "a host's files fill the right pane" "$tui" "ok:right pane"

echo "== w opens what the terminal browser shows as a page =="
: > "$opened"
tui="$(BROWSER="$opener" python3 - "$CLEAT" "$REPO" <<'PY'
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
for keys in (b"p", b"deploy\n", b"w", b"q"):
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
print(("ok:" if "w page" in text else "fail:") + "key")
print(("ok:" if "wrote " in text and ".html (" in text else "fail:") + "notice")
PY
)"
contains "exits 0" "$tui" "exit 0"
contains "the key line offers w" "$tui" "ok:key"
contains "and the key line says what it wrote" "$tui" "ok:notice"
url="$(cat "$opened" 2>/dev/null)"
contains "w opens the page in the browser" "$url" "file://"
page_w="${url#file://}"
contains "with the browser's probe term" "$(cat "$page_w" 2>/dev/null)" '"probe":{"term":"deploy"'

echo "== the mouse picks panes and rows, and files are links =="
tui="$(python3 - "$CLEAT" "$REPO" <<'PY'
import os, pty, re, select, sys, time
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
def click(x, y, button=0):
    return "\x1b[<{};{};{}M".format(button, x + 1, y + 1).encode()
# Rows start on line 2, under the meter and the pane titles. A click on the
# picked row (Insights) closes it, which puts Plugins on line 8, under vs
# ideal and Orphans; a click picks
# it, a second opens it, and the same again opens acme below it. Then the wheel
# turns down and back up over the right pane, a click picks its top row, and
# the mouse's back button returns to the left pane.
for keys in (click(5, 2), click(5, 8), click(5, 8), click(5, 9), click(5, 9),
             click(60, 3, 65), click(60, 3, 64), click(60, 2), click(60, 2, 128), b"q"):
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
print(("ok:" if "\x1b[?1006h" in text else "fail:") + "mouse on")
print(("ok:" if text.rfind("\x1b[?1000l") > text.rfind("\x1b[?1006h") else "fail:") + "mouse off")
print(("ok:" if "acme:deploy" in text else "fail:") + "deploy")
links = re.findall(r"\x1b\]8;;(file://[^\x1b]+)\x1b\\([^\x1b]*)\x1b\]8;;\x1b\\", text)
print(("ok:" if any(t == "/acme:deploy" and u.endswith("/SKILL.md") for u, t in links) else "fail:") + "row links")
print(("ok:" if any(t.endswith("/") and u.endswith(t.rstrip("/").replace(" ", "%20")) for u, t in links) else "fail:") + "folder link")
PY
)"
contains "exits 0" "$tui" "exit 0"
contains "turns on the terminal's mouse reporting" "$tui" "ok:mouse on"
contains "and off again on quit" "$tui" "ok:mouse off"
contains "clicks pick and open rows down to a plugin's roots" "$tui" "ok:deploy"
contains "each file's name is a link to it" "$tui" "ok:row links"
contains "the file line links its folder" "$tui" "ok:folder link"

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

echo "== --settings lays a session's flag over the settings files =="
graph_json "$REPO" --settings '{"enabledPlugins": {"acme@market": false}}'
check "exits 0" "$GRAPH_EXIT" "0"
check "a plugin the flag turns off is left out" "$(q 'any(n["plugin"] == "acme" for n in g["nodes"])')" "False"
graph_json "$REPO" --settings '{"enabledPlugins": {"acme@market": ["1.0.0"]}}'
check "a version list keeps a plugin off, as Claude Code does" "$(q 'any(n["plugin"] == "acme" for n in g["nodes"])')" "False"
cp "$USER_DIR/settings.json" "$USER_DIR/settings.json.good"
write "$USER_DIR/settings.json" '{"enabledPlugins": {"acme@market": false}}\n'
SETTINGS_ON="$(mktemp "$TMP/cleat-settings.XXXXXX")"
write "$SETTINGS_ON" '{"enabledPlugins": {"acme@market": true},
 "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo bye"}]}]}}\n'
graph_json "$REPO" --settings "$SETTINGS_ON"
check "a file the flag names turns one on, as rig does" "$(q 'node("/acme:deploy")["plugin"]')" "acme"
check "and its hooks register under user scope" "$(q '(node("Stop echo bye")["scope"], node("Stop echo bye")["path"])')" "('user', '--settings')"
mv "$USER_DIR/settings.json.good" "$USER_DIR/settings.json"
out="$(python3 "$CLEAT" graph --json "$REPO" --settings '{ not json' 2>&1)"
check "an inline value that doesn't parse exits 2" "$?" "2"
contains "names the flag" "$out" "--settings does not parse"
out="$(python3 "$CLEAT" graph --json "$REPO" --settings "$TMP/cleat-no-such-settings.json" 2>&1)"
check "a file that isn't there exits 2" "$?" "2"
contains "names the file" "$out" "cleat-no-such-settings.json"

echo "== --returns marks what one session loaded =="
# A session's hook payloads, a JSON object a line: the startup file and its
# import, a rule a touched file pulled in, a skill the model invoked, one typed
# by its bare name, a built-in command, and a nested file nothing predicts.
R="$(cd "$REPO" && pwd -P)"
RETURNS="$(mktemp "$TMP/cleat-returns.XXXXXX")"
cat > "$RETURNS" <<EOF
{"ts": "2026-11-13T10:00:00Z", "session_id": "5e55-1", "hook_event_name": "InstructionsLoaded", "file_path": "$R/CLAUDE.md", "load_reason": "session_start", "memory_type": "Project"}
{"ts": "2026-11-13T10:00:00Z", "session_id": "5e55-1", "hook_event_name": "InstructionsLoaded", "file_path": "$R/AGENTS.md", "load_reason": "include", "parent_file_path": "$R/CLAUDE.md"}
{"ts": "2026-11-13T10:00:01Z", "session_id": "5e55-1", "hook_event_name": "SessionStart", "source": "startup"}

{"ts": "2026-11-13T10:01:00Z", "session_id": "5e55-1", "hook_event_name": "InstructionsLoaded", "file_path": "$R/.claude/rules/api.md", "load_reason": "path_glob_match", "trigger_file_path": "$R/src/app.ts", "globs": ["src/**/*.ts"]}
{"ts": "2026-11-13T10:02:00Z", "session_id": "5e55-1", "hook_event_name": "PostToolUse", "tool_name": "Skill", "tool_input": {"skill": "acme:deploy"}}
{"ts": "2026-11-13T10:03:00Z", "session_id": "5e55-1", "hook_event_name": "UserPromptSubmit", "prompt": "/verify the build"}
{"ts": "2026-11-13T10:04:00Z", "session_id": "5e55-1", "hook_event_name": "UserPromptSubmit", "prompt": "/clear"}
{"ts": "2026-11-13T10:05:00Z", "session_id": "5e55-1", "hook_event_name": "InstructionsLoaded", "file_path": "$R/src/CLAUDE.md", "load_reason": "nested_traversal"}
{"ts": "2026-11-13T10:06:00Z", "session_id": "5e55-1", "hook_event_name": "InstructionsLoaded", "file_path": "$R/CLAUDE.md", "load_reason": "compact"}
EOF
graph_json "$REPO" --returns "$RETURNS"
check "exits 0" "$GRAPH_EXIT" "0"
claude_id="$(q 'next(n["id"] for n in g["nodes"] if n["label"] == "CLAUDE.md" and n["scope"] == "repo")')"
check "the startup file returned at start, through its import, and after a compact" \
  "$(q 'next(n["returned"] for n in g["nodes"] if n["id"] == "'"$claude_id"'")["times"], next(n["returned"] for n in g["nodes"] if n["id"] == "'"$claude_id"'")["how"]')" \
  "(3, ['session_start', 'include', 'compact'])"
check "the rule returned on its path match" "$(q 'node(".claude/rules/api.md")["returned"]["how"]')" "['path_glob_match']"
check "an invoked skill returns as its body" \
  "$(q '[n["returned"]["how"] for n in g["nodes"] if n["id"].endswith("deploy/SKILL.md")]')" "[['Skill tool']]"
check "a typed bare name finds its one plugin skill" \
  "$(q '[n["returned"]["how"] for n in g["nodes"] if n["id"].endswith("verify/SKILL.md")]')" "[['typed']]"
check "a typed built-in is not a load, and a file no node holds is unexpected" \
  "$(q '[m["load"].rsplit("/", 2)[-2:] for m in g["returns"]["unexpected"]]')" "[['src', 'CLAUDE.md']]"
check "the import folds into the file importing it, as the walk folds its text" \
  "$(q 'any("AGENTS.md" in m["load"] for m in g["returns"]["unexpected"])')" "False"
check "every load counted, and the startup seen" "$(q '(g["returns"]["loads"], g["returns"]["startupObserved"], g["returns"]["session"])')" "(7, True, '5e55-1')"
check "an insight leads with the returns, Show narrowing to them" \
  "$(q '(g["insights"][0]["title"], g["insights"][0]["focus"]["type"], len(g["insights"][0]["focus"]["ids"]))')" \
  "('Returned this session: 4, 1 unexpected', 'set', 4)"
graph_json "$REPO" --returns "$RETURNS" --scope user
check "a filter keeps only the returns it shows" "$(q 'len(g["returns"]["returned"])')" "0"
grep -v session_start "$RETURNS" > "$RETURNS.late"
graph_json "$REPO" --returns "$RETURNS.late"
contains "a log with no startup load says the hook registered too late" "$(q 'g["insights"][0]["text"]')" "registered too late"
page="$(mktemp "$TMP/cleat-returns-page.XXXXXX").html"
python3 "$CLEAT" graph "$REPO" --returns "$RETURNS" --html "$page" 2>/dev/null
contains "the page carries each node's return" "$(cat "$page")" '"returned":{"times":3'
contains "and words it on the node's card" "$(cat "$page")" 'function returnedNote(mark)'
contains "with the returns insight" "$(cat "$page")" 'Returned this session: 4'
tui="$(python3 - "$CLEAT" "$REPO" "$RETURNS" <<'PY'
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["LINES"], os.environ["COLUMNS"] = "30", "160"
    os.execvp(sys.executable, [sys.executable, sys.argv[1], "graph", sys.argv[2], "--returns", sys.argv[3]])
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
# d shows the details strip; the returns insight is the first under Insights,
# and tab moves into the nodes it narrows to.
for keys in (b"d", b"j", b"\t", b"q"):
    drain(0.6)
    os.write(fd, keys)
drain(1.5)
os.waitpid(pid, 0)
text = seen.decode("utf-8", "replace")
print(("ok:" if "Returned this session: 4, 1 unexpected" in text else "fail:") + "insight")
print(("ok:" if "returned (" in text else "fail:") + "strip")
PY
)"
contains "the terminal lists the returns insight" "$tui" "ok:insight"
contains "and its details strip says how a node returned" "$tui" "ok:strip"
printf '{"hook_event_name": "InstructionsLoaded"}\n{ not json\n' > "$RETURNS.bad"
out="$(python3 "$CLEAT" graph --json "$REPO" --returns "$RETURNS.bad" 2>&1)"
check "a line that doesn't parse exits 2" "$?" "2"
contains "naming the line" "$out" "line 2 does not parse"
out="$(python3 "$CLEAT" graph --json "$REPO" --returns "$TMP/cleat-no-such-returns" 2>&1)"
check "a missing log exits 2" "$?" "2"
contains "naming it" "$out" "cleat-no-such-returns"

echo "== --measure-remote measures each web address, and the cache keeps it =="
SITE="$(mktemp -d "$TMP/cleat-site.XXXXXX")"
write "$SITE/page.html" '<html><head><title>t</title><style>p{}</style></head><body><p>Ten words of text on a page about releasing things.</p><script>x()</script></body></html>\n'
PORT_FILE="$SITE/port"
python3 - "$SITE" "$PORT_FILE" <<'PY' &
import functools, http.server, sys
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
open(sys.argv[2], "w").write(str(server.server_port))
server.serve_forever()
PY
SERVER=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$PORT_FILE" ] && break; python3 -c 'import time; time.sleep(0.2)'; done
PORT="$(cat "$PORT_FILE")"
WEB="$(mkrepo "CLAUDE.md:::$POINTER" "AGENTS.md:::# Web\n\nRelease notes: http://127.0.0.1:$PORT/page.html and http://127.0.0.1:$PORT/gone.html\n")"
measure_err="$(python3 "$CLEAT" graph --json --probe release --measure-remote --scope repo "$WEB" 2>&1 >"$GRAPH")"
kill "$SERVER"
check "the page's text, without markup, script, or style" \
  "$(q '[r.get("bytes") for r in node("CLAUDE.md")["remotes"] if r["url"].endswith("page.html")]')" "[51]"
check "an address that fails says why" \
  "$(q '[r.get("error") for r in node("CLAUDE.md")["remotes"] if r["url"].endswith("gone.html")]')" "['HTTP 404']"
contains "and stderr counts what was measured" "$measure_err" "measured 1 of 2 web addresses (0 already measured); 1 could not be measured: HTTP 404 ×1"
contains "and names the cache" "$measure_err" "$XDG_CACHE_HOME/cleat/remote.json"
graph_json --probe release "$WEB"
check "a later run reads the cache, with the server gone" \
  "$(q '[r.get("bytes") for r in node("CLAUDE.md")["remotes"] if r["url"].endswith("page.html")]')" "[51]"
check "the JSON carries the estimate an unmeasured address counts for, in bytes" "$(q 'g["remoteEstimate"]')" "5600.0"
python3 - "$XDG_CACHE_HOME/cleat/remote.json" <<'PY'
import datetime, json, sys
cache = json.load(open(sys.argv[1]))
for entry in cache.values():
    entry["fetched"] = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=31)).isoformat()
json.dump(cache, open(sys.argv[1], "w"))
PY
graph_json --probe release "$WEB"
check "a measurement older than 30 days is not used" \
  "$(q '[r.get("bytes") for r in node("CLAUDE.md")["remotes"] if r["url"].endswith("page.html")]')" "[None]"
printf '{ not json' > "$XDG_CACHE_HOME/cleat/remote.json"
out="$(python3 "$CLEAT" graph --json "$WEB" 2>&1)"
check "a cache that doesn't parse exits 2" "$?" "2"
contains "and names it" "$out" "remote.json does not parse"
rm "$XDG_CACHE_HOME/cleat/remote.json"

echo "== DIR defaults to the current directory =="
here="$(cd "$REPO" && python3 "$CLEAT" graph --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["directory"])')"
check "the repo it ran in" "$here" "$(cd "$REPO" && pwd -P)"

summary graph
