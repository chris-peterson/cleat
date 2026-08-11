# cleat

A Claude Code plugin that holds a repository's agent instructions in one
canonical `AGENTS.md`, with `CLAUDE.md` reduced to a pointer that imports it.
Claude Code reads `CLAUDE.md` and does not read `AGENTS.md`; roughly 30 other
tools read `AGENTS.md`. The pointer shape is what makes one body of guidance
reach both.

`SPEC.md` is the requirement source of record and `STATUS.md` is its coverage
ledger. Both are part of the diff — a change to behavior updates the requirement
and the ledger in the same commit, not as a follow-up.

## Commands

```bash
just test         # the bash test suite under scripts/tests/
just check        # validate source and diff the pending projection (the CI gate)
just generate     # regenerate plugin.json, hooks.json, docs/ from source
just self-check   # cleat's findings for this repo — it must hold its own shape
```

## Layout

```text
plugin.yml              source of record for metadata and marketplace copy
hooks/hooks.yml         source of record for the three hook registrations
hooks/prefilter.sh      the bash prefilter fronting every registration
scripts/cleat           the CLI: `check` and `hook`
scripts/tests/          bash test suite
guides/                 the tool-agnostic vs Claude-specific rubric
SPEC.md / STATUS.md     requirements and their coverage
docs/                   docsify site (README, _sidebar, favicon are source)
```

`.claude-plugin/plugin.json`, `hooks/hooks.json`, and most of `docs/` are
**generated** by `shipyard` from the sources above. Never hand-edit a generated
file; edit its source and run `just generate`.

## Conventions

- **`scripts/cleat` is python3, standard library only.** No third-party imports,
  no virtualenv. It runs from a hook, where a missing dependency is a silent
  failure.
- **A hook always exits 0.** `cleat hook` communicates through
  `hookSpecificOutput` on stdout, never through its exit code — a non-zero exit
  from a hook is a different signal to Claude Code than a deny decision.
- **The prefilter never starts an interpreter it doesn't have to.** `Read` is the
  highest-frequency tool in a session. Anything added to the hot path belongs in
  `hooks/prefilter.sh` as a substring test, not in the CLI.
- **The check decides facts; the model decides judgment.** Which files exist,
  whether the ref is present, whether two files duplicate each other — all
  script-side. What counts as *tool-agnostic* is a judgment call, so the deny
  reason carries the short-form rubric and names `guides/` for the long form.
- **No fallbacks.** If the check can't read a file or the payload doesn't parse,
  surface it; don't degrade to a guess.
- **Findings carry a severity.** Errors drive the exit code; advisories
  (`unguided`, heading-only duplication) are reported and leave the check green,
  because a repo may legitimately sit that way.

## Glossary

- **Pointer shape** — `CLAUDE.md` as a link to `AGENTS.md` plus the `@AGENTS.md`
  ref, optionally followed by genuinely Claude-specific guidance. An import
  rather than a symlink: a symlink surprises whoever opens the file next, and
  `CLAUDE.md` has a use beyond pointing.
- **Ref** — the `@AGENTS.md` import line. A markdown link alone does not load
  the file.
- **Inversion** — `AGENTS.md` as a stub pointing back at `CLAUDE.md`, so every
  non-Claude tool gets the stub.
- **Foreign config** — a single-tool instruction file (`.cursorrules`,
  `.cursor/rules/*`, `.github/copilot-instructions.md`, `.windsurfrules`,
  `GEMINI.md`) holding guidance the other tools ignore.
- **Graceful degradation** — restating Claude-only operational config
  (`.claude/hooks`, `.claude/settings.json`, `.mcp.json`, …) in `AGENTS.md` as
  something a tool that only reads `AGENTS.md` can act on: a hook's rule as a
  rule to follow, a permission as what is safe to run unprompted. The
  enforcement stays Claude-only; the intent travels. Nothing is moved — most of
  it is consumed by the harness, which no prose can reach.
- **Re-issue record** — the `sha256(session_id, path, content)` receipt a deny
  leaves behind, so an identical re-issue of a `CLAUDE.md` that genuinely is all
  Claude-specific passes on the second try. One speed bump, not a wall.
