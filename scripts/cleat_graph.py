"""`cleat graph`: the context graph a session can load, and its costs.

Imported by `scripts/cleat` for the graph command alone, so a hook never parses
it. The helpers it shares with `cleat cost` arrive as the `cleat` module itself.
"""
from __future__ import annotations

import hashlib
import heapq
import json
import os
import pathlib
import re
import sys
import tempfile
import textwrap
import webbrowser

LAUNCH, INVOKE, PATH, READ, RUN, EVENT = (
    "launch", "on invoke", "on path match", "on read", "on run", "on event")
TIERS = (LAUNCH, INVOKE, PATH, READ, RUN, EVENT)
SCOPES = ("repo", "user", "plugin")
# Sizes are kept in bytes and shown in tokens. Measured against Claude Code's
# /context on instruction files, markdown runs 2.5 to 2.9 bytes per token.
BYTES_PER_TOKEN = 2.8

SCRIPT_SUFFIXES = {".sh", ".bash", ".zsh", ".py", ".js", ".mjs", ".cjs", ".ts",
                   ".rb", ".pl", ".ps1"}
# Files whose text reaches the agent when read, and whose own references are
# followed in turn. A data file a page names (a cache, a settings file) is
# what a script reads, so naming one is no read edge.
TEXT_SUFFIXES = {".md", ".markdown", ".txt", ".mdx"}
READ_SUFFIXES = TEXT_SUFFIXES

URL = re.compile(r"\b[a-z][a-z0-9+.-]*://\S+", re.I)
# A path as prose, a link, or a command states one: an optional variable or ~
# prefix, segments, and a file extension. Whether it names anything is settled
# by whether it resolves to a file.
PATH_REF = re.compile(
    r"(?<![\w@.$/~-])"
    r"((?:\$\{CLAUDE_PLUGIN_ROOT\}|\$\{CLAUDE_SKILL_DIR\}|\$CLAUDE_PLUGIN_ROOT|~)?"
    r"/?(?:\.{1,2}/)*[\w.+-]+(?:/[\w.+-]+)*\.[A-Za-z][A-Za-z0-9]*)")
SLASH_NAME = re.compile(r"(?<![\w./:-])/([\w-]+(?::[\w-]+)*)(?![\w/-]|\.\w)")
QUALIFIED_NAME = re.compile(r"(?<![\w/.:-])([\w-]+(?::[\w-]+)+)(?![\w/:-]|\.\w)")


class Graph:
    def __init__(self):
        self.nodes = {}
        self.edges = set()
        # (source, target, kind) -> where the source names the target: the
        # file, its line, and the line's text. The first mention wins.
        self.refs = {}

    def node(self, id, **attrs):
        if id not in self.nodes:
            attrs.setdefault("measured", True)
            attrs.setdefault("root", False)
            self.nodes[id] = dict(id=id, **attrs)
        return self.nodes[id]

    def edge(self, source, target, kind, ref=None):
        if source != target:
            self.edges.add((source, target, kind))
            if ref and (source, target, kind) not in self.refs:
                self.refs[(source, target, kind)] = ref


# ---- inputs ----------------------------------------------------------------

def config_dir():
    """Where Claude Code keeps user scope: `$CLAUDE_CONFIG_DIR`, else ~/.claude."""
    return pathlib.Path(os.environ.get("CLAUDE_CONFIG_DIR")
                        or pathlib.Path.home() / ".claude")


def _json_file(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except ValueError as exc:
        raise RuntimeError("{} does not parse: {}".format(path, exc)) from exc
    except OSError as exc:
        raise RuntimeError("cannot read {}: {}".format(path, exc)) from exc


def settings_files(root, user):
    """The settings Claude Code merges, lowest precedence first."""
    return [(path, scope) for path, scope in (
        (user / "settings.json", "user"),
        (root / ".claude" / "settings.json", "repo"),
        (root / ".claude" / "settings.local.json", "repo"),
    ) if path.is_file()]


def enabled_plugins(root, user):
    """[(key, install path)] for each plugin the merged settings enable."""
    enabled = {}
    for path, _scope in settings_files(root, user):
        enabled.update(_json_file(path).get("enabledPlugins") or {})
    keys = sorted(key for key, on in enabled.items() if on)
    if not keys:
        return []
    record = user / "plugins" / "installed_plugins.json"
    if not record.is_file():
        raise RuntimeError("{} plugins are enabled but {} is missing".format(
            len(keys), record))
    installed = _json_file(record).get("plugins") or {}
    resolved_root = str(root.resolve())
    out = []
    for key in keys:
        records = installed.get(key) or []
        chosen = next((r for r in records if r.get("scope") != "user"
                       and r.get("projectPath") == resolved_root), None)
        chosen = chosen or next((r for r in records if r.get("scope") == "user"), None)
        if chosen is None:
            raise RuntimeError("enabled plugin {} has no install record in {}".format(
                key, record))
        path = pathlib.Path(chosen.get("installPath", ""))
        if not path.is_dir():
            raise RuntimeError("enabled plugin {} is installed at {}, which is missing"
                               .format(key, path))
        out.append((key, path))
    return out


# ---- the walk --------------------------------------------------------------

class Scope:
    """Where a set of skills, rules, and instructions lives, and what its names
    and nodes are labeled with."""

    def __init__(self, kind, base, plugin=None, marketplace=None):
        self.kind, self.base = kind, base
        self.plugin, self.marketplace = plugin, marketplace

    def attrs(self):
        return {"scope": self.kind, "plugin": self.plugin, "marketplace": self.marketplace}

    def qualified(self, name):
        return "{}:{}".format(self.plugin, name) if self.plugin else name


def _manifest_dirs(base, manifest, field, default):
    dirs = [base / default]
    declared = manifest.get(field)
    for entry in ([declared] if isinstance(declared, str) else declared or []):
        if isinstance(entry, str):
            dirs.append(base / entry)
    seen, out = set(), []
    for d in dirs:
        r = d.resolve()
        if r not in seen and d.is_dir():
            seen.add(r)
            out.append(d)
    return out


class Walker:
    def __init__(self, h, root):
        self.h = h
        self.root = root.resolve()
        self.user = config_dir()
        self.g = Graph()
        self.texts = {}           # node id -> [(path, text)] to scan
        self.names = {}           # invocable name -> [body node id]
        self.locations = []       # (resolved base, Scope), most specific first
        self.pending = []
        self.raw = {}

    # -- locating ------------------------------------------------------------

    def scope_of(self, path):
        text = str(path)
        for base, scope in self.locations:
            if text == base or text.startswith(base + os.sep):
                return scope
        return Scope("other", pathlib.Path("/"))

    def label(self, path, scope):
        if scope.kind != "other":
            return path.relative_to(scope.base.resolve()).as_posix()
        home = str(pathlib.Path.home())
        text = str(path)
        return "~" + text[len(home):] if text.startswith(home + os.sep) else text

    # -- nodes ---------------------------------------------------------------

    def file_node(self, path, tier, kind, scope=None, size=None, measured=True,
                  root=False, texts=None):
        path = path.resolve()
        id = str(path)
        scope = scope or self.scope_of(path)
        if id in self.g.nodes:
            return id
        if texts is None and measured:
            text = self.h._read(path)
            texts = [(path, text)]
        if size is None:
            size = sum(len(t.encode("utf-8")) for _p, t in texts) if measured else 0
        node = self.g.node(id, label=self.label(path, scope), path=str(path), kind=kind,
                           tier=tier, size=size, measured=measured, root=root, **scope.attrs())
        if measured:
            node["digest"] = hashlib.sha256(
                "".join(text for _p, text in texts).encode("utf-8")).hexdigest()[:16]
        if texts is not None and path.suffix.lower() in TEXT_SUFFIXES | {""}:
            self.texts[id] = texts
            self.pending.append(id)
        return id

    def instructions(self, starts, scope):
        """A launch node per instruction file, its imports folded into it, since
        Claude Code loads them together."""
        for start in starts:
            texts, seen = [], set()
            queue = [(start, 0)]
            while queue:
                path, hops = queue.pop(0)
                if path.resolve() in seen:
                    continue
                seen.add(path.resolve())
                text = self.h._as_loaded(self.h._read(path))
                texts.append((path, text))
                if hops < self.h.IMPORT_MAX_HOPS:
                    queue.extend((t, hops + 1) for t in self.h._imports(path, text))
            id = self.file_node(start, LAUNCH, "instructions", scope, root=True, texts=texts)
            self.g.nodes[id]["when"] = "every session, at launch"

    def rules(self, base, scope):
        if not base.is_dir():
            return
        for path in sorted(base.rglob("*.md")):
            text = self.h._read(path)
            _fields, body = self.h._frontmatter(text)
            globs = self.h._rule_globs(text)
            id = self.file_node(path, LAUNCH if globs is None else PATH, "rule", scope,
                                root=True, texts=[(path, body)])
            if globs is None:
                self.g.nodes[id]["when"] = "every session, at launch"
            elif self.retired(globs):
                self.g.nodes[id].update(
                    when="never here: no file under {} matches {}".format(
                        self.root.name, ", ".join(globs)),
                    trigger="retired")
            else:
                self.g.nodes[id].update(
                    when="when a file matching {} is read, written, or edited".format(
                        ", ".join(globs)),
                    trigger=", ".join(globs))

    def retired(self, globs):
        """Whether these globs match no file under the session's directory, the
        test `cleat check` classifies a retired rule by. Globs it can't
        evaluate count as live: the check reports those as bad-glob."""
        patterns, problem = self.h._expanded(globs)
        return not problem and not self.h._matches_any_file(self.root, patterns)

    def invocable(self, path, name, kind, scope):
        """A listing entry and the body it opens. A typed-only or path-scoped
        skill keeps its entry out of the listing until it is needed."""
        text = self.h._read(path)
        fields, body = self.h._frontmatter(text)
        qualified = scope.qualified(name)
        body_id = self.file_node(path, INVOKE, kind, scope, texts=[(path, body)])
        self.g.nodes[body_id]["when"] = "when /{} is invoked".format(qualified)
        self.names.setdefault(qualified, []).append(body_id)
        globs = self.h._rule_globs(text) if kind == "skill" else None
        trigger = None
        if fields.get("disable-model-invocation") == "true":
            tier, size, note = LAUNCH, 0, "typed only"
            when, trigger = "only when you type /{}".format(qualified), "typed only"
        elif globs:
            tier, note = PATH, "paths: " + ", ".join(globs)
            size = len(self.h._listing_entry(qualified, fields, body).encode("utf-8")) + 1
            if self.retired(globs):
                when = "never listed here: no file under {} matches {}".format(
                    self.root.name, ", ".join(globs))
                trigger = "retired"
            else:
                when = "listed once a file matching {} is touched".format(", ".join(globs))
                trigger = ", ".join(globs)
        else:
            tier, note = LAUNCH, ""
            size = len(self.h._listing_entry(qualified, fields, body).encode("utf-8")) + 1
            when = "listed at launch; the body loads when the model or you invoke it"
        entry = "entry:{}:{}:{}".format(scope.kind, scope.plugin or "", qualified)
        self.g.node(entry, label="/" + qualified, path=str(path.resolve()), kind="entry",
                    tier=tier, size=size, root=True, note=note, when=when, **scope.attrs())
        if trigger:
            self.g.nodes[entry]["trigger"] = trigger
        self.g.edge(entry, body_id, "invoke")

    def components(self, base, scope, manifest=None):
        manifest = manifest or {}
        for skills in _manifest_dirs(base, manifest, "skills", "skills"):
            for path in sorted(skills.glob("*/SKILL.md")):
                fields, _ = self.h._frontmatter(self.h._read(path))
                self.invocable(path, fields.get("name") or path.parent.name, "skill", scope)
        for commands in _manifest_dirs(base, manifest, "commands", "commands"):
            for path in sorted(commands.rglob("*.md")):
                name = path.relative_to(commands).with_suffix("").as_posix().replace("/", ":")
                self.invocable(path, name, "command", scope)
        for agents in _manifest_dirs(base, manifest, "agents", "agents"):
            for path in sorted(agents.glob("*.md")):
                fields, _ = self.h._frontmatter(self.h._read(path))
                self.invocable(path, fields.get("name") or path.stem, "agent", scope)

    def hooks(self, registrations, source, scope):
        for event, groups in sorted((registrations or {}).items()):
            for group in groups or []:
                matcher = group.get("matcher") or ""
                for hook in group.get("hooks") or []:
                    command = hook.get("command") or hook.get("prompt") or hook.get("type", "")
                    id = "hook:{}:{}:{}:{}".format(source, event, matcher, command)
                    label = "{}{} {}".format(event, "[{}]".format(matcher) if matcher else "",
                                             _short(command))
                    self.g.node(id, label=label, path=str(source), kind="hook", tier=EVENT,
                                size=0, measured=False, root=True, note=command,
                                when="on {}{}".format(event, " for {}".format(matcher)
                                                      if matcher else ""),
                                **scope.attrs())
                    if matcher:
                        self.g.nodes[id]["trigger"] = matcher

    # -- references ----------------------------------------------------------

    def resolve(self, token, holder, scope):
        """The file a path token names, or None."""
        candidates = []
        if token.startswith(("${CLAUDE_PLUGIN_ROOT}", "$CLAUDE_PLUGIN_ROOT")):
            rest = token.split("}", 1)[1] if token.startswith("${") else token[len("$CLAUDE_PLUGIN_ROOT"):]
            candidates.append(scope.base / rest.lstrip("/"))
        elif token.startswith("${CLAUDE_SKILL_DIR}"):
            candidates.append(holder.parent / token.split("}", 1)[1].lstrip("/"))
        elif token.startswith("~"):
            candidates.append(pathlib.Path(os.path.expanduser(token)))
        elif token.startswith("/"):
            candidates += [pathlib.Path(token), scope.base / token.lstrip("/")]
        else:
            candidates.append(holder.parent / token)
            if "/" in token:
                candidates.append(scope.base / token)
        for candidate in candidates:
            try:
                if candidate.is_file():
                    return candidate
            except OSError:
                continue
        return None

    def ref(self, holder, text, offset):
        """Where a reference sits: the holder's label, the line number in the
        file on disk, and that line's text. The text scanned may have lost its
        frontmatter or comments, so the line is found again in the raw file."""
        start = text.rfind("\n", 0, offset) + 1
        end = text.find("\n", offset)
        full = text[start:end if end >= 0 else len(text)]
        line = full.strip()
        raw = self.raw.get(holder)
        if raw is None:
            raw = self.raw[holder] = self.h._read(holder).splitlines()
        number = next((i + 1 for i, each in enumerate(raw) if each.strip() == line), None)
        holder = holder.resolve()
        # A long line is cut to a window around the reference, so it stays in view.
        at = offset - start - (len(full) - len(full.lstrip()))
        if len(line) > 160:
            lo = max(0, min(at - 60, len(line) - 160))
            line = ("…" if lo else "") + line[lo:lo + 160] + ("…" if lo + 160 < len(line) else "")
        return {"file": self.label(holder, self.scope_of(holder)), "line": number, "text": line}

    def scan(self, id):
        node = self.g.nodes[id]
        scope = self.scope_of(pathlib.Path(node["path"]))
        for holder, original in self.texts.pop(id):
            # Blank out URLs at their own length, so an offset into the scanned
            # text is the same offset into the original.
            text = URL.sub(lambda m: " " * len(m.group(0)), original)
            for match in PATH_REF.finditer(text):
                target = self.resolve(match.group(1), holder, scope)
                if target is None or target.resolve() == holder.resolve():
                    continue
                suffix = target.suffix.lower()
                if suffix in SCRIPT_SUFFIXES or (suffix not in READ_SUFFIXES
                                                 and os.access(target, os.X_OK)):
                    to = self.file_node(target, RUN, "script", measured=False)
                    self.g.nodes[to].setdefault("when", "when a file that names it says to run it")
                    self.g.edge(id, to, "run", self.ref(holder, original, match.start()))
                elif suffix in READ_SUFFIXES:
                    to = self.file_node(target, READ, "file")
                    self.g.nodes[to].setdefault("when", "when the agent follows a reference to it")
                    self.g.edge(id, to, "read", self.ref(holder, original, match.start()))
            for pattern in (SLASH_NAME, QUALIFIED_NAME):
                for match in pattern.finditer(text):
                    for body in self.names.get(match.group(1), ()):
                        self.g.edge(id, body, "invoke", self.ref(holder, original, match.start()))

    # -- driver --------------------------------------------------------------

    def walk(self):
        h, root, user = self.h, self.root, self.user
        plugins = enabled_plugins(root, user)
        plugin_scopes = []
        for key, base in plugins:
            name, _, market = key.partition("@")
            scope = Scope("plugin", base, name, market or None)
            plugin_scopes.append((base, scope))
            self.locations.append((str(base.resolve()), scope))
        repo, home = Scope("repo", root), Scope("user", user)
        # Most specific first: a plugin's cache sits under user scope.
        self.locations.sort(key=lambda pair: -len(pair[0]))
        self.locations += sorted([(str(root), repo), (str(user.resolve()), home)],
                                 key=lambda pair: -len(pair[0]))

        starts = [root / name for name in h.CLAUDE_FAMILY if (root / name).is_file()]
        if not starts and (root / h.AGENTS).is_file() and h._shadowing(root) is None:
            starts = [root / h.AGENTS]
        self.instructions(starts, repo)
        self.rules(root / h.RULES_DIR, repo)
        self.components(root / ".claude", repo)

        if (user / h.CLAUDE).is_file():
            self.instructions([user / h.CLAUDE], home)
        self.rules(user / "rules", home)
        self.components(user, home)

        for base, scope in plugin_scopes:
            manifest_path = base / ".claude-plugin" / "plugin.json"
            manifest = _json_file(manifest_path) if manifest_path.is_file() else {}
            self.components(base, scope, manifest)
            declared = manifest.get("hooks")
            if isinstance(declared, dict):
                self.hooks(declared.get("hooks", declared), manifest_path, scope)
            hooks_file = base / declared if isinstance(declared, str) else base / "hooks" / "hooks.json"
            if hooks_file.is_file():
                self.hooks(_json_file(hooks_file).get("hooks"), hooks_file, scope)

        for path, kind in settings_files(root, user):
            self.hooks(_json_file(path).get("hooks"), path, repo if kind == "repo" else home)

        while self.pending:
            self.scan(self.pending.pop())
        return self.g


def _short(command, limit=48):
    command = " ".join(str(command).split())
    for prefix in ("${CLAUDE_PLUGIN_ROOT}/", "$CLAUDE_PLUGIN_ROOT/"):
        command = command.replace(prefix, "")
    return command if len(command) <= limit else command[:limit - 1] + "…"


# ---- costs -----------------------------------------------------------------

def compute_costs(g):
    """Reach cost (cheapest path from a root, node excluded) with the node it is
    reached through; next cost (what opening it one level adds: the direct
    children it pulls in); and closure cost (node plus everything it pulls in, each once)
    with the unmeasured nodes that closure includes. `g.pulled` keeps each
    closure's members, which a rollup unions."""
    out, pulls = {}, {}
    for source, target, kind in g.edges:
        out.setdefault(source, set()).add(target)
        # A body naming another skill hands off to that skill's own root, which
        # carries its cost; folding it in here would give every skill that
        # mentions a popular one the same closure.
        if kind != "invoke" or g.nodes[source]["kind"] == "entry":
            pulls.setdefault(source, set()).add(target)
    size = {id: n["size"] for id, n in g.nodes.items()}

    reach, via = {}, {}
    heap = [(0, id) for id, n in g.nodes.items() if n["root"]]
    heapq.heapify(heap)
    while heap:
        cost, id = heapq.heappop(heap)
        if id in reach:
            continue
        reach[id] = cost
        for target in out.get(id, ()):
            if target not in reach:
                step = cost + size[id]
                if step < via.get(target, (float("inf"),))[0]:
                    via[target] = (step, id)
                    heapq.heappush(heap, (step, target))

    g.pulled = {}
    for id, node in g.nodes.items():
        seen, stack = {id}, [id]
        while stack:
            for target in pulls.get(stack.pop(), ()):
                if target not in seen:
                    seen.add(target)
                    stack.append(target)
        g.pulled[id] = frozenset(seen)
        node["closure"] = sum(size[n] for n in seen)
        node["next"] = sum(size[n] for n in pulls.get(id, ()))
        node["closureUnmeasured"] = sum(1 for n in seen if not g.nodes[n]["measured"])
        node["reach"] = reach.get(id)
        node["via"] = via[id][1] if id in via and not node["root"] else None
        node["children"] = sorted(out.get(id, ()))


def depth_cost(node):
    """What a session spends to have this file open, down the cheapest path:
    everything read before it, and the file itself."""
    return (node["reach"] or 0) + node["size"]


def totals(nodes):
    """The three measures every view reports: what launch costs, what opening
    every file would cost (breadth), and what the deepest single path costs
    (depth). A session walks one path at a time, so it never pays the breadth."""
    nodes = list(nodes)
    return {
        "launch": sum(n["size"] for n in nodes if n["tier"] == LAUNCH),
        "reachable": sum(n["size"] for n in nodes),
        "deepest": max((depth_cost(n) for n in nodes), default=0),
        "unmeasured": sum(1 for n in nodes if not n["measured"]),
        "nodes": len(nodes),
    }


def owners(nodes):
    """The totals per owner (this repo, user scope, each plugin), largest
    first: the universe's wedges and the terminal's owner rollup."""
    by_owner = {}
    for n in nodes.values():
        by_owner.setdefault(owner_label(n), []).append(n)
    rows = []
    for name, members in by_owner.items():
        first = members[0]
        rows.append(dict(owner=name, scope=first["scope"], plugin=first["plugin"],
                         marketplace=first["marketplace"], **totals(members)))
    return sorted(rows, key=lambda row: -row["reachable"])


def build(h, root):
    g = Walker(h, pathlib.Path(root)).walk()
    compute_costs(g)
    return g


# ---- filters ---------------------------------------------------------------

FILTER_FIELDS = (("marketplace", "marketplace"), ("plugin", "plugin"),
                 ("scope", "scope"), ("tier", "tier"))


def matches(node, filters):
    return all(node.get(field) in wanted
               for field, wanted in filters.items() if wanted)


def filtered(g, filters):
    """Nodes matching every filter given, and the edges between them. Costs were
    computed over the whole graph, so they don't move."""
    nodes = {id: n for id, n in g.nodes.items() if matches(n, filters)}
    edges = sorted((s, t, k) for s, t, k in g.edges if s in nodes and t in nodes)
    return nodes, edges


def as_json(root, g, nodes, edges, filters):
    public = [{k: v for k, v in n.items() if k != "children"}
              for n in sorted(nodes.values(), key=lambda n: n["id"])]
    return {
        "directory": str(root),
        "bytesPerToken": BYTES_PER_TOKEN,
        "filters": {k: sorted(v) for k, v in filters.items() if v},
        "totals": totals(nodes.values()),
        "owners": owners(nodes),
        "insights": insights(g, nodes),
        "nodes": public,
        "edges": [dict({"source": s, "target": t, "kind": k}, **g.refs.get((s, t, k), {}))
                  for s, t, k in edges],
    }


# ---- insights --------------------------------------------------------------

def _insight(title, text, query, ids, label=None):
    """graph-explorer's shape: a finding, how it was computed, and what Show
    narrows the view to, plus a short title for a list row."""
    ids = list(dict.fromkeys(ids))
    focus = ({"type": "node", "id": ids[0]} if len(ids) == 1 and label is None
             else {"type": "set", "ids": ids, "label": label or text})
    return {"title": title, "text": text, "query": query, "focus": focus}


def insights(g, nodes):
    """Findings over the nodes shown, each emitted only where the data has one."""
    out = []
    measured = [n for n in nodes.values() if n["measured"]]
    roots = [n for n in nodes.values() if n["root"]]
    entries = [n for n in roots if n["kind"] == "entry"]

    launch = [n for n in nodes.values() if n["tier"] == LAUNCH and n["size"]]
    launch_total = sum(n["size"] for n in launch)
    if launch_total:
        by_category = {}
        for n in launch:
            by_category.setdefault(category(n), []).append(n)
        name, members = max(by_category.items(), key=lambda kv: sum(n["size"] for n in kv[1]))
        share = sum(n["size"] for n in members)
        out.append(_insight(
            "Launch: {} {:.0%}".format(dict(CATEGORIES)[name].split("  ")[0].lower(),
                                       share / launch_total),
            "{} are ~{} of the ~{} tokens every session loads at launch ({:.0%}).".format(
                dict(CATEGORIES)[name].split("  ")[0], tokens(share), tokens(launch_total),
                share / launch_total),
            "launch-tier sizes summed by artifact type; the largest type",
            [n["id"] for n in sorted(members, key=lambda n: -n["size"])],
            label="{} loaded at launch".format(dict(CATEGORIES)[name].split("  ")[0])))

    if entries:
        top = max(entries, key=lambda n: n["closure"])
        if top["closure"]:
            out.append(_insight(
                "Heaviest skill: {}".format(top["label"]),
                "Invoking {} adds ~{} tokens up front and ~{} with everything it reads.".format(
                    top["label"], tokens(top["next"]), tokens(top["closure"])),
                "the listing entry with the largest closure; up front is its next cost",
                [top["id"]]))

    reached = {}
    for root in roots:
        for id in g.pulled[root["id"]] & nodes.keys():
            if id != root["id"]:
                reached.setdefault(id, set()).add(root["id"])
    hubs = [(nodes[id], by) for id, by in reached.items()
            if len(by) > 1 and nodes[id]["measured"] and nodes[id]["size"]]
    if hubs:
        hub, by = max(hubs, key=lambda h: h[0]["size"] * len(h[1]))
        out.append(_insight(
            "Shared file: {}".format(hub["label"].rsplit("/", 1)[-1]),
            "{} (~{} tokens) is pulled in by {} roots; trimming it helps each of them.".format(
                hub["label"], tokens(hub["size"]), len(by)),
            "files in more than one root's closure, ranked by size times roots",
            [hub["id"]] + sorted(by, key=lambda id: -nodes[id]["closure"]),
            label="{} and the roots that pull it in".format(hub["label"])))

    files = [n for n in measured if not n["root"]]
    if files:
        big = max(files, key=lambda n: n["size"])
        out.append(_insight(
            "Largest file: {}".format(big["label"].rsplit("/", 1)[-1]),
            "The largest file any path opens is {} at ~{} tokens.".format(
                big["label"], tokens(big["size"])),
            "the measured non-root node with the largest size", [big["id"]]))
        deep = max(files, key=lambda n: n["reach"] or 0)
        if deep["reach"]:
            out.append(_insight(
                "Deepest read: {}".format(deep["label"].rsplit("/", 1)[-1]),
                "Reading {} needs ~{} tokens already spent on the cheapest path to it.".format(
                    deep["label"], tokens(deep["reach"])),
                "the largest reach cost", [deep["id"]]))

    copies = {}
    for n in measured:
        if n["size"] and n.get("digest"):
            copies.setdefault(n["digest"], []).append(n)
    groups = [grp for grp in copies.values() if len(grp) > 1]
    if groups:
        wasted = sum(grp[0]["size"] * (len(grp) - 1) for grp in groups)
        ids = [n["id"] for grp in sorted(groups, key=lambda grp: -grp[0]["size"]) for n in grp]
        out.append(_insight(
            "Duplicate files: {}".format(sum(len(grp) - 1 for grp in groups)),
            "{} files are byte-identical copies of another reachable file, ~{} tokens "
            "a session could read twice.".format(
                sum(len(grp) - 1 for grp in groups), tokens(wasted)),
            "measured nodes sharing a content digest", ids, label="identical copies"))

    typed_only = {}
    for entry in entries:
        if entry.get("note") == "typed only":
            for body in entry["children"]:
                typed_only[body] = entry
    # Docs, changelogs, and a typed-only skill's own files name the command for
    # the person typing it. A call the model can't make comes from another
    # skill, command, or agent body.
    broken = [(source, target) for source, target, kind in g.edges
              if kind == "invoke" and target in typed_only and source in nodes
              and target in nodes and nodes[source]["kind"] in ("skill", "command", "agent")
              and source not in g.pulled[typed_only[target]["id"]]]
    if broken:
        source, target = broken[0]
        out.append(_insight(
            "Typed-only mentions: {}".format(len(broken)),
            "{} names {}, which is typed-only: where a body means to call it, the "
            "model can't{}.".format(
                nodes[source]["label"], typed_only[target]["label"],
                "" if len(broken) == 1 else " ({} such mentions)".format(len(broken))),
            "skill, command, and agent bodies naming a skill with "
            "disable-model-invocation: true, outside that skill's own files",
            [id for pair in broken for id in pair], label="mentions of typed-only skills"))

    starts = [n for n in roots if n["kind"] == "hook" and n["label"].startswith("SessionStart")]
    if starts:
        out.append(_insight(
            "Unsized at launch: {} hook{}".format(len(starts), "" if len(starts) == 1 else "s"),
            "{} SessionStart hook{} add output at every launch that cleat can't size; "
            "/context counts it.".format(len(starts), "" if len(starts) == 1 else "s"),
            "hook registrations on SessionStart", [n["id"] for n in starts],
            label="SessionStart hooks"))
    return out


# ---- the page --------------------------------------------------------------

PAGE = pathlib.Path(__file__).resolve().parent / "cleat_graph.html"


def render_html(data):
    template = PAGE.read_text(encoding="utf-8")
    payload = json.dumps(data, separators=(",", ":")).replace("</", "<\\/")
    if "/*GRAPH*/null" not in template:
        raise RuntimeError("{} has no /*GRAPH*/null placeholder".format(PAGE))
    return template.replace("/*GRAPH*/null", payload, 1)


# ---- the terminal browser --------------------------------------------------

SORTS = ("closure", "next", "size", "reach")
SORT_LABELS = {"closure": "all", "next": "+next", "size": "this", "reach": "spent"}

# The left pane's default rollup: what kind of artifact each root is, with
# plugins one level deeper so each plugin's total reads at a glance.
CATEGORIES = (
    ("instructions", "Instructions  CLAUDE.md, AGENTS.md"),
    ("rules", "Rules"),
    ("skills", "Skills, commands, agents"),
    ("plugins", "Plugins"),
    ("hooks", "Hooks"),
)
GROUPINGS = ("type", "owner")
# The left pane's first group, open from the start: the findings come before the
# tree they were computed from.
INSIGHTS = "insights"

# A hotspot is absolute, not relative to the screen, so a color means the same
# cost in either pane and on the page.
HEAT_TOKENS = (1_000, 4_000, 10_000, 30_000, 70_000)
HEAT_GLYPHS = ("·", "▁", "▃", "▅", "▇", "█")
HEAT_256 = (245, 142, 178, 208, 202, 196)


def heat_level(size):
    return sum(1 for limit in HEAT_TOKENS if (size or 0) / BYTES_PER_TOKEN >= limit)


def tokens(size):
    """A byte count as an estimated token count: 640, 4.4k, 1.2M."""
    if size is None:
        return "—"
    n = size / BYTES_PER_TOKEN
    if n < 1000:
        return "{:.0f}".format(n)
    if n < 1_000_000:
        return "{:.1f}k".format(n / 1000)
    return "{:.1f}M".format(n / 1_000_000)


def _sort_key(sort, nodes):
    return lambda id: (-(nodes[id].get(sort) or 0), nodes[id]["label"])


def tag(node):
    """A root's trigger beside its label: the globs a scoped rule or skill waits
    on, a hook's matcher, or that a skill is typed only."""
    trigger = node.get("trigger")
    return "  [{}]".format(trigger) if trigger else ""


def category(node):
    if node["scope"] == "plugin":
        return "plugins"
    return {"instructions": "instructions", "rule": "rules", "hook": "hooks"}.get(
        node["kind"], "skills")


def owner_label(node):
    if node["scope"] == "plugin":
        return "{}@{}".format(node["plugin"], node["marketplace"] or "")
    return {"repo": "this repo", "user": "user scope"}.get(node["scope"], node["scope"])


class Group:
    def __init__(self, key, label, depth):
        self.key, self.label, self.depth = key, label, depth
        self.groups, self.roots = [], []

    def members(self):
        out = list(self.roots)
        for group in self.groups:
            out.extend(group.members())
        return out


def rollup(nodes, by):
    """[Group] for the left pane. By type: a category per kind of artifact,
    with each plugin a group of its own inside Plugins. By owner: a group per
    scope or plugin."""
    top = {}
    for id, node in nodes.items():
        if not node["root"]:
            continue
        if by == "owner":
            key = owner_label(node)
            top.setdefault(key, Group(key, key, 0)).roots.append(id)
            continue
        cat = category(node)
        group = top.setdefault(cat, Group(cat, dict(CATEGORIES)[cat], 0))
        if cat != "plugins":
            group.roots.append(id)
            continue
        key = "plugins/" + owner_label(node)
        sub = next((s for s in group.groups if s.key == key), None)
        if sub is None:
            sub = Group(key, node["plugin"], 1)
            group.groups.append(sub)
        sub.roots.append(id)
    if by == "owner":
        return list(top.values())
    return [top[key] for key, _label in CATEGORIES if key in top]


def group_stats(group, nodes, pulled):
    """(paid at launch, pulls in, unmeasured, the nodes pulled in, the deepest
    path): a group's members' closures unioned, so a file two of them share
    counts once."""
    members = group.members()
    union = set()
    for id in members:
        union |= pulled[id] & nodes.keys()
    launch = sum(nodes[id]["size"] for id in members if nodes[id]["tier"] == LAUNCH)
    return (launch, sum(nodes[id]["size"] for id in union),
            sum(1 for id in union if not nodes[id]["measured"]), union,
            max((depth_cost(nodes[id]) for id in union), default=0))


def left_rows(groups, expanded, sort, nodes, stats):
    """[("group", Group) | ("root", id, depth)] in display order."""
    rows = []

    def visit(group):
        rows.append(("group", group))
        if group.key not in expanded:
            return
        for sub in sorted(group.groups, key=lambda s: -stats[s.key][1]):
            visit(sub)
        rows.extend(("root", id, group.depth + 1)
                    for id in sorted(group.roots, key=_sort_key(sort, nodes)))

    for group in groups:
        visit(group)
    return rows


def tree_rows(nodes, tops, sort, expanded):
    """[(path, depth, cut)] for the right pane: a tree from each of tops.
    `cut` marks a node already above it on its path, shown but not expanded."""
    rows = []

    def visit(path, depth):
        id = path[-1]
        cut = id in path[:-1]
        rows.append((path, depth, cut))
        if cut or path not in expanded:
            return
        children = [c for c in nodes[id]["children"] if c in nodes]
        for child in sorted(children, key=_sort_key(sort, nodes)):
            visit(path + (child,), depth + 1)

    for top in tops:
        visit((top,), 0)
    return rows


def parse_filter(text):
    """`plugin:anchor tier:launch some words` -> (filters, free text)."""
    filters, words = {}, []
    for token in text.split():
        field, sep, value = token.partition("=") if "=" in token else token.partition(":")
        if sep and field in dict(FILTER_FIELDS) and value:
            filters.setdefault(field, set()).add(value.replace("_", " "))
        else:
            words.append(token.lower())
    return filters, words


def browse(g, base_filters):
    import curses
    curses.wrapper(lambda screen: Browser(screen, g, base_filters).run())


class Browser:
    def __init__(self, screen, g, base_filters):
        import curses
        self.curses = curses
        self.s = screen
        self.g = g
        self.kinds = {(s, t): k for s, t, k in g.edges}
        self.base = base_filters
        self.query = ""
        self.sort = 0
        self.grouping = 0
        self.pane = 0
        self.cursor = [0, 0]
        self.top = [0, 0]
        self.left_open = {INSIGHTS}
        self.right_open = set()
        self.apply()

    # -- model ---------------------------------------------------------------

    def apply(self):
        filters, words = parse_filter(self.query)
        merged = {k: set(v) for k, v in self.base.items() if v}
        for k, v in filters.items():
            merged[k] = merged.get(k, set()) | v
        self.nodes, _ = filtered(self.g, merged)
        if words:
            self.nodes = {id: n for id, n in self.nodes.items()
                          if not n["root"] or all(
                              w in (n["label"] + " " + (n["plugin"] or "")).lower() for w in words)}
        self.groups = rollup(self.nodes, GROUPINGS[self.grouping])
        self.stats = {}
        for group in self.groups:
            for each in [group] + group.groups:
                self.stats[each.key] = group_stats(each, self.nodes, self.g.pulled)
        if GROUPINGS[self.grouping] == "owner":
            self.groups.sort(key=lambda grp: -self.stats[grp.key][1])
        self.insights = insights(self.g, self.nodes)
        self.refresh_rows()

    def refresh_rows(self):
        sort = SORTS[self.sort]
        head = []
        if self.insights:
            head.append((INSIGHTS,))
            if INSIGHTS in self.left_open:
                head.extend(("insight", i) for i in range(len(self.insights)))
        self.left = head + left_rows(self.groups, self.left_open, sort, self.nodes, self.stats)
        self.cursor[0] = min(self.cursor[0], max(len(self.left) - 1, 0))
        self.right = tree_rows(self.nodes, self.right_tops(), sort, self.right_open)
        self.cursor[1] = min(self.cursor[1], max(len(self.right) - 1, 0))

    def selected(self):
        return self.left[self.cursor[0]] if self.left else None

    def right_tops(self):
        """What the right pane shows: a root's tree, or a group's heaviest
        files, biggest first."""
        row = self.selected()
        if row is None:
            return []
        if row[0] == "root":
            return [row[1]]
        if row[0] == INSIGHTS:
            return []
        if row[0] == "insight":
            focus = self.insights[row[1]]["focus"]
            ids = [focus["id"]] if focus["type"] == "node" else focus["ids"]
            return [id for id in ids if id in self.nodes]
        union = self.stats[row[1].key][3]
        return sorted((id for id in union if self.nodes[id]["measured"]),
                      key=_sort_key(SORTS[self.sort], self.nodes))

    def right_title(self):
        row = self.selected()
        if row is None:
            return "nothing matches"
        if row[0] == "root":
            return "{}: what it opens".format(self.nodes[row[1]]["label"])
        if row[0] == INSIGHTS:
            return "Insights: what stands out in this graph; select one to see its files"
        if row[0] == "insight":
            return self.insights[row[1]]["text"]
        return "{}: heaviest files it pulls in".format(row[1].label.split("  ")[0])

    # -- drawing -------------------------------------------------------------

    def setup_colors(self):
        c = self.curses
        self.heat = [0] * len(HEAT_256)
        if not c.has_colors():
            return
        c.start_color()
        try:
            c.use_default_colors()
            bg = -1
        except c.error:
            bg = c.COLOR_BLACK
        # A 256-color terminal gets the gray-to-red ramp; an 8-color one gets
        # its nearest: plain, yellow, then red.
        basic = (-1, -1, c.COLOR_YELLOW, c.COLOR_YELLOW, c.COLOR_RED, c.COLOR_RED)
        for level in range(len(HEAT_256)):
            fg = HEAT_256[level] if c.COLORS >= 256 else basic[level]
            c.init_pair(level + 1, fg, bg)
            attr = c.color_pair(level + 1)
            if level >= len(HEAT_256) - 2:
                attr |= c.A_BOLD
            self.heat[level] = attr

    def put(self, y, x, text, width, attr=0):
        if width <= 0 or y < 0:
            return
        try:
            self.s.addnstr(y, x, text.ljust(width), width, attr)
        except self.curses.error:
            pass

    def scroll(self, pane, body):
        cur = self.cursor[pane]
        if cur < self.top[pane]:
            self.top[pane] = cur
        elif cur >= self.top[pane] + body:
            self.top[pane] = cur - body + 1

    def draw(self):
        c = self.curses
        self.s.erase()
        height, width = self.s.getmaxyx()
        split = max(34, width * 2 // 5)
        body = height - 9
        by = GROUPINGS[self.grouping]
        heading = c.A_REVERSE if self.pane == 0 else c.A_BOLD
        self.put(0, 0, " What a session can load, by {}".format(
            "artifact type" if by == "type" else "owner"), split, heading)
        self.put(1, 0, " g groups by {}".format("owner" if by == "type" else "artifact type"),
                 split, c.A_DIM)
        self.put(2, 0, "   {:>7} {:>7} {:>7}   ~tokens".format("launch", "all", "deep"), split, c.A_DIM)
        heading = c.A_REVERSE if self.pane == 1 else c.A_BOLD
        title = textwrap.wrap(self.right_title(), max(width - split - 3, 20)) or [""]
        self.put(0, split + 1, " " + title[0], width - split - 1, heading)
        self.put(1, split + 1, " " + " ".join(title[1:]), width - split - 1, heading)
        self.put(2, split + 1, "   {:>7} {:>7} {:>7} {:>7}   ~tokens".format(
            "spent", "this", "+next", "all"), width - split - 1, c.A_DIM)

        self.scroll(0, body)
        for i, row in enumerate(self.left[self.top[0]:self.top[0] + body]):
            index = self.top[0] + i
            chosen = index == self.cursor[0]
            if row[0] == INSIGHTS:
                mark = "▾" if INSIGHTS in self.left_open else "▸"
                text = "! {:>23}  {} Insights ({})".format("", mark, len(self.insights))
                attr = self.heat[3] | c.A_BOLD
            elif row[0] == "insight":
                text = "  {:>23}    • {}".format("", self.insights[row[1]]["title"])
                attr = 0
            elif row[0] == "group":
                group = row[1]
                launch, pulls, unmeasured, _, deepest = self.stats[group.key]
                mark = "▾" if group.key in self.left_open else "▸"
                text = "{} {:>7} {:>7} {:>7}  {}{} {}".format(
                    HEAT_GLYPHS[heat_level(pulls)], tokens(launch),
                    "?" if unmeasured and not pulls else tokens(pulls), tokens(deepest),
                    "  " * group.depth, mark, group.label)
                attr = self.heat_attr(pulls) | c.A_BOLD
            else:
                _kind, id, depth = row
                n = self.nodes[id]
                launch = n["size"] if n["tier"] == LAUNCH else None
                deepest = max((depth_cost(self.nodes[m]) for m in self.g.pulled[id] & self.nodes.keys()),
                              default=0)
                text = "{} {:>7} {:>7} {:>7}  {}{}".format(
                    HEAT_GLYPHS[heat_level(n["closure"])], tokens(launch), tokens(n["closure"]),
                    tokens(deepest),
                    "  " * depth, n["label"] + tag(n))
                attr = self.heat_attr(n["closure"])
            if chosen:
                attr = (attr | c.A_REVERSE) if self.pane == 0 else (attr | c.A_UNDERLINE)
            self.put(i + 3, 0, text, split, attr)

        self.scroll(1, body)
        for i, (path, depth, cut) in enumerate(self.right[self.top[1]:self.top[1] + body]):
            index = self.top[1] + i
            n = self.nodes[path[-1]]
            has_children = any(ch in self.nodes for ch in n["children"])
            mark = "↺" if cut else (("▾" if path in self.right_open else "▸") if has_children else " ")
            edge = self.kinds.get((path[-2], path[-1]), "") if len(path) > 1 else ""
            measured = n["measured"]
            # Down a tree, what's spent is what this path opened; a top row has
            # no path above it, so it shows the cheapest one from any root.
            spent = (sum(self.nodes[id]["size"] for id in set(path[:-1]))
                     if len(path) > 1 else n["reach"])
            text = "{} {:>7} {:>7} {:>7} {:>7}  {}{} {}{}".format(
                HEAT_GLYPHS[heat_level(n["closure"])], tokens(spent),
                tokens(n["size"]) if measured else "?",
                tokens(n["next"]) if has_children else "-",
                tokens(n["closure"]) if measured else "?",
                "  " * depth, mark, (edge + " ") if edge else "", n["label"] + tag(n))
            attr = self.heat_attr(n["closure"])
            if index == self.cursor[1] and self.pane == 1:
                attr |= c.A_REVERSE
            self.put(i + 3, split + 1, text, width - split - 1, attr)

        for y in range(0, body + 3):
            try:
                self.s.addch(y, split, c.ACS_VLINE)
            except c.error:
                pass
        t = totals(self.nodes.values())
        footer = (" ~tokens: launch {} · every file {} · deepest path {} · unmeasured {}"
                  " · sort: {} · filter: {}").format(
            tokens(t["launch"]), tokens(t["reachable"]), tokens(t["deepest"]), t["unmeasured"],
            SORT_LABELS[SORTS[self.sort]], self.query or self.describe_base() or "none")
        self.put(height - 6, 0, "─" * width, width)
        when, via = self.details()
        self.put(height - 5, 0, " when  " + when, width, c.A_BOLD)
        self.put(height - 4, 0, " via   " + via, width)
        self.put(height - 3, 0, "─" * width, width)
        self.put(height - 2, 0, footer, width)
        self.put(height - 1, 0,
                 " ↑↓ move  tab pane  enter/space expand  ←→ collapse/expand  "
                 "s sort  g group by  / filter  q quit", width, c.A_DIM)
        self.s.refresh()

    def heat_attr(self, n):
        return self.heat[heat_level(n)]

    def details(self):
        """(when the selected node loads, the line that opens it) for the strip
        under the panes. The reference comes from the row above it in the tree."""
        if self.pane == 1 and self.right:
            path = self.right[self.cursor[1]][0]
            n = self.nodes[path[-1]]
            if len(path) > 1:
                kind = self.kinds.get((path[-2], path[-1]), "")
                ref = self.g.refs.get((path[-2], path[-1], kind))
                if ref:
                    return n.get("when", ""), "{}:{}  {}".format(
                        ref["file"], ref["line"] or "?", ref["text"])
                return n.get("when", ""), "{} {}".format(kind, self.nodes[path[-2]]["label"])
            return n.get("when", ""), "a root: the harness opens it"
        row = self.selected()
        if row is None:
            return "", ""
        if row[0] == "root":
            return self.nodes[row[1]].get("when", ""), "a root: the harness opens it"
        if row[0] == "insight":
            return self.insights[row[1]]["text"], "how: " + self.insights[row[1]]["query"]
        return "", ""

    def describe_base(self):
        return " ".join("{}:{}".format(k, v) for k, vs in sorted(self.base.items()) for v in sorted(vs))

    # -- input ---------------------------------------------------------------

    def prompt(self):
        c = self.curses
        height, width = self.s.getmaxyx()
        self.put(height - 1, 0, "/", width)
        c.echo()
        try:
            c.curs_set(1)
        except c.error:
            pass
        try:
            raw = self.s.getstr(height - 1, 1, width - 2).decode("utf-8", "replace")
        finally:
            c.noecho()
            try:
                c.curs_set(0)
            except c.error:
                pass
        self.query = raw.strip()
        self.cursor = [0, 0]
        self.top = [0, 0]
        self.apply()

    def run(self):
        c = self.curses
        try:
            c.curs_set(0)
        except c.error:
            pass
        self.setup_colors()
        self.s.keypad(True)
        self.on_select()
        while True:
            self.draw()
            key = self.s.getch()
            rows = self.left if self.pane == 0 else self.right
            page = self.s.getmaxyx()[0] - 9
            if key == ord("q"):
                return
            if key == 9:
                self.pane = 1 - self.pane
            elif key in (c.KEY_DOWN, ord("j")):
                self.move(1, rows)
            elif key in (c.KEY_UP, ord("k")):
                self.move(-1, rows)
            elif key == c.KEY_NPAGE:
                self.move(page, rows)
            elif key == c.KEY_PPAGE:
                self.move(-page, rows)
            elif key == ord("s"):
                self.sort = (self.sort + 1) % len(SORTS)
                self.refresh_rows()
            elif key == ord("g"):
                self.grouping = (self.grouping + 1) % len(GROUPINGS)
                self.left_open = {INSIGHTS} & self.left_open
                self.cursor = [0, 0]
                self.top = [0, 0]
                self.apply()
                self.on_select()
            elif key == ord("/"):
                self.prompt()
                self.on_select()
            elif key in (10, 13, 32, c.KEY_ENTER):
                self.toggle()
            elif key in (c.KEY_RIGHT, ord("l")):
                self.open(True)
            elif key in (c.KEY_LEFT, ord("h")):
                self.open(False)

    def move(self, delta, rows):
        pane = self.pane
        self.cursor[pane] = max(0, min(len(rows) - 1, self.cursor[pane] + delta))
        if pane == 0:
            self.on_select()

    def on_select(self):
        """A new left row starts the right pane fresh, a root opened one level."""
        self.cursor[1] = 0
        self.top[1] = 0
        self.right_open = set()
        row = self.selected()
        if row is not None and row[0] == "root":
            self.right_open.add((row[1],))
        self.refresh_rows()

    def toggle(self):
        if self.pane == 0:
            row = self.selected()
            if row is None:
                return
            if row[0] == INSIGHTS:
                self.left_open ^= {INSIGHTS}
            elif row[0] == "insight":
                self.pane = 1
            elif row[0] == "group":
                self.left_open ^= {row[1].key}
            else:
                self.right_open ^= {(row[1],)}
            self.refresh_rows()
            return
        if not self.right:
            return
        path, _depth, cut = self.right[self.cursor[1]]
        if not cut:
            self.right_open ^= {path}
            self.refresh_rows()

    def open(self, expand):
        if self.pane == 0:
            row = self.selected()
            if row is None:
                return
            if row[0] == INSIGHTS:
                (self.left_open.add if expand else self.left_open.discard)(INSIGHTS)
            elif row[0] == "insight":
                if expand:
                    self.pane = 1
                else:
                    self.cursor[0] = 0
                    self.on_select()
            elif row[0] == "group":
                if expand:
                    self.left_open.add(row[1].key)
                elif row[1].key in self.left_open:
                    self.left_open.discard(row[1].key)
                else:
                    self.to_parent_group(row[1].depth)
            elif expand:
                self.pane = 1
            else:
                self.to_parent_group(row[2])
            self.refresh_rows()
            return
        if not self.right:
            return
        path, _depth, cut = self.right[self.cursor[1]]
        if expand and not cut:
            self.right_open.add(path)
        elif not expand and path in self.right_open:
            self.right_open.discard(path)
        elif not expand and len(path) > 1:
            parent = path[:-1]
            self.cursor[1] = next(i for i, row in enumerate(self.right) if row[0] == parent)
        elif not expand:
            self.pane = 0
        self.refresh_rows()

    def to_parent_group(self, depth):
        """Move the left cursor up to the nearest group above at a shallower depth."""
        for i in range(self.cursor[0] - 1, -1, -1):
            row = self.left[i]
            if row[0] == INSIGHTS:
                return
            if row[0] == "group" and row[1].depth < depth:
                self.cursor[0] = i
                self.on_select()
                return


# ---- the command -----------------------------------------------------------

def run(h, args):
    directory = pathlib.Path(args.directory)
    if not directory.is_dir():
        sys.stderr.write("cleat: not a directory: {}\n".format(directory))
        return 2
    interactive = not args.json and args.html is None
    if interactive and not (sys.stdin.isatty() and sys.stdout.isatty()):
        sys.stderr.write("cleat: graph browses in a terminal; outside one, pass "
                         "--json or --html\n")
        return 2
    if args.html and pathlib.Path(args.html).is_dir():
        sys.stderr.write("cleat: --html {} is a directory; name the page file, or "
                         "put DIR before --html\n".format(args.html))
        return 2
    filters = {field: set(getattr(args, field) or ()) for field, _ in FILTER_FIELDS}
    try:
        g = build(h, directory)
    except RuntimeError as exc:
        sys.stderr.write("cleat: {}\n".format(exc))
        return 2
    if interactive:
        browse(g, filters)
        return 0
    nodes, edges = filtered(g, filters)
    data = as_json(directory.resolve(), g, nodes, edges, filters)
    if args.html is not None:
        status = write_page(data, args.html)
        if status:
            return status
    if args.json:
        json.dump(data, sys.stdout, indent=2)
        sys.stdout.write("\n")
    return 0


def write_page(data, target):
    """Write the page to target, or with no target to a new temporary file that
    then opens in the default browser."""
    try:
        page = render_html(data)
    except (OSError, RuntimeError) as exc:
        sys.stderr.write("cleat: {}\n".format(exc))
        return 2
    if target:
        path = pathlib.Path(target)
    else:
        handle, name = tempfile.mkstemp(prefix="cleat-graph.", suffix=".html")
        os.close(handle)
        path = pathlib.Path(name)
    path.write_text(page, encoding="utf-8")
    t = data["totals"]
    sys.stderr.write("cleat: wrote {} ({} files; ~tokens at launch {}, every file {}, deepest "
                     "path {}; {} unmeasured)\n".format(
                         path, t["nodes"], tokens(t["launch"]), tokens(t["reachable"]),
                         tokens(t["deepest"]), t["unmeasured"]))
    if not target and not webbrowser.open(path.resolve().as_uri()):
        sys.stderr.write("cleat: no browser opened {}; open it yourself\n".format(path))
        return 2
    return 0
