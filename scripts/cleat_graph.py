"""`cleat graph`: the context graph a session can load, and its costs.

Imported by `scripts/cleat` for the graph and metrics commands alone, so a hook
never parses it. The helpers it shares with `cleat cost` arrive as the `cleat`
module itself.
"""
from __future__ import annotations

import base64
import collections
import datetime
import concurrent.futures
import gzip
import hashlib
import heapq
import html.parser
import json
import math
import os
import pathlib
import re
import sys
import tempfile
import textwrap
import urllib.error
import urllib.request
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


# A file named for people browsing a folder, not for an agent working in it.
HUMAN_FACING = {"readme", "changelog", "license", "contributing", "security", "code_of_conduct"}
# What a session opens on its own: a file one of these links to marks its
# folder as one the guidance uses.
LINKERS = {"skill", "agent", "command", "rule", "instructions"}
TOPIC_WORD = re.compile(r"[a-z][a-z0-9]{3,}")
TOPIC_STOP = {"about", "content", "file", "from", "goes", "guide", "into", "name", "notes",
              "that", "this", "tool", "using", "what", "when", "where", "which", "with", "your"}

TOC_WINDOW = 40
TOC_HEADING = re.compile(r"#+\s*(?:table of )?contents\b", re.I)
TOC_ITEM = re.compile(r"\s*(?:[-*+]|\d+\.)\s+\[[^\]]+\]\(#")


def has_toc(text):
    """A contents heading, or three list items linking to anchors in the file,
    within its first lines: what a partial read sees."""
    head = text.splitlines()[:TOC_WINDOW]
    return (any(TOC_HEADING.match(line) for line in head)
            or sum(1 for line in head if TOC_ITEM.match(line)) >= 3)


class Graph:
    def __init__(self):
        self.nodes = {}
        self.edges = set()
        # (source, target, kind) -> where the source names the target: the
        # file, its line, and the line's text. The first mention wins.
        self.refs = {}
        # owner label -> the install record's version and commit, per plugin
        self.plugins = {}
        # node id -> its text as a session loads it, for the page's probe
        self.texts = {}
        # the files beside the guidance that nothing links to, from Walker.orphans
        self.orphans = []

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
    """[(key, install path, install record)] for each plugin the merged
    settings enable."""
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
        out.append((key, path, chosen))
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
            parts = path.relative_to(scope.base.resolve()).parts
            # A synced skill's account id says nothing a reader wants in a label.
            if parts[:2] == ("skills", "synced") and len(parts) > 3:
                parts = parts[:2] + parts[3:]
            return "/".join(parts)
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
            joined = "".join(text for _p, text in texts)
            node["digest"] = hashlib.sha256(joined.encode("utf-8")).hexdigest()[:16]
            node["lines"] = len(joined.splitlines())
            if path.suffix.lower() in TEXT_SUFFIXES:
                node["toc"] = has_toc(joined)
                self.g.texts[id] = joined
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
        self.g.texts[entry] = self.h._listing_entry(qualified, fields, body)
        if trigger:
            self.g.nodes[entry]["trigger"] = trigger
        self.g.edge(entry, body_id, "invoke")

    def components(self, base, scope, manifest=None):
        manifest = manifest or {}
        for skills in _manifest_dirs(base, manifest, "skills", "skills"):
            # A skill the claude.ai account syncs sits a level deeper, under
            # skills/synced/<account>/<name>/, after the ones in the folder itself,
            # so one of the same name here shadows it.
            paths = sorted(skills.glob("*/SKILL.md")) + sorted(skills.glob("synced/*/*/SKILL.md"))
            for path in paths:
                fields, _ = self.h._frontmatter(self.h._read(path))
                self.invocable(path, fields.get("name") or path.parent.name, "skill", scope)
        for commands in _manifest_dirs(base, manifest, "commands", "commands"):
            for path in sorted(commands.rglob("*.md")):
                name = path.relative_to(commands).with_suffix("").as_posix().replace("/", ":")
                self.invocable(path, name, "command", scope)
        for agents in _manifest_dirs(base, manifest, "agents", "agents"):
            # An agent is agents/<name>.md, or agents/<name>/<name>.md beside its scripts.
            paths = sorted(agents.glob("*.md")) + sorted(p for p in agents.glob("*/*.md")
                                                         if p.stem == p.parent.name)
            for path in paths:
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

    def remote(self, id, holder, original, match):
        """A web URL the file states, with the line that states it: what a
        session reaches only by leaving the machine."""
        url = match.group(0).rstrip(".,;:!?)>]}\"'`*")
        if not url.lower().startswith(("http://", "https://")):
            return
        host = url.split("/", 3)[2]
        # A host with no dot is a placeholder in an example, not a site.
        if "." not in host:
            return
        remotes = self.g.nodes[id].setdefault("remotes", [])
        if any(r["url"] == url for r in remotes):
            return
        ref = self.ref(holder, original, match.start())
        remotes.append({"url": url, "host": host, "line": ref["line"], "text": ref["text"]})

    def scan(self, id):
        node = self.g.nodes[id]
        scope = self.scope_of(pathlib.Path(node["path"]))
        for holder, original in self.texts.pop(id):
            for match in URL.finditer(original):
                self.remote(id, holder, original, match)
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

    # -- orphans -------------------------------------------------------------

    def orphans(self):
        """The markdown files in a folder the guidance uses that no reference
        reaches: a skill's or agent's own folder, or a folder holding a file
        that a skill, agent, command, rule, or instruction file links to. A
        README and its kin are for people, and a file a hook's script names,
        or one of its folders, reaches the agent through that script's output,
        so neither is one. Each carries the fix: the line to name it on."""
        nodes = self.g.nodes
        known = {n["path"] for n in nodes.values() if n["kind"] not in ("entry", "hook")}
        folders = {}
        for id, n in sorted(nodes.items()):
            path = pathlib.Path(n["path"])
            if n["scope"] != "other" and (
                    (n["kind"] == "skill" and path.name == "SKILL.md")
                    or (n["kind"] == "agent" and path.parent.name == path.stem)):
                folders.setdefault(path.parent, (id, True))
        # A folder's holder is the file that links the most of what it holds.
        linkers = collections.defaultdict(collections.Counter)
        for source, target, kind in sorted(self.g.edges):
            s, t = nodes[source], nodes[target]
            folder = pathlib.Path(t["path"]).parent
            if (kind == "read" and s["kind"] in LINKERS and t["scope"] != "other"
                    and owner_label(s) == owner_label(t)
                    and str(folder) != str(self.scope_of(folder).base.resolve())):
                linkers[folder][source] += 1
        for folder, counts in linkers.items():
            folders.setdefault(folder, (min(counts, key=lambda id: (-counts[id], id)), False))
        hooks, scripts = collections.defaultdict(list), collections.defaultdict(list)
        for n in nodes.values():
            if n["kind"] == "script" and pathlib.Path(n["path"]).suffix.lower() in SCRIPT_SUFFIXES:
                scripts[owner_label(n)].append(self.h._read(pathlib.Path(n["path"])))
            if n["kind"] != "hook":
                continue
            holder = pathlib.Path(n["path"])
            for match in PATH_REF.finditer(n.get("note") or ""):
                target = self.resolve(match.group(1), holder, self.scope_of(holder))
                if target is not None and target.suffix.lower() in SCRIPT_SUFFIXES:
                    hooks[owner_label(n)].append(self.h._read(target))
        found = {}
        for folder, (holder, home) in sorted(folders.items()):
            for path in sorted(folder.rglob("*.md") if home else folder.glob("*.md")):
                rel = path.relative_to(folder).parts
                if any(part.startswith(".") or part == "node_modules" for part in rel):
                    continue
                path = path.resolve()
                if (str(path) in known or str(path) in found or path.name.startswith("_")
                        or path.stem.lower() in HUMAN_FACING):
                    continue
                owner = owner_label(nodes[holder])
                folder_ref = re.compile(r"/" + re.escape(path.parent.name) + r"(?![\w./-])")
                if (any(path.name in text for text in hooks[owner] + scripts[owner])
                        or any(folder_ref.search(text) for text in hooks[owner])):
                    continue
                found[str(path)] = self.orphan(path, folder, holder, home)
        return list(found.values())

    def orphan(self, path, folder, holder, home):
        nodes = self.g.nodes
        scope = self.scope_of(path)
        text = self.h._read(path)
        owner = owner_label(nodes[holder])
        record = dict(id=str(path), label=self.label(path, scope), path=str(path), kind="file",
                      tier=READ, size=len(text.encode("utf-8")), lines=len(text.splitlines()),
                      measured=True, root=False, reach=None, via=None, closure=0, next=0,
                      holder=nodes[holder]["label"], **scope.attrs())
        mine = [(id, n) for id, n in sorted(nodes.items())
                if owner_label(n) == owner and id in self.g.texts and n["kind"] != "entry"]
        # Named only as a folder: the skill points at a subfolder of its own
        # and not at the file, so an agent lists the folder to find it.
        sub = path.relative_to(folder).parts[0] if home and path.parent != folder else None
        if sub:
            named = re.compile(r"(?<![\w./-])" + re.escape(sub) + r"/(?![\w-])")
            for id, n in mine:
                if not n["path"].startswith(str(folder) + os.sep):
                    continue
                found = named.search(self.g.texts[id])
                if found:
                    record.update(status="folder", folder=sub, fix=self.line_at(id, found.start()),
                                  advice="{} names the folder {}/ but not this file, so an agent "
                                         "lists the folder to find it. Name it there, with when to "
                                         "read it.".format(n["label"], sub))
                    return record
        title = next((line.lstrip("#").strip() for line in text.splitlines()
                      if line.startswith("# ")), "")
        stem = {w for w in TOPIC_WORD.findall(re.sub(r"[-_.]", " ", path.stem).lower())
                if w not in TOPIC_STOP}
        words = sorted(stem | {w for w in TOPIC_WORD.findall(title.lower()) if w not in TOPIC_STOP})
        pattern = re.compile(r"\b(?:{})\b".format("|".join(map(re.escape, words))), re.I) if words else None
        # The best home: a file named for the same thing (docs/skills/x.md
        # beside skills/x/SKILL.md), then a line naming every word of its file
        # name, then the line naming most of its topic.
        best = None
        for id, n in mine:
            if n["reach"] is None:
                continue
            namesake = path.stem.lower() in (part.lower() for part in pathlib.Path(n["label"]).parts[:-1])
            offset = 0
            for line in self.g.texts[id].split("\n"):
                said = {m.group(0).lower() for m in pattern.finditer(line)} if pattern else set()
                named = bool(stem) and stem <= said
                rank = (namesake, named, len(said), id == holder)
                if (namesake or said) and (best is None or rank > best[0]):
                    best = (rank, id, offset, sorted(said))
                offset += len(line) + 1
        topic = ", ".join(words) or path.stem
        record.update(status="unlinked", topic=words)
        if best and (best[0][0] or best[0][1] or best[0][2] >= min(2, len(words))):
            home_label = nodes[best[1]]["label"]
            record.update(fix=self.line_at(best[1], best[2]), advice=(
                "Nothing links to it. {} shares its name: link it there, with when to read it."
                .format(home_label) if best[0][0] else
                "Nothing links to it. {} talks about {} too: link it there, with when to read it."
                .format(home_label, ", ".join(best[3]))))
        else:
            record.update(fix=None,
                          advice="Nothing links to it, and nothing a session reaches talks about "
                                 "{}. Link it from {} if it is still needed, or delete it.".format(
                                     topic, nodes[holder]["label"]))
        return record

    def line_at(self, id, offset):
        """The reference shape for a node's text at offset: its file, line, and text."""
        text = self.g.texts[id]
        ref = self.ref(pathlib.Path(self.g.nodes[id]["path"]), text, offset)
        return dict(ref, id=id)

    # -- driver --------------------------------------------------------------

    def walk(self):
        h, root, user = self.h, self.root, self.user
        plugins = enabled_plugins(root, user)
        plugin_scopes = []
        for key, base, record in plugins:
            name, _, market = key.partition("@")
            scope = Scope("plugin", base, name, market or None)
            self.g.plugins["{}@{}".format(name, market)] = {
                "version": record.get("version"), "commit": record.get("gitCommitSha")}
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
    walker = Walker(h, pathlib.Path(root))
    g = walker.walk()
    g.launch_budget = h.launch_budget(pathlib.Path(root))
    g.tiering_guide = str(h.TIERING_GUIDE)
    compute_costs(g)
    g.orphans = walker.orphans()
    return g


# ---- metrics ---------------------------------------------------------------

CURVE_START_TOKENS = 1_000


def hop_counts(nodes):
    """Each node's hop count along the path its reach cost measures, or None
    where no root reaches it."""
    hops = {}
    for id in nodes:
        chain, current = [], id
        while current not in hops:
            node = nodes[current]
            if node["reach"] is None:
                hops[current] = None
            elif node["via"] is None:
                hops[current] = 0
            else:
                chain.append(current)
                current = node["via"]
        for step, link in enumerate(reversed(chain), 1):
            hops[link] = hops[current] + step
    return hops


def _stats(members):
    return {"nodes": len(members), "bytes": sum(n["size"] for n in members),
            "unmeasured": sum(1 for n in members if not n["measured"])}


def depth_curve(nodes):
    """C(b) at a budget doubling from CURVE_START_TOKENS to the first at or past
    the deepest path, and b50 and b90: the smallest depth costs at which C
    reaches half and 90% of the every-file total."""
    points = sorted((depth_cost(n), n["size"]) for n in nodes)
    total = sum(size for _cost, size in points)
    deepest = points[-1][0] if points else 0
    curve, budget, held, i = [], CURVE_START_TOKENS, 0, 0
    while True:
        limit = budget * BYTES_PER_TOKEN
        while i < len(points) and points[i][0] <= limit:
            held += points[i][1]
            i += 1
        curve.append({"tokens": budget, "bytes": held})
        if limit >= deepest:
            break
        budget *= 2

    def reaching(share):
        held = 0
        for cost, size in points:
            held += size
            if held >= share * total:
                return cost
        return 0

    return curve, reaching(0.5), reaching(0.9)


def owner_digest(members):
    """Changes when any of the owner's files is added, removed, or edited."""
    digest = hashlib.sha256()
    for n in sorted(members, key=lambda n: n["id"]):
        digest.update("{}\0{}\n".format(n["id"], n.get("digest") or "").encode("utf-8"))
    return digest.hexdigest()[:16]


def snapshot(h, root, g, taken):
    nodes = g.nodes
    repo = h._repo_root(root)
    commit = h._git(repo, "rev-parse", "--verify", "--quiet", "HEAD",
                    unset_ok=True).strip() if repo else ""

    hops = hop_counts(nodes)
    by_hops = {}
    for count in sorted({c for c in hops.values() if c is not None}):
        by_hops[count] = _stats([nodes[id] for id, c in hops.items() if c == count])
    unreached = [nodes[id] for id, c in hops.items() if c is None]
    if unreached:
        by_hops["unreached"] = _stats(unreached)

    curve, b50, b90 = depth_curve(nodes.values())
    largest = max(nodes.values(), key=lambda n: n["size"], default=None)

    members = {}
    for n in nodes.values():
        members.setdefault(owner_label(n), []).append(n)
    owner_rows = []
    for row in owners(nodes):
        row = dict(row, digest=owner_digest(members[row["owner"]]))
        if row["scope"] == "plugin":
            row.update(g.plugins.get(row["owner"], {"version": None, "commit": None}))
        owner_rows.append(row)

    return {
        "at": taken.isoformat(timespec="seconds"),
        "directory": str(root.resolve()),
        "commit": commit or None,
        "bytesPerToken": BYTES_PER_TOKEN,
        "totals": totals(nodes.values()),
        "tiers": {tier: _stats([n for n in nodes.values() if n["tier"] == tier])
                  for tier in TIERS},
        "hops": by_hops,
        "curve": curve,
        "b50": b50,
        "b90": b90,
        "largestStep": {"path": largest["id"], "bytes": largest["size"]} if largest else None,
        "owners": owner_rows,
    }


PLAIN_KEY = re.compile(r"[A-Za-z_][\w-]*\Z")


def _scalar(value):
    """A YAML scalar. A string goes out JSON-quoted, which YAML reads as a
    double-quoted scalar, so no value needs escaping rules of its own."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, dict):
        return "{}"
    if isinstance(value, list):
        return "[]"
    return json.dumps(value, ensure_ascii=False)


def yaml_lines(value, indent=0):
    """Block-style YAML for nested dicts, lists, and scalars."""
    pad = " " * indent
    if isinstance(value, dict):
        for key, item in value.items():
            key = key if isinstance(key, int) or PLAIN_KEY.match(key) else _scalar(key)
            if isinstance(item, (dict, list)) and item:
                yield "{}{}:".format(pad, key)
                yield from yaml_lines(item, indent + 2)
            else:
                yield "{}{}: {}".format(pad, key, _scalar(item))
    else:
        for item in value:
            if isinstance(item, (dict, list)) and item:
                lines = list(yaml_lines(item, indent + 2))
                yield "{}- {}".format(pad, lines[0][indent + 2:])
                yield from lines[1:]
            else:
                yield "{}- {}".format(pad, _scalar(item))


def history_path(given):
    if given:
        return pathlib.Path(given)
    state = os.environ.get("XDG_STATE_HOME") or pathlib.Path.home() / ".local" / "state"
    return pathlib.Path(state) / "cleat" / "metrics.yml"


def run_metrics(h, args):
    directory = pathlib.Path(args.directory)
    if not directory.is_dir():
        sys.stderr.write("cleat: not a directory: {}\n".format(directory))
        return 2
    try:
        g = build(h, directory)
        snap = snapshot(h, directory, g, datetime.datetime.now(datetime.timezone.utc))
    except RuntimeError as exc:
        sys.stderr.write("cleat: {}\n".format(exc))
        return 2
    text = "\n".join(yaml_lines([snap])) + "\n"
    path = history_path(args.history)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(text)
    except OSError as exc:
        sys.stderr.write("cleat: cannot write the metrics history {}: {}\n".format(path, exc))
        return 2
    sys.stdout.write(text)
    sys.stderr.write("cleat: appended to {}\n".format(path))
    return 0


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
        "remoteEstimate": REMOTE_ESTIMATE_TOKENS * BYTES_PER_TOKEN,
        "filters": {k: sorted(v) for k, v in filters.items() if v},
        "totals": totals(nodes.values()),
        "owners": owners(nodes),
        "insights": insights(g, nodes),
        "ideal": vs_ideal(g, nodes),
        "nodes": public,
        "edges": [dict({"source": s, "target": t, "kind": k}, **g.refs.get((s, t, k), {}))
                  for s, t, k in edges],
        "orphans": [o for o in g.orphans if matches(o, filters)],
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


# ---- vs ideal --------------------------------------------------------------

SKILLS_OVERVIEW = "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview"
SKILLS_PRACTICES = "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
ENTRY_IDEAL_TOKENS = 100
BODY_IDEAL_TOKENS = 5_000
BODY_IDEAL_LINES = 500
TOC_IDEAL_LINES = 100
BODY_KINDS = ("skill", "command", "agent")
SESSION, INVOCATION, EACH_READ = "every session", "each invocation", "each read"
PAID = (SESSION, INVOCATION, EACH_READ)


def checks(tiering_guide):
    """Each check's ideal, when its excess is paid, where the ideal comes
    from, and the repair."""
    return {
        "launch": dict(paid=SESSION, goal="launch within the launch budget",
                       sources=["cleat: git config cleat.launchBudget, 16 KiB by default"],
                       repair="move what only some sessions need to a later tier; {} "
                              "orders the moves".format(tiering_guide)),
        "entry": dict(paid=SESSION, goal="a listing entry of about {} tokens".format(ENTRY_IDEAL_TOKENS),
                      sources=[SKILLS_OVERVIEW],
                      repair="cut the description to what tells the model when to use it; "
                             "the rest belongs in the body"),
        "body": dict(paid=INVOCATION, goal="a body under {:,} tokens and {} lines".format(
                         BODY_IDEAL_TOKENS, BODY_IDEAL_LINES),
                     sources=[SKILLS_OVERVIEW, SKILLS_PRACTICES],
                     repair="move the sections a run doesn't always need into reference "
                            "files the body links to"),
        "nested": dict(paid=EACH_READ, goal="references one level below the body",
                       sources=[SKILLS_PRACTICES],
                       repair="link it from the body, so a session reads it whole rather "
                              "than previewing it"),
        "toc": dict(paid=EACH_READ, goal="a table of contents atop a reference over {} "
                                          "lines".format(TOC_IDEAL_LINES),
                    sources=[SKILLS_PRACTICES],
                    repair="add a table of contents at the top, so a partial read still "
                           "shows what the file holds"),
    }


def _reads_below(g, start):
    """{node: read hops below start}, following read edges only."""
    reads = {}
    for source, target, kind in g.edges:
        if kind == "read":
            reads.setdefault(source, []).append(target)
    depth, frontier = {}, [start]
    hops = 0
    while frontier:
        hops += 1
        nxt = []
        for current in frontier:
            for target in reads.get(current, ()):
                if target != start and target not in depth:
                    depth[target] = hops
                    nxt.append(target)
        frontier = nxt
    return depth


def vs_ideal(g, nodes):
    """The checks, the scorecard per owner, and the improvements ranked, over
    the nodes shown."""
    spec = checks(g.tiering_guide)
    budget = g.launch_budget
    entry_ideal = round(ENTRY_IDEAL_TOKENS * BYTES_PER_TOKEN)
    body_ideal = round(BODY_IDEAL_TOKENS * BYTES_PER_TOKEN)
    improvements = []
    applies = {}

    def counted(owner, check, failed):
        row = applies.setdefault(owner, {}).setdefault(check, {"failing": 0, "of": 0})
        row["of"] += 1
        row["failing"] += 1 if failed else 0

    def improve(check, node, owner, actual, ideal, excess, title, text, **extra):
        improvements.append(dict(
            check=check, id=node["id"], label=node["label"], owner=owner,
            actual=actual, ideal=ideal, excess=excess, size=node["size"],
            title=title, text=text, **spec[check], **extra))

    members = {}
    for n in nodes.values():
        members.setdefault(owner_label(n), []).append(n)

    for owner, group in members.items():
        if group[0]["scope"] not in ("repo", "user"):
            continue
        launch = [n for n in group if n["tier"] == LAUNCH and n["size"]]
        total = sum(n["size"] for n in launch)
        counted(owner, "launch", total > budget)
        if total > budget:
            largest = max(launch, key=lambda n: n["size"])
            improve("launch", largest, owner, {"bytes": total}, {"bytes": budget}, total - budget,
                    "{} launch ~{} over".format(owner, tokens(total - budget)),
                    "{} loads ~{} tokens at launch against a ~{} budget; its largest piece "
                    "is {} at ~{}.".format(owner, tokens(total), tokens(budget),
                                           largest["label"], tokens(largest["size"])))

    for n in nodes.values():
        owner = owner_label(n)
        if n["kind"] == "entry" and n["size"]:
            over = n["size"] > entry_ideal
            counted(owner, "entry", over)
            if over:
                excess = n["size"] - entry_ideal
                improve("entry", n, owner, {"bytes": n["size"]}, {"bytes": entry_ideal}, excess,
                        "{} entry ~{}".format(n["label"], tokens(n["size"])),
                        "The {} listing entry is ~{} tokens, against about {}: ~{} more in "
                        "every session.".format(n["label"], tokens(n["size"]),
                                                ENTRY_IDEAL_TOKENS, tokens(excess)))
        elif n["kind"] in BODY_KINDS and n["measured"]:
            lines = n.get("lines", 0)
            over = n["size"] > body_ideal or lines > BODY_IDEAL_LINES
            counted(owner, "body", over)
            if over:
                excess = max(0, n["size"] - body_ideal)
                improve("body", n, owner, {"bytes": n["size"], "lines": lines},
                        {"bytes": body_ideal, "lines": BODY_IDEAL_LINES}, excess,
                        "{} body ~{}, {} lines".format(n["label"], tokens(n["size"]), lines),
                        "{} is ~{} tokens and {} lines, against {:,} and {}.".format(
                            n["label"], tokens(n["size"]), lines, BODY_IDEAL_TOKENS,
                            BODY_IDEAL_LINES))
        if n["kind"] == "file" and n["measured"] and n.get("lines", 0) > TOC_IDEAL_LINES:
            counted(owner, "toc", not n.get("toc"))
            if not n.get("toc"):
                improve("toc", n, owner, {"lines": n["lines"], "toc": False},
                        {"lines": TOC_IDEAL_LINES, "toc": True}, 0,
                        "{} {} lines, no contents".format(n["label"], n["lines"]),
                        "{} runs {} lines with no table of contents in its first {}.".format(
                            n["label"], n["lines"], TOC_WINDOW))

    nested = {}
    for body in nodes.values():
        if body["kind"] not in BODY_KINDS:
            continue
        owner = owner_label(body)
        for id, hops in _reads_below(g, body["id"]).items():
            if id not in nodes or nodes[id]["kind"] != "file":
                continue
            row = nested.setdefault((owner, id), {"hops": 1, "bodies": []})
            if hops > 1:
                row["hops"] = max(row["hops"], hops)
                row["bodies"].append(body["label"])
    for (owner, id), row in nested.items():
        failed = bool(row["bodies"])
        counted(owner, "nested", failed)
        if failed:
            n = nodes[id]
            improve("nested", n, owner, {"depth": row["hops"]}, {"depth": 1}, 0,
                    "{} {} reads below {}".format(n["label"], row["hops"], row["bodies"][0]),
                    "{} is {} reads below {}, with no link from the body.".format(
                        n["label"], row["hops"], ", ".join(sorted(set(row["bodies"])))),
                    bodies=sorted(set(row["bodies"])))

    improvements.sort(key=lambda x: (PAID.index(x["paid"]), -x["excess"], -x["size"], x["label"]))
    cards = []
    for owner, rows in applies.items():
        mine = [x for x in improvements if x["owner"] == owner]
        cards.append({
            "owner": owner,
            "checks": {check: rows[check] for check in spec if check in rows},
            # A listing entry is part of launch, so the launch excess already
            # holds the entries' where both fail; the larger is what's paid.
            "excess": {"session": max([sum(x["excess"] for x in mine if x["check"] == check)
                                       for check in ("launch", "entry")]),
                       "invocation": sum(x["excess"] for x in mine if x["paid"] == INVOCATION)},
            "improvements": len(mine),
        })
    cards.sort(key=lambda c: (-c["excess"]["session"], -c["excess"]["invocation"],
                              -c["improvements"], c["owner"]))
    return {"checks": spec, "owners": cards, "improvements": improvements}


# ---- the page --------------------------------------------------------------

PAGE = pathlib.Path(__file__).resolve().parent / "cleat_graph.html"


# ---- web addresses ----------------------------------------------------------
#
# Following a web address costs whatever the fetch puts in context, which no
# file on this machine says. Each address is estimated until it is measured:
# --measure-remote fetches it and records the size of its text, and that
# measurement stands for REMOTE_CACHE_DAYS, read back by every later run
# without touching the network.

# For most fetches, Claude Code's WebFetch hands back a separate model call's
# answer about the page rather than the page, reading at most 100,000
# characters of it (https://code.claude.com/docs/en/tools-reference.md), so what
# a fetch adds does not grow with the page. What that answer runs to is not
# documented: this is an assumption, and every view that shows it says so. A
# measured page smaller than it caps it, since an answer about a page runs no
# longer than the page; the page's own size is what reading it raw costs.
REMOTE_ESTIMATE_TOKENS = 2_000
REMOTE_CACHE_DAYS = 30
REMOTE_READ_LIMIT = 5_000_000
REMOTE_WORKERS = 8
REMOTE_TIMEOUT = 15


def remote_cache_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return pathlib.Path(base) / "cleat" / "remote.json"


def read_remote_cache(path):
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise RuntimeError("{} does not parse ({}); delete it to start the cache over".format(path, exc))


def _fresh(entry, now):
    if not entry:
        return False
    taken = datetime.datetime.fromisoformat(entry["fetched"])
    return now - taken < datetime.timedelta(days=REMOTE_CACHE_DAYS)


class _PageText(html.parser.HTMLParser):
    """The words a page shows: its text, without scripts, styles, or markup."""
    SKIP = {"script", "style", "noscript", "template", "svg", "head"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.skipping = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skipping += 1

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skipping:
            self.skipping -= 1

    def handle_data(self, data):
        if not self.skipping:
            self.parts.append(data)


def page_text(body, content_type):
    if "html" in content_type:
        parser = _PageText()
        parser.feed(body)
        body = "\n".join(parser.parts)
    body = re.sub(r"[ \t]+", " ", body)
    return re.sub(r"\s*\n\s*", "\n", body).strip()


def measure_url(url, now):
    """{bytes, fetched} for the text at url, or {error, fetched}."""
    entry = {"fetched": now.isoformat(timespec="seconds")}
    request = urllib.request.Request(url, headers={"User-Agent": "cleat"})
    try:
        with urllib.request.urlopen(request, timeout=REMOTE_TIMEOUT) as response:
            raw = response.read(REMOTE_READ_LIMIT + 1)
            charset = response.headers.get_content_charset() or "utf-8"
            kind = response.headers.get_content_type()
    except urllib.error.HTTPError as exc:
        return dict(entry, error="HTTP {}".format(exc.code))
    except urllib.error.URLError as exc:
        return dict(entry, error=str(exc.reason))
    except (OSError, ValueError) as exc:
        return dict(entry, error=str(exc) or type(exc).__name__)
    if not kind.startswith("text/") and kind not in ("application/xhtml+xml", "application/json"):
        return dict(entry, error="not text ({})".format(kind))
    text = page_text(raw[:REMOTE_READ_LIMIT].decode(charset, "replace"), kind)
    entry["bytes"] = len(text.encode("utf-8"))
    if len(raw) > REMOTE_READ_LIMIT:
        entry["truncated"] = True
    return entry


def measure_remotes(nodes, cache, path):
    """Fetch each web address the nodes name that has no fresh measurement,
    record each in the cache, write it, and say on stderr what happened."""
    now = datetime.datetime.now(datetime.timezone.utc)
    urls = sorted({r["url"] for n in nodes.values() for r in n.get("remotes", ())})
    stale = [url for url in urls if not _fresh(cache.get(url), now)]
    with concurrent.futures.ThreadPoolExecutor(REMOTE_WORKERS) as pool:
        for url, entry in zip(stale, pool.map(lambda u: measure_url(u, now), stale)):
            cache[url] = entry
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cache, indent=1, sort_keys=True), encoding="utf-8")
    failed = [cache[url]["error"] for url in stale if "error" in cache[url]]
    why = ", ".join("{} \u00d7{}".format(reason, count) for reason, count in
                    sorted(collections.Counter(failed).items(), key=lambda kv: -kv[1])[:4])
    sys.stderr.write("cleat: measured {} of {} web addresses ({} already measured){}; cached in {}\n".format(
        len(stale) - len(failed), len(stale), len(urls) - len(stale),
        "; {} could not be measured: {}".format(len(failed), why) if failed else "", path))
    return cache


def attach_remote_sizes(nodes, cache):
    """Carry each fresh measurement onto the remote reference it measures."""
    now = datetime.datetime.now(datetime.timezone.utc)
    for n in nodes.values():
        for r in n.get("remotes", ()):
            entry = cache.get(r["url"])
            if not _fresh(entry, now):
                continue
            if "bytes" in entry:
                r["bytes"], r["measured"] = entry["bytes"], entry["fetched"][:10]
            else:
                r["error"] = entry["error"]


def remote_cost(sites):
    """(bytes, addresses, measured) for following each distinct address the
    sites name once: the estimate, capped by the page's measured text."""
    seen = {}
    for site in sites:
        for r in site["refs"]:
            seen[r["url"]] = r.get("bytes")
    estimate = REMOTE_ESTIMATE_TOKENS * BYTES_PER_TOKEN
    return (sum(estimate if b is None else min(b, estimate) for b in seen.values()), len(seen),
            sum(1 for b in seen.values() if b is not None))


# ---- the probe --------------------------------------------------------------

def plain(text):
    """What a file says, lowercased, its web addresses blanked at their own
    length: a term is looked for in the words, not in where they link."""
    return URL.sub(lambda m: " " * len(m.group(0)), text.lower())


def probe(g, nodes, term):
    """What a session after `term` finds in the nodes shown: the roots whose
    text mentions it, then hop by hop each reference a lit node states whose
    line or target mentions it, or that a lit listing entry invokes, each node
    once. With no term, everything: each reached node at its hop count along
    its cheapest path, and every remote site. The page's probe() is the same
    walk in JavaScript."""
    term = (term or "").strip().lower()
    hits, mentions = {}, {}
    if term:
        for id in nodes:
            text = g.texts.get(id)
            if text is None:
                continue
            low = plain(text)
            if term not in low:
                continue
            raw = text.split("\n")
            mentions[id] = [raw[i].strip() for i, line in enumerate(low.split("\n")) if term in line]
        out = {}
        for s, t, k in g.edges:
            out.setdefault(s, []).append((t, k))
        frontier = sorted(id for id, n in nodes.items() if n["root"] and id in mentions)
        for id in frontier:
            hits[id] = {"hop": 0, "via": None, "lines": mentions[id], "signposted": True}
        hop = 0
        while frontier:
            hop += 1
            next_frontier = []
            for id in frontier:
                for target, kind in sorted(out.get(id, ())):
                    if target not in nodes or target in hits:
                        continue
                    ref = g.refs.get((id, target, kind))
                    signposted = (bool(ref and term in plain(ref["text"]))
                                  or (kind == "invoke" and nodes[id]["kind"] == "entry"))
                    lines = mentions.get(target)
                    if not signposted and lines is None:
                        continue
                    hits[target] = {"hop": hop, "via": id, "lines": lines or [], "signposted": signposted}
                    next_frontier.append(target)
            frontier = next_frontier
        hops = max(0, hop - 1)
        islands = sorted(id for id in mentions if id not in hits and not nodes[id]["root"])
    else:
        counts = hop_counts(nodes)
        for id, n in nodes.items():
            if counts[id] is not None:
                hits[id] = {"hop": counts[id], "via": n["via"], "lines": [], "signposted": True}
        hops = max((h["hop"] for h in hits.values()), default=0)
        islands = sorted(id for id, count in counts.items() if count is None)
    remotes = {}
    for id in hits:
        for r in nodes[id].get("remotes", ()):
            if term and term not in plain(r["text"]):
                continue
            site = remotes.setdefault(r["host"], {"host": r["host"], "refs": [], "sources": []})
            site["refs"].append(dict(r, source=id))
            if id not in site["sources"]:
                site["sources"].append(id)
    return {"term": term, "hits": hits, "islands": islands, "hops": hops, "mentions": mentions,
            "remotes": dict(sorted(remotes.items(), key=lambda kv: -len(kv[1]["refs"])))}


def listed(node):
    """A root a session has at launch: loaded, or in the listing. A hook, a
    path-scoped rule, and a typed-only skill wait on a trigger instead."""
    return node["root"] and node["tier"] == LAUNCH and node.get("trigger") != "typed only"


def probe_summary(p, nodes):
    """The sentence every view gives for a probe."""
    roots = sum(1 for n in nodes.values() if listed(n))
    lit = sum(1 for id, h in p["hits"].items() if h["hop"] == 0 and listed(nodes[id]))
    waiting = sum(1 for id, h in p["hits"].items() if h["hop"] == 0 and not listed(nodes[id]))
    more = len(p["hits"]) - lit - waiting
    cost = sum(nodes[id]["size"] for id in p["hits"])
    named = sum(len(site["refs"]) for site in p["remotes"].values())
    sites = len(p["remotes"])
    hops = "1 hop" if p["hops"] == 1 else "{} hops".format(p["hops"])
    parts = []
    if not p["term"]:
        parts.append("{} files are loaded or listed at launch and {} wait on a trigger; {} more lie "
                     "within reach over {}, ~{} tokens to read all {}.".format(
                         roots, waiting, more, hops, tokens(cost), len(p["hits"])))
        if p["islands"]:
            parts.append("{} {}: nothing leads there.".format(
                len(p["islands"]), "file is an island" if len(p["islands"]) == 1 else "files are islands"))
    elif not lit:
        parts.append("Nothing loaded mentions \u201c{}\u201d.".format(p["term"]))
    else:
        parts.append("{} of {} loaded files mention \u201c{}\u201d{}.".format(
            lit, roots, p["term"],
            ", and {} waiting on a trigger".format(waiting) if waiting else ""))
        parts.append("Following them lights {} more over {}; reading all {} costs ~{} tokens.".format(
            more, hops, len(p["hits"]), tokens(cost)) if more else
            "None of them points anywhere further about it.")
    if p["term"] and p["islands"]:
        parts.append("{} {} it but {} islands: no lit link leads there.".format(
            len(p["islands"]), "file mentions" if len(p["islands"]) == 1 else "files mention",
            "is one of the" if len(p["islands"]) == 1 else "are"))
    parts.append("{} remote {}, named on {} {}: each a trip off the machine.".format(
        sites, "site" if sites == 1 else "sites", named, "line" if named == 1 else "lines")
        if sites else "Everything it reaches is on this machine.")
    return " ".join(parts)


def probe_public(g, p, nodes):
    """The probe as `--json` carries it."""
    return {
        "term": p["term"],
        "hops": p["hops"],
        "summary": probe_summary(p, nodes),
        "hits": [dict(id=id, label=nodes[id]["label"], **h) for id, h in p["hits"].items()],
        "islands": [dict(id=id, label=nodes[id]["label"], fix=fix,
                         advice=island_advice(fix, p["term"], nodes) if p["term"] else None)
                    for id, fix in ((id, island_fix(g, p, nodes, id) if p["term"] else None)
                                    for id in p["islands"])],
        "sites": list(p["remotes"].values()),
    }


def island_fix(g, p, nodes, id):
    """Why a term doesn't reach an island, and the line that would bring it in.
    Where a lit file links a file that links the island, naming the term on
    that lit line lights the file between, and from it the island, which
    mentions the term: a "name" fix. Otherwise the file that links it most
    cheaply, which asking about the term never opens: "behind"."""
    into = collections.defaultdict(list)
    for s, t, k in sorted(g.edges):
        if s in nodes and t in nodes:
            into[t].append((s, k))
    referrers = sorted(into[id], key=lambda sk: (nodes[sk[0]]["reach"] is None,
                                                 nodes[sk[0]]["reach"] or 0, sk[0]))
    for between, _kind in referrers:
        for source, kind in into[between]:
            if source in p["hits"]:
                ref = g.refs.get((source, between, kind)) or {}
                return dict(ref, id=source, opens=between, fix="name")
    if not referrers:
        return None
    source, kind = referrers[0]
    return dict(g.refs.get((source, id, kind)) or {}, id=source, fix="behind",
                others=len({s for s, _k in referrers}) - 1)


def island_advice(fix, term, nodes):
    """What island_fix finds, as the sentence every view gives."""
    if fix is None:
        return "Nothing links here."
    if fix["fix"] == "name":
        return ("{} is lit, but its line opening {} never says \u201c{}\u201d. Say it there, and "
                "both light.".format(nodes[fix["id"]]["label"], nodes[fix["opens"]]["label"], term))
    others = " and {} more".format(fix["others"]) if fix["others"] else ""
    return "{}{} {} here, and asking about \u201c{}\u201d never opens {}.".format(
        nodes[fix["id"]]["label"], others, "link" if others else "links", term,
        "them" if others else "it")


def render_html(data, texts):
    """The page with the graph inline, and each shown file's text gzipped and
    base64-encoded, so a probe for a term runs in the browser without a
    server and the page stays a fraction of the size of the text."""
    template = PAGE.read_text(encoding="utf-8")
    payload = json.dumps(data, separators=(",", ":")).replace("</", "<\\/")
    for placeholder in ("/*GRAPH*/null", "/*TEXT*/null"):
        if placeholder not in template:
            raise RuntimeError("{} has no {} placeholder".format(PAGE, placeholder))
    packed = base64.b64encode(gzip.compress(
        json.dumps(texts, separators=(",", ":")).encode("utf-8"), mtime=0)).decode("ascii")
    return (template.replace("/*GRAPH*/null", payload, 1)
            .replace("/*TEXT*/null", json.dumps(packed), 1))


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
GROUPINGS = ("type", "owner", "distance")
# The by-distance rollup's last two groups, after a group per hop.
ISLANDS, SITES = "islands", "sites"
# The left pane's first group, open from the start: the findings come before the
# tree they were computed from.
INSIGHTS = "insights"
# The second, closed until opened: each file against the ideal for its tier.
IDEAL = "ideal"
# The third, closed until opened: the files nothing links to, and where to.
ORPHANS = "orphans"
HEADS = (INSIGHTS, IDEAL, ORPHANS)

# A hotspot is absolute, not relative to the screen, so a color means the same
# cost in either pane and on the page.
HEAT_TOKENS = (1_000, 4_000, 10_000, 30_000, 70_000)
HEAT_GLYPHS = ("·", "▁", "▃", "▅", "▇", "█")
# Slate to purple to pink, as the page draws cost; red is kept for a remote site,
# and cyan for what a prompt opens, as the page's meter draws it.
HEAT_256 = (60, 103, 140, 141, 177, 206)
FAR_256 = 203
RANGE_256 = 81
# The meter runs out to the largest common context window, with a mark where
# each smaller one ends, so what does not fit one reads as such.
WINDOW_LIMITS = (200_000, 1_000_000)
WARN_256 = 215
# A row's cost bar: cells, on a log scale from 100 to 100k tokens, so a file
# ten times heavier reads two cells longer.
BAR_CELLS = 6
EIGHTHS = " ▏▎▍▌▋▊▉"


def heat_level(size):
    return sum(1 for limit in HEAT_TOKENS if (size or 0) / BYTES_PER_TOKEN >= limit)


def window_label(size):
    t = size / BYTES_PER_TOKEN
    return "{:g}M".format(t / 1e6) if t >= 1e6 else "{:g}k".format(t / 1000)


def size_bar(size, cells=BAR_CELLS):
    t = (size or 0) / BYTES_PER_TOKEN
    share = 0.0 if t <= 100 else min(1.0, math.log10(t / 100) / 3)
    full, part = divmod(round(share * cells * 8), 8)
    return ("█" * full + (EIGHTHS[part] if part else "")).ljust(cells)


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
        self.groups, self.roots, self.sites = [], [], []

    def members(self):
        out = list(self.roots)
        for group in self.groups:
            out.extend(group.members())
        return out


def rollup(nodes, by, probe=None):
    """[Group] for the left pane. By type: a category per kind of artifact,
    with each plugin a group of its own inside Plugins. By owner: a group per
    scope or plugin. By distance: what the probe lit at each hop from launch,
    then the islands, then the remote sites."""
    if by == "distance":
        groups = []
        for hop in range(probe["hops"] + 1):
            members = [id for id, h in probe["hits"].items() if h["hop"] == hop]
            if hop == 0:
                # What a session has at launch, then the roots waiting on a hook,
                # a glob, or a typed name.
                for key, label, pick in (("hop/0", "Loaded", listed),
                                         ("trigger", "On a trigger", lambda n: not listed(n))):
                    chosen = [id for id in members if pick(nodes[id])]
                    if chosen:
                        group = Group(key, label, 0)
                        group.roots = chosen
                        groups.append(group)
                continue
            if members:
                label = "1 hop" if hop == 1 else "{} hops".format(hop)
                group = Group("hop/{}".format(hop), label, 0)
                group.roots = members
                groups.append(group)
        if probe["islands"]:
            group = Group(ISLANDS, "Islands", 0)
            group.roots = list(probe["islands"])
            groups.append(group)
        if probe["remotes"]:
            group = Group(SITES, "Remote sites", 0)
            group.sites = list(probe["remotes"])
            groups.append(group)
        return groups
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
        rows.extend(("site", host, group.depth + 1) for host in group.sites)

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


def browse(g, base_filters, term=None):
    # A bare Esc steps back, so curses waits only as long as an escape
    # sequence's bytes take to arrive, not its default second.
    os.environ.setdefault("ESCDELAY", "25")
    import curses
    curses.wrapper(lambda screen: Browser(screen, g, base_filters, term).run())


# The terminal reports the mouse in SGR form, ESC [ < button ; x ; y M (press)
# or m (release); curses' own decoding loses the wheel's down turn.
MOUSE_ON, MOUSE_OFF = "\x1b[?1000h\x1b[?1006h", "\x1b[?1006l\x1b[?1000l"
SGR_MOUSE = re.compile(r"\[<(\d+);(\d+);(\d+)([Mm])")
WHEEL_UP, WHEEL_DOWN = 64, 65
# The mouse's back button, as xterm reports buttons 8 and up.
MOUSE_BACK = 128


def osc8(uri, text):
    """text as a hyperlink the terminal opens on cmd+click (or ctrl+click)."""
    return "\x1b]8;;{}\x1b\\{}\x1b]8;;\x1b\\".format(uri, text)


class Browser:
    def __init__(self, screen, g, base_filters, term=None):
        import curses
        self.curses = curses
        self.s = screen
        self.g = g
        self.kinds = {(s, t): k for s, t, k in g.edges}
        self.base = base_filters
        self.query = ""
        self.sort = 0
        # A probe opens on the by-distance rollup; the term may be empty.
        self.term = term or ""
        self.probe = None
        self.grouping = GROUPINGS.index("distance") if term is not None else 0
        self.pane = 0
        self.cursor = [0, 0]
        self.top = [0, 0]
        self.left_open = {INSIGHTS}
        self.right_open = set()
        # The cost columns and the full details strip, shown on `d`.
        self.detail = False
        # The views a step back returns to: before each probe, filter, and regroup.
        self.trail = []
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
        by = GROUPINGS[self.grouping]
        self.probe = probe(self.g, self.nodes, self.term) if by == "distance" else None
        self.groups = rollup(self.nodes, by, self.probe)
        self.stats = {}
        for group in self.groups:
            for each in [group] + group.groups:
                self.stats[each.key] = group_stats(each, self.nodes, self.g.pulled)
        if GROUPINGS[self.grouping] == "owner":
            self.groups.sort(key=lambda grp: -self.stats[grp.key][1])
        self.insights = insights(self.g, self.nodes)
        self.improvements = vs_ideal(self.g, self.nodes)["improvements"]
        self.orphans = [o for o in self.g.orphans if matches(o, merged) and all(
            w in (o["label"] + " " + (o["plugin"] or "")).lower() for w in words)]
        self.refresh_rows()

    def refresh_rows(self):
        sort = SORTS[self.sort]
        head = []
        if self.insights:
            head.append((INSIGHTS,))
            if INSIGHTS in self.left_open:
                head.extend(("insight", i) for i in range(len(self.insights)))
        if self.improvements:
            head.append((IDEAL,))
            if IDEAL in self.left_open:
                head.extend(("improvement", i) for i in range(len(self.improvements)))
        if self.orphans:
            head.append((ORPHANS,))
            if ORPHANS in self.left_open:
                head.extend(("orphan", i) for i in range(len(self.orphans)))
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
        if row[0] == "site":
            return [id for id in self.probe["remotes"][row[1]]["sources"] if id in self.nodes]
        if row[0] in HEADS:
            return []
        if row[0] == "orphan":
            fix = self.orphans[row[1]].get("fix")
            return [fix["id"]] if fix and fix["id"] in self.nodes else []
        if row[0] == "improvement":
            id = self.improvements[row[1]]["id"]
            return [id] if id in self.nodes else []
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
        if row[0] == "site":
            site = self.probe["remotes"][row[1]]
            return "{}: the {} that send a session there".format(
                row[1], "file" if len(site["sources"]) == 1 else "files")
        if row[0] == INSIGHTS:
            return "Insights: what stands out in this graph; select one to see its files"
        if row[0] == "insight":
            return self.insights[row[1]]["text"]
        if row[0] == IDEAL:
            return ("vs ideal: each file against the budget for its tier, what every session "
                    "pays first; select one to see it")
        if row[0] == "improvement":
            return self.improvements[row[1]]["text"]
        if row[0] == ORPHANS:
            return ("Orphans: files beside the guidance that nothing links to; select one to see "
                    "where to name it")
        if row[0] == "orphan":
            o = self.orphans[row[1]]
            return "{}: {}".format(o["label"], "where to name it" if o.get("fix") else "nothing names its topic")
        return "{}: heaviest files it pulls in".format(row[1].label.split("  ")[0])

    # -- drawing -------------------------------------------------------------

    def setup_colors(self):
        c = self.curses
        self.heat = [0] * len(HEAT_256)
        self.far = c.A_BOLD
        self.range = c.A_BOLD
        self.warn = c.A_BOLD
        if not c.has_colors():
            return
        c.start_color()
        try:
            c.use_default_colors()
            bg = -1
        except c.error:
            bg = c.COLOR_BLACK
        # A 256-color terminal gets the slate-to-pink ramp; an 8-color one gets
        # its nearest: plain, blue, then magenta.
        basic = (-1, -1, c.COLOR_BLUE, c.COLOR_MAGENTA, c.COLOR_MAGENTA, c.COLOR_MAGENTA)
        for level in range(len(HEAT_256)):
            fg = HEAT_256[level] if c.COLORS >= 256 else basic[level]
            c.init_pair(level + 1, fg, bg)
            attr = c.color_pair(level + 1)
            if level >= len(HEAT_256) - 2:
                attr |= c.A_BOLD
            self.heat[level] = attr
        c.init_pair(len(HEAT_256) + 1, FAR_256 if c.COLORS >= 256 else c.COLOR_RED, bg)
        self.far = c.color_pair(len(HEAT_256) + 1) | c.A_BOLD
        c.init_pair(len(HEAT_256) + 2, RANGE_256 if c.COLORS >= 256 else c.COLOR_CYAN, bg)
        self.range = c.color_pair(len(HEAT_256) + 2)
        c.init_pair(len(HEAT_256) + 3, WARN_256 if c.COLORS >= 256 else c.COLOR_YELLOW, bg)
        self.warn = c.color_pair(len(HEAT_256) + 3) | c.A_BOLD

    def put(self, y, x, text, width, attr=0):
        if width <= 0 or y < 0:
            return
        try:
            self.s.addnstr(y, x, text.ljust(width), width, attr)
        except self.curses.error:
            pass

    def link(self, y, x, text, path, limit, attr=0):
        """Mark the cells at (y, x) holding text as a link to path, cut at
        column limit. curses can't write an escape sequence into a cell, so
        emit_links rewrites the same text over them once curses has drawn."""
        text = text[:max(limit - x, 0)]
        if text and path and os.path.exists(path):
            self.links.append((y, x, text, pathlib.Path(path).as_uri(), attr))

    def sgr(self, attr):
        c = self.curses
        codes = ["0"]
        for bit, code in ((c.A_BOLD, "1"), (c.A_DIM, "2"), (c.A_UNDERLINE, "4"), (c.A_REVERSE, "7")):
            if attr & bit:
                codes.append(code)
        pair = c.pair_number(attr & c.A_COLOR)
        if pair:
            fg, _bg = c.pair_content(pair)
            if 0 <= fg < 8:
                codes.append(str(30 + fg))
            elif fg >= 8:
                codes.append("38;5;{}".format(fg))
        return "\x1b[{}m".format(";".join(codes))

    def emit_links(self):
        out = "".join("\x1b7\x1b[{};{}H{}{}\x1b8".format(y + 1, x + 1, self.sgr(attr), osc8(uri, text))
                      for y, x, text, uri, attr in self.links)
        if out:
            sys.stdout.write(out)
            sys.stdout.flush()

    def scroll(self, pane, body):
        cur = self.cursor[pane]
        if cur < self.top[pane]:
            self.top[pane] = cur
        elif cur >= self.top[pane] + body:
            self.top[pane] = cur - body + 1

    def layout(self):
        """(rows above the panes' bodies, rows below them) for the current mode."""
        return (4, 7) if self.detail else (2, 4)

    def meter(self, y, width):
        """The context windows as a bar, as the page draws it: what loads at
        start, then what the probe's term opens beyond it, on a square-root
        scale out to the largest window, with a mark where each smaller one
        ends, and what runs past a window named in orange."""
        c = self.curses
        start = sum(n["size"] for n in self.nodes.values() if n["tier"] == LAUNCH)
        adds = online = 0
        if self.probe is not None and self.term:
            adds = sum(self.nodes[id]["size"] for id in self.probe["hits"] if self.nodes[id]["tier"] != LAUNCH)
            online, addresses, measured = remote_cost(self.probe["remotes"].values())
        windows = [limit * BYTES_PER_TOKEN for limit in WINDOW_LIMITS]
        label = " ~{} at start".format(tokens(start))
        if adds:
            label += " + ~{} asking about \u201c{}\u201d".format(tokens(adds), self.term)
        if online:
            label += " + ~{} online{}".format(tokens(online), "" if measured == addresses else " (estimated)")
        total = start + adds + online
        past = [w for w in windows if total > w]
        label += ", ~{} past {}".format(tokens(total - past[-1]), window_label(past[-1])) if past else ""
        marks = "".join("  │ {}".format(window_label(w)) for w in windows[:-1]) + "  ▏ {}".format(window_label(windows[-1]))
        cells = max(16, min(64, width - len(label) - len(marks) - 3))
        at = lambda size: min(cells, round(math.sqrt(min(size, windows[-1]) / windows[-1]) * cells))
        first, second, third = at(start), at(start + adds), at(total)
        line = ["█"] * second + ["▒"] * (third - second) + ["░"] * (cells - third)
        attrs = ([self.heat[3]] * first + [self.range] * (second - first) + [self.far] * (third - second)
                 + [c.A_DIM] * (cells - third))
        for w in windows[:-1]:
            line[min(at(w), cells - 1)] = "│"
            attrs[min(at(w), cells - 1)] = c.A_BOLD
        for i, (ch, attr) in enumerate(zip(line, attrs)):
            self.put(y, 1 + i, ch, 1, attr)
        self.put(y, 1 + cells, "▏", 1, c.A_BOLD)
        self.put(y, 2 + cells, label, len(label), self.warn if past else c.A_BOLD)
        self.put(y, 2 + cells + len(label), marks, width - 2 - cells - len(label), c.A_DIM)

    def lead(self, size, columns=()):
        """A row's cost: a bar and the one number in compact mode, or the
        heat glyph and every column with details on."""
        if self.detail:
            return "{} {}  ".format(HEAT_GLYPHS[heat_level(size)], " ".join("{:>7}".format(v) for v in columns))
        return "{} {:>7}  ".format(size_bar(size), tokens(size) if size is not None else "")

    def blank_lead(self, columns):
        return " " * len(self.lead(0, ("",) * columns))

    def draw(self):
        c = self.curses
        self.s.erase()
        self.links = []
        height, width = self.s.getmaxyx()
        head, tail = self.layout()
        split = max(34, width * 2 // 5)
        body = height - head - tail
        self.split, self.body, self.head = split, body, head
        by = GROUPINGS[self.grouping]
        self.meter(0, width)
        heading = c.A_REVERSE if self.pane == 0 else c.A_BOLD
        if by == "distance":
            title = ("Asking about \u201c{}\u201d, by distance".format(self.term) if self.term
                     else "Everything, by distance from launch")
        else:
            title = "What a session can load, by {}".format("artifact type" if by == "type" else "owner")
        self.put(1, 0, " " + title, split, heading)
        heading = c.A_REVERSE if self.pane == 1 else c.A_BOLD
        title = textwrap.wrap(self.right_title(), max(width - split - 3, 20)) or [""]
        self.put(1, split + 1, " " + title[0], width - split - 1, heading)
        if self.detail:
            following = GROUPINGS[(self.grouping + 1) % len(GROUPINGS)]
            self.put(2, 0, " g groups by {}  p asks about a term".format(
                {"type": "artifact type", "owner": "owner", "distance": "distance"}[following]), split, c.A_DIM)
            self.put(2, split + 1, " " + " ".join(title[1:]), width - split - 1, heading)
            self.put(3, 0, "   {:>7} {:>7} {:>7}   ~tokens".format("launch", "all", "deep"), split, c.A_DIM)
            self.put(3, split + 1, "   {:>7} {:>7} {:>7} {:>7}   ~tokens".format(
                "spent", "this", "+next", "all"), width - split - 1, c.A_DIM)

        self.scroll(0, body)
        blank = self.blank_lead(3)
        for i, row in enumerate(self.left[self.top[0]:self.top[0] + body]):
            index = self.top[0] + i
            chosen = index == self.cursor[0]
            lead = ""
            if row[0] == INSIGHTS:
                mark = "▾" if INSIGHTS in self.left_open else "▸"
                text = "!" + blank[1:] + "{} Insights ({})".format(mark, len(self.insights))
                attr = self.heat[3] | c.A_BOLD
            elif row[0] == "insight":
                text = blank + "  • {}".format(self.insights[row[1]]["title"])
                attr = 0
            elif row[0] == IDEAL:
                mark = "▾" if IDEAL in self.left_open else "▸"
                text = "✓" + blank[1:] + "{} vs ideal ({} to improve)".format(mark, len(self.improvements))
                attr = c.A_BOLD
            elif row[0] == "improvement":
                x = self.improvements[row[1]]
                if self.detail:
                    text = "  {:>7} {:>15}    {:<6} {}".format(
                        "+" + tokens(x["excess"]) if x["excess"] else "", x["paid"][:15],
                        x["check"], x["title"])
                else:
                    text = "{} {:>7}    {}".format(size_bar(x["excess"]),
                                                   "+" + tokens(x["excess"]) if x["excess"] else "", x["title"])
                attr = self.heat_attr(x["excess"])
            elif row[0] == ORPHANS:
                mark = "▾" if ORPHANS in self.left_open else "▸"
                text = "○" + blank[1:] + "{} Orphans ({})".format(mark, len(self.orphans))
                attr = c.A_BOLD
            elif row[0] == "orphan":
                o = self.orphans[row[1]]
                lead = self.lead(o["size"], (tokens(None), tokens(o["size"]), tokens(None)))
                text = lead + o["label"] + "  [{}]".format(owner_label(o))
                attr = self.heat_attr(o["size"]) | c.A_DIM
            elif row[0] == "group":
                group = row[1]
                launch, pulls, unmeasured, _, deepest = self.stats[group.key]
                mark = "▾" if group.key in self.left_open else "▸"
                count = len(group.roots) + len(group.sites)
                # By distance, a group's one number is what reading its files
                # spends, so the hops add up to what the meter shows.
                own = (sum(self.nodes[id]["size"] for id in group.roots)
                       if by == "distance" and group.key != SITES else pulls)
                lead = self.lead(own, (tokens(launch), "?" if unmeasured and not pulls else tokens(pulls), tokens(deepest)))
                text = lead + "{}{} {} ({})".format("  " * group.depth, mark, group.label, count)
                attr = self.heat_attr(own if not self.detail else pulls) | c.A_BOLD
            elif row[0] == "site":
                site = self.probe["remotes"][row[1]]
                lead = "◆" + blank[1:] + "  " * row[2]
                text = lead + row[1] + "  [{} {}]".format(
                    len(site["refs"]), "line" if len(site["refs"]) == 1 else "lines")
                attr = self.far
            else:
                _kind, id, depth = row
                n = self.nodes[id]
                launch = n["size"] if n["tier"] == LAUNCH else None
                deepest = max((depth_cost(self.nodes[m]) for m in self.g.pulled[id] & self.nodes.keys()),
                              default=0)
                lead = self.lead(n["closure"], (tokens(launch), tokens(n["closure"]), tokens(deepest))) + "  " * depth
                text = lead + n["label"] + tag(n) + self.return_tag(id)
                attr = self.heat_attr(n["closure"])
            if chosen:
                attr = (attr | c.A_REVERSE) if self.pane == 0 else (attr | c.A_UNDERLINE)
            self.put(i + head, 0, text, split, attr)
            if row[0] == "root":
                self.link(i + head, len(lead), n["label"], n["path"], split, attr)
            elif row[0] == "orphan":
                self.link(i + head, len(lead), o["label"], o["path"], split, attr)

        self.scroll(1, body)
        sort = SORTS[self.sort]
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
            shown = {"closure": n["closure"], "next": n["next"], "size": n["size"], "reach": spent}[sort]
            lead = self.lead(shown if measured else None, (
                tokens(spent), tokens(n["size"]) if measured else "?",
                tokens(n["next"]) if has_children else "-",
                tokens(n["closure"]) if measured else "?"))
            lead += "{}{} {}".format("  " * depth, mark, (edge + " ") if edge and self.detail else "")
            attr = self.heat_attr(n["closure"])
            if index == self.cursor[1] and self.pane == 1:
                attr |= c.A_REVERSE
            self.put(i + head, split + 1, lead + n["label"] + tag(n), width - split - 1, attr)
            self.link(i + head, split + 1 + len(lead), n["label"], n["path"], width, attr)

        for y in range(1, body + head):
            try:
                self.s.addch(y, split, c.ACS_VLINE)
            except c.error:
                pass
        when, via = self.details()
        path = self.selected_path()
        y = height - tail
        self.put(y, 0, "─" * width, width)
        if self.detail:
            self.put(y + 1, 0, " when  " + when, width, c.A_BOLD)
            self.put(y + 2, 0, " via   " + via, width)
            file_row, file_at = y + 3, 7
        else:
            # One line: how the probe reached the row, or an improvement's fix;
            # otherwise when the row loads.
            row = self.selected()
            fixing = self.pane == 0 and row is not None and row[0] in ("improvement", "orphan")
            how = via if via and (fixing or (self.probe is not None and self.term)) else when
            self.put(y + 1, 0, " " + how, width, c.A_BOLD)
            file_row, file_at = y + 2, 1
        if path:
            folder = os.path.dirname(path) + os.sep
            self.put(file_row, 0, (" file  " if self.detail else " ") + folder + os.path.basename(path), width, c.A_DIM if not self.detail else 0)
            self.link(file_row, file_at, folder, folder, width)
            self.link(file_row, file_at + len(folder), os.path.basename(path), path, width)
        elif self.detail:
            self.put(file_row, 0, " file", width)
        if self.detail:
            t = totals(self.nodes.values())
            footer = (" ~tokens: launch {} · every file {} · deepest path {} · unmeasured {}"
                      " · sort: {} · filter: {}").format(
                tokens(t["launch"]), tokens(t["reachable"]), tokens(t["deepest"]), t["unmeasured"],
                SORT_LABELS[sort], self.query or self.describe_base() or "none")
            if self.probe is not None:
                footer = " " + probe_summary(self.probe, self.nodes)
            self.put(height - 3, 0, "─" * width, width)
            self.put(height - 2, 0, footer, width)
            keys = (" ↑↓ move  tab pane  enter/space expand  ←→ collapse/expand  esc back  "
                    "s sort  g group by  p ask about  / filter  d less  q quit  ·  mouse: click, wheel, back; "
                    "cmd+click a file or folder to open it")
        else:
            keys = (" ↑↓ move  enter open  esc back  p ask about a term  g group  "
                    "s sort ({})  / filter  d details  q quit".format(SORT_LABELS[sort]))
        self.put(height - 1, 0, keys, width, c.A_DIM)
        self.s.refresh()
        self.emit_links()

    def heat_attr(self, n):
        return self.heat[heat_level(n)]

    def return_tag(self, id):
        """How the probe found a left-pane file: the lines mentioning the term,
        or that it is an island."""
        if self.probe is None or not self.term:
            return ""
        hit = self.probe["hits"].get(id)
        if hit is None:
            return "  [island]" if id in self.probe["islands"] else ""
        if hit["lines"]:
            return "  [{} {}]".format(len(hit["lines"]), "line" if len(hit["lines"]) == 1 else "lines")
        return "  [signpost only]"

    def selected_path(self):
        """The file under the cursor: the right pane's row, else the left's root."""
        if self.pane == 1 and self.right:
            return self.nodes[self.right[self.cursor[1]][0][-1]]["path"]
        row = self.selected()
        if row is not None and row[0] == "site":
            return None
        if row is not None and row[0] == "root":
            return self.nodes[row[1]]["path"]
        if row is not None and row[0] == "improvement":
            return self.nodes[self.improvements[row[1]]["id"]]["path"]
        if row is not None and row[0] == "orphan":
            return self.orphans[row[1]]["path"]
        return None

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
        if row[0] == "site":
            site = self.probe["remotes"][row[1]]
            first = site["refs"][0]
            return ("remote: a network round trip, and whatever {} serves that day".format(row[1]),
                    "{}:{}  {}".format(self.nodes[first["source"]]["label"], first["line"] or "?",
                                       first["text"]))
        if row[0] == "root" and self.probe is not None and self.term:
            return self.nodes[row[1]].get("when", ""), self.reached(row[1])
        if row[0] == "root":
            return self.nodes[row[1]].get("when", ""), "a root: the harness opens it"
        if row[0] == "insight":
            return self.insights[row[1]]["text"], "how: " + self.insights[row[1]]["query"]
        if row[0] == "improvement":
            x = self.improvements[row[1]]
            return ("{}, paid {}; the ideal is {}".format(x["text"].rstrip("."), x["paid"], x["goal"]),
                    "fix: " + x["repair"])
        if row[0] == "orphan":
            o = self.orphans[row[1]]
            fix = o.get("fix")
            return (o["advice"], "fix: " + ("{}:{}  {}".format(fix["file"], fix["line"] or "?", fix["text"])
                                            if fix else o["advice"]))
        return "", ""

    def reached(self, id):
        """How the probe reached a file, and the first line that mentions the term."""
        hit = self.probe["hits"].get(id)
        lines = self.probe["mentions"].get(id, [])
        first = "  \u201c{}\u201d".format(lines[0][:120]) if lines else ""
        if hit is None:
            return "an island: {}{}".format(island_advice(island_fix(self.g, self.probe, self.nodes, id),
                                                          self.term, self.nodes), first)
        if hit["hop"] == 0:
            return "loaded at launch; {} {} mention it{}".format(
                len(lines), "line" if len(lines) == 1 else "lines", first)
        via = self.nodes[hit["via"]]["label"]
        ref = self.g.refs.get((hit["via"], id, self.kinds.get((hit["via"], id), "")))
        how = ("{}:{}  {}".format(ref["file"], ref["line"] or "?", ref["text"]) if ref
               else "invoked from {}".format(via))
        return "hop {} from {}{}: {}".format(
            hit["hop"], via, "" if hit["signposted"] else " (the line never names it)", how)

    def describe_base(self):
        return " ".join("{}:{}".format(k, v) for k, vs in sorted(self.base.items()) for v in sorted(vs))

    # -- input ---------------------------------------------------------------

    def prompt(self, lead="/"):
        c = self.curses
        height, width = self.s.getmaxyx()
        self.put(height - 1, 0, lead, width)
        c.echo()
        try:
            c.curs_set(1)
        except c.error:
            pass
        try:
            raw = self.s.getstr(height - 1, len(lead), width - 1 - len(lead)).decode("utf-8", "replace")
        finally:
            c.noecho()
            try:
                c.curs_set(0)
            except c.error:
                pass
        return raw.strip()

    def remember(self):
        self.trail.append(dict(query=self.query, term=self.term, grouping=self.grouping,
                               cursor=list(self.cursor), top=list(self.top), pane=self.pane,
                               left_open=set(self.left_open), right_open=set(self.right_open)))

    def back(self):
        """One step back, as on the page: out of the right pane, else to the
        view before the last probe, filter, or regroup, else up to the group
        above the cursor."""
        if self.pane == 1:
            self.pane = 0
            return
        if self.trail:
            view = self.trail.pop()
            self.query, self.term, self.grouping = view["query"], view["term"], view["grouping"]
            self.apply()
            self.cursor, self.top, self.pane = view["cursor"], view["top"], view["pane"]
            self.left_open = view["left_open"]
            self.refresh_rows()
            self.right_open = view["right_open"]
            self.refresh_rows()
            # A view change repaints whole, as the probe prompt's does.
            self.s.clear()
            return
        self.open(False)

    def filter_prompt(self):
        self.remember()
        self.query = self.prompt()
        self.cursor = [0, 0]
        self.top = [0, 0]
        self.apply()

    def probe_prompt(self):
        """A term to probe for; an empty one shows everything by distance."""
        self.remember()
        self.term = self.prompt("ask about: ")
        self.grouping = GROUPINGS.index("distance")
        self.left_open = set(HEADS) & self.left_open
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
        sys.stdout.write(MOUSE_ON)
        sys.stdout.flush()
        try:
            self.loop()
        finally:
            sys.stdout.write(MOUSE_OFF)
            sys.stdout.flush()

    def loop(self):
        c = self.curses
        while True:
            self.draw()
            key = self.s.getch()
            rows = self.left if self.pane == 0 else self.right
            page = self.body
            if key == ord("q"):
                return
            if key == 27:
                sequence = self.read_escape()
                if sequence:
                    self.mouse(sequence)
                else:
                    self.back()
            elif key == c.KEY_MOUSE:
                # Where terminfo's kmous is the SGR prefix (Ubuntu's ncurses
                # 6.6 has it), curses reads it as KEY_MOUSE and leaves the
                # rest of the click unread.
                self.mouse("[<" + self.read_escape())
            elif key in (c.KEY_BACKSPACE, 127, 8):
                self.back()
            elif key == ord("d"):
                self.detail = not self.detail
            elif key == 9:
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
                self.regroup()
            elif key == ord("/"):
                self.filter_prompt()
                self.on_select()
            elif key == ord("p"):
                self.probe_prompt()
                self.on_select()
            elif key in (10, 13, 32, c.KEY_ENTER):
                self.toggle()
            elif key in (c.KEY_RIGHT, ord("l")):
                self.open(True)
            elif key in (c.KEY_LEFT, ord("h")):
                self.open(False)

    def regroup(self):
        self.remember()
        self.grouping = (self.grouping + 1) % len(GROUPINGS)
        self.left_open = set(HEADS) & self.left_open
        self.cursor = [0, 0]
        self.top = [0, 0]
        self.apply()
        self.on_select()

    def read_escape(self):
        """The rest of an escape sequence curses didn't recognize as a key."""
        self.s.nodelay(True)
        try:
            chars = []
            while len(chars) < 32:
                ch = self.s.getch()
                if ch == -1:
                    break
                chars.append(chr(ch))
                if chr(ch) in "Mm" and len(chars) > 1:
                    break
            return "".join(chars)
        finally:
            self.s.nodelay(False)

    def mouse(self, sequence):
        """A left click picks the pane and row under it, and on the row already
        picked expands or collapses it; the wheel moves the pane under it."""
        found = SGR_MOUSE.fullmatch(sequence)
        if not found:
            return
        button, x, y, kind = int(found[1]), int(found[2]) - 1, int(found[3]) - 1, found[4]
        if button == MOUSE_BACK:
            if kind == "M":
                self.back()
            return
        pane = 0 if x < self.split else 1
        rows = self.left if pane == 0 else self.right
        if button in (WHEEL_UP, WHEEL_DOWN):
            self.pane = pane
            self.move(-3 if button == WHEEL_UP else 3, rows)
            return
        if button != 0 or kind != "M":
            return
        if pane == 0 and y in ((1, 2) if self.detail else (1,)):
            self.regroup()
            return
        index = self.top[pane] + y - self.head
        if not 0 <= y - self.head < self.body or index >= len(rows):
            self.pane = pane
            return
        if pane == self.pane and index == self.cursor[pane]:
            self.toggle()
            return
        self.pane = pane
        self.move(index - self.cursor[pane], rows)

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
            if row[0] in HEADS:
                self.left_open ^= {row[0]}
            elif row[0] in ("insight", "improvement", "orphan"):
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
            if row[0] in HEADS:
                (self.left_open.add if expand else self.left_open.discard)(row[0])
            elif row[0] in ("insight", "improvement", "orphan"):
                if expand:
                    self.pane = 1
                else:
                    head = {"insight": INSIGHTS, "improvement": IDEAL, "orphan": ORPHANS}[row[0]]
                    self.cursor[0] = next(i for i, r in enumerate(self.left) if r[0] == head)
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
            if row[0] in HEADS:
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
        cache_path = remote_cache_path()
        cache = read_remote_cache(cache_path)
    except RuntimeError as exc:
        sys.stderr.write("cleat: {}\n".format(exc))
        return 2
    if getattr(args, "measure_remote", False):
        cache = measure_remotes(filtered(g, filters)[0], cache, cache_path)
    attach_remote_sizes(g.nodes, cache)
    if interactive:
        browse(g, filters, args.probe)
        return 0
    nodes, edges = filtered(g, filters)
    data = as_json(directory.resolve(), g, nodes, edges, filters)
    if args.probe is not None:
        data["probe"] = probe_public(g, probe(g, nodes, args.probe), nodes)
    if args.html is not None:
        status = write_page(data, args.html, {id: g.texts[id] for id in nodes if id in g.texts})
        if status:
            return status
    if args.json:
        json.dump(data, sys.stdout, indent=2)
        sys.stdout.write("\n")
    return 0


def write_page(data, target, texts):
    """Write the page to target, or with no target to a new temporary file that
    then opens in the default browser."""
    try:
        page = render_html(data, texts)
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
