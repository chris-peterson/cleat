#!/usr/bin/env bash
# `cleat metrics`: a snapshot of the context graph's numbers, appended to a YAML
# history and printed.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

USER_DIR="$(mktemp -d "$TMP/cleat-user.XXXXXX")"
PLUGIN="$(mktemp -d "$TMP/cleat-plugin.XXXXXX")"
STATE="$(mktemp -d "$TMP/cleat-xdg.XXXXXX")"
export CLAUDE_CONFIG_DIR="$USER_DIR"
export XDG_STATE_HOME="$STATE"

write() {  # $1 path  $2 printf %b body
  mkdir -p "$(dirname "$1")"
  printf '%b' "$2" > "$1"
}

write "$USER_DIR/settings.json" '{"enabledPlugins": {"acme@market": true},
 "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "echo hello"}]}]}}\n'
write "$USER_DIR/plugins/installed_plugins.json" '{"version": 2, "plugins": {
 "acme@market": [{"scope": "user", "installPath": "'"$PLUGIN"'", "version": "1.2.3", "gitCommitSha": "abc123"}]}}\n'
write "$USER_DIR/CLAUDE.md" 'Plain words in every reply.\n'
write "$USER_DIR/rules/tone.md" 'Short sentences.\n'
write "$PLUGIN/.claude-plugin/plugin.json" '{"name": "acme"}\n'
write "$PLUGIN/skills/deploy/SKILL.md" '---\nname: deploy\ndescription: Ship the build.\n---\nRead `${CLAUDE_PLUGIN_ROOT}/guides/deploy.md` first.\n'
write "$PLUGIN/guides/deploy.md" 'Deploy in order. The edge cases are in more.md.\n'
write "$PLUGIN/guides/more.md" "Edge cases, at length. $(printf 'x%.0s' $(seq 1 4000))\n"

REPO="$(mkrepo "CLAUDE.md:::$POINTER" "AGENTS.md:::# Widget\n\nThe [design notes](docs/design.md) are here.\n" \
               "docs/design.md:::Design notes.\n")"

HISTORY="$(mktemp -u "$TMP/cleat-history.XXXXXX").yml"
OUT="$(mktemp "$TMP/cleat-out.XXXXXX")"
GRAPH="$(mktemp "$TMP/cleat-graph.XXXXXX")"
python3 "$CLEAT" graph --json "$REPO" > "$GRAPH"

metrics() {  # args to cleat metrics; stdout lands in $OUT, stderr in $ERR
  ERR="$(python3 "$CLEAT" metrics "$@" 2>&1 >"$OUT")"
  EXIT=$?
}

# q EXPR: evaluate EXPR with `h` the history parsed as a list of snapshots,
# `s` its last snapshot, `g` the graph's JSON, and `node(label)` a graph node.
# The reader covers the block subset cleat writes (maps, lists, JSON-quoted
# strings), so a line outside that subset fails the parse here.
q() {
  python3 - "$1" "$2" "$GRAPH" <<'PY'
import json, re, sys

def split_key(text):
    if text.startswith('"'):
        key, end = json.JSONDecoder().raw_decode(text)
        rest = text[end:]
    else:
        m = re.match(r"([\w-]+)(.*)\Z", text)
        if not m:
            return None
        key, rest = m.group(1), m.group(2)
        key = int(key) if key.isdigit() else key
    if rest == ":" or rest.startswith(": "):
        return key, rest[2:]
    return None

def parse(lines, i, indent):
    pad = " " * indent
    if lines[i].startswith(pad + "- "):
        out = []
        while i < len(lines) and lines[i].startswith(pad + "- "):
            body = lines[i][indent + 2:]
            if split_key(body) is None:
                out.append(json.loads(body))
                i += 1
            else:
                lines[i] = " " * (indent + 2) + body
                item, i = parse(lines, i, indent + 2)
                out.append(item)
        return out, i
    out = {}
    while i < len(lines) and lines[i].startswith(pad) and not lines[i].startswith(pad + " ") \
            and not lines[i].startswith(pad + "- "):
        key, rest = split_key(lines[i][indent:])
        if rest:
            out[key] = json.loads(rest)
            i += 1
        else:
            out[key], i = parse(lines, i + 1, indent + 2)
    return out, i

lines = open(sys.argv[1]).read().splitlines()
h, end = parse(lines, 0, 0)
assert end == len(lines), "unparsed from line {}: {!r}".format(end + 1, lines[end])
s = h[-1]
g = json.load(open(sys.argv[3]))
by_label = {n["label"]: n for n in g["nodes"]}
def node(label):
    return by_label[label]
print(eval(sys.argv[2]))
PY
}
qh() { q "$HISTORY" "$1"; }

echo "== a snapshot is appended to the history and printed =="
metrics "$REPO" --history "$HISTORY"
check "exits 0" "$EXIT" "0"
contains "names the history it appended to" "$ERR" "appended to $HISTORY"
check "stdout is the snapshot the history holds" "$(cat "$OUT")" "$(cat "$HISTORY")"
check "the history is a list of one snapshot" "$(qh 'len(h)')" "1"
metrics "$REPO" --history "$HISTORY"
check "a second run appends a second" "$(qh 'len(h)')" "2"

echo "== it carries the time, directory, commit, ratio, and totals =="
check "a UTC timestamp" "$(qh 's["at"].endswith("+00:00")')" "True"
check "the resolved directory" "$(qh 's["directory"] == g["directory"]')" "True"
check "no commit in a repo with none" "$(qh 's["commit"]')" "None"
check "the bytes-per-token ratio" "$(qh 's["bytesPerToken"] == g["bytesPerToken"]')" "True"
check "the GRAPH-18 totals" "$(qh 's["totals"] == g["totals"]')" "True"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -qm init
SHA="$(git -C "$REPO" rev-parse HEAD)"
metrics "$REPO" --history "$HISTORY"
check "HEAD once there is a commit" "$(qh 's["commit"]')" "$SHA"

echo "== per load tier =="
check "every tier, in order" "$(qh 'list(s["tiers"])')" \
  "['launch', 'on invoke', 'on path match', 'on read', 'on run', 'on event']"
check "each tier's bytes match the graph" \
  "$(qh 'all(s["tiers"][t]["bytes"] == sum(n["size"] for n in g["nodes"] if n["tier"] == t) for t in s["tiers"])')" "True"
check "the hook is an unmeasured node on event" "$(qh 's["tiers"]["on event"]')" \
  "{'nodes': 1, 'bytes': 0, 'unmeasured': 1}"

echo "== per hop count, along the path reach cost measures =="
check "hops from the skill's listing entry to the guide it reads, and on" \
  "$(qh 'sorted(s["hops"])')" "[0, 1, 2, 3]"
check "more.md is three hops out, alone" "$(qh 's["hops"][3]')" \
  "{'nodes': 1, 'bytes': $(qh 'node("guides/more.md")["size"]'), 'unmeasured': 0}"
check "every node is counted once" "$(qh 'sum(r["nodes"] for r in s["hops"].values()) == g["totals"]["nodes"]')" "True"

echo "== the depth curve, b50, b90, and the largest step =="
check "starts at 1,000 tokens and doubles" \
  "$(qh 'all(p["tokens"] == 1000 * 2 ** i for i, p in enumerate(s["curve"]))')" "True"
check "ends at the first budget at or past the deepest path" \
  "$(qh '(s["curve"][-1]["tokens"] * s["bytesPerToken"] >= s["totals"]["deepest"], len(s["curve"]) == 1 or s["curve"][-2]["tokens"] * s["bytesPerToken"] < s["totals"]["deepest"])')" \
  "(True, True)"
check "reaching every file at its end" "$(qh 's["curve"][-1]["bytes"] == s["totals"]["reachable"]')" "True"
check "each point sums the nodes within its budget" \
  "$(qh 'all(p["bytes"] == sum(n["size"] for n in g["nodes"] if (n["reach"] or 0) + n["size"] <= p["tokens"] * g["bytesPerToken"]) for p in s["curve"])')" "True"
check "b50 and b90 are the smallest depth costs holding half and 90%" \
  "$(qh '[min(c for c in ((n["reach"] or 0) + n["size"] for n in g["nodes"]) if sum(m["size"] for m in g["nodes"] if (m["reach"] or 0) + m["size"] <= c) >= share * g["totals"]["reachable"]) for share in (0.5, 0.9)] == [s["b50"], s["b90"]]')" "True"
check "the largest step is the largest file" \
  "$(qh 's["largestStep"] == {"path": node("guides/more.md")["id"], "bytes": node("guides/more.md")["size"]}')" "True"

echo "== per owner, with a plugin's version and a content digest =="
check "the GRAPH-18 totals per owner" \
  "$(qh 'all({k: o[k] for k in ("launch", "reachable", "deepest", "unmeasured", "nodes")} == {k: r[k] for k in ("launch", "reachable", "deepest", "unmeasured", "nodes")} for o, r in zip(s["owners"], g["owners"]))')" "True"
check "the plugin's install record" \
  "$(qh '[(o["version"], o["commit"]) for o in s["owners"] if o["owner"] == "acme@market"]')" "[('1.2.3', 'abc123')]"
check "only a plugin carries a version" "$(qh 'sorted(o["owner"] for o in s["owners"] if "version" in o)')" "['acme@market']"
write "$PLUGIN/guides/deploy.md" 'Deploy in a different order.\n'
metrics "$REPO" --history "$HISTORY"
check "editing a plugin file changes that owner's digest alone" \
  "$(qh '[o["owner"] for o, p in zip(h[-1]["owners"], h[-2]["owners"]) if o["digest"] != p["digest"]]')" "['acme@market']"

echo "== the default history is under XDG_STATE_HOME =="
metrics "$REPO"
check "exits 0" "$EXIT" "0"
check "writes the default path" "$(cat "$OUT")" "$(cat "$STATE/cleat/metrics.yml")"

echo "== failures exit 2 and append nothing =="
BEFORE="$(cat "$HISTORY")"
metrics "$REPO" --history "$STATE"
check "a history that can't be written exits 2" "$EXIT" "2"
contains "and names it" "$ERR" "cannot write the metrics history $STATE"
check "with nothing on stdout" "$(cat "$OUT")" ""
cp "$USER_DIR/settings.json" "$USER_DIR/settings.json.good"
write "$USER_DIR/settings.json" '{not json\n'
metrics "$REPO" --history "$HISTORY"
check "a settings file that doesn't parse exits 2" "$EXIT" "2"
contains "and names it" "$ERR" "does not parse"
check "leaving the history as it was" "$(cat "$HISTORY")" "$BEFORE"
mv "$USER_DIR/settings.json.good" "$USER_DIR/settings.json"
metrics "$REPO/nope" --history "$HISTORY"
check "a missing directory exits 2" "$EXIT" "2"

summary "metrics"
