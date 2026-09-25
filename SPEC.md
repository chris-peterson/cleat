# cleat — Specification

cleat is a Claude Code plugin that routes a repository's agent instructions to
the widest reader that can act on them. Guidance lives in `AGENTS.md`, read by
Claude Code and the ~30 other tools, with `CLAUDE.md` reduced to a pointer at it.
Scoping metadata may be tool-specific: `.claude/rules/` holds topic rules that
only Claude Code loads, and loads on demand, so long as `AGENTS.md` indexes them
— a tool that cannot load a rule can still find it. Enforcement is hooks only: a
write gate, an in-turn repair nudge, and bootstrap guidance for repos where the
convention is absent.

Requirements use [EARS syntax](https://alistairmavin.com/ears) — each is one of:
Ubiquitous (`The <system> shall …`), State-Driven (`While …`), Event-Driven
(`When …`), Optional (`Where …`), or Unwanted Behaviour (`If … then …`).

## Concepts

- **`AGENTS.md`** — the tool-agnostic agent instruction file, read by roughly 30
  coding tools. In the target shape it is the **canonical** location: guidance
  lives here, and what a rules directory holds instead is indexed from here.
- **`CLAUDE.md`** — Claude Code's own instruction file, and the one it always
  loads. Since v2.1.277 Claude Code also reads `AGENTS.md` directly, but only
  where no `CLAUDE.md` or `CLAUDE.local.md` sits in the working directory or
  above it, and only in a session that fetches feature flags — so not on Bedrock
  or another third-party provider, not with telemetry disabled, and not in the
  first session after an upgrade. The pointer shape is what makes the load
  unconditional across all of them.
- **Pointer shape** — a `CLAUDE.md` whose body is a link to `AGENTS.md` plus the
  `@AGENTS.md` ref, optionally followed by Claude-specific guidance (slash
  commands, hooks, `settings.json`). An import rather than a symlink, because
  `CLAUDE.md` has a legitimate use beyond pointing.
- **Ref** — the `@AGENTS.md` import line inside `CLAUDE.md`. Its presence is what
  makes the pointer load `AGENTS.md`; a link alone does not.
- **Substantive content** — a file body that is more than whitespace and more
  than the pointer shape. The gate acts on substantive `CLAUDE.md` content only.
- **Inversion** — the reverse of the target shape: `AGENTS.md` is a stub pointing
  back at `CLAUDE.md`, so every non-Claude tool gets the stub.
- **Foreign config** — a single-tool instruction file (`.cursorrules`,
  `.cursor/rules/*`, `.github/copilot-instructions.md`, `.windsurfrules`,
  `GEMINI.md`) holding guidance every other tool ignores. `.claude/rules/` is not
  one: it is the location cleat recommends for topic rules, because Claude Code
  loads a path-scoped rule only when it reads a matching file, and no import
  mechanism does that — an `@path` import loads at launch whatever it costs.
- **Topic rule** — a markdown file under `.claude/rules/`, discovered
  recursively. **Always-on** when it carries no `paths:` frontmatter,
  **path-scoped** when its globs can match a file, **retired** when every glob it
  carries can match nothing.
- **Rules index** — the rows of `AGENTS.md` that name topic rules and the globs
  they answer to. It is what carries a path-scoped rule to a tool that cannot
  load one. Every reader pays for it at launch, in every session, so it indexes
  the path-scoped rules and covers the always-on ones with a single line: a tool
  that cannot scope must read all of those anyway, and their names buy it
  nothing.
- **Finding** — one code, the path it concerns, a severity, and the repair that
  clears it. The ten codes are `no-agents`, `no-claude`, `no-ref`, `inverted`,
  `duplicated`, `unguided`, `foreign-config`, `unlisted-rule`,
  `dead-rule-listed`, `toc-bloat`.
- **Severity** — a finding is either an **error** (the shape is broken; drives
  the exit code) or an **advisory** (reported, but a repo can legitimately sit
  this way). `unguided` and heading-only duplication are advisories: a repo may
  have chosen to carry no agent guidance, and a shared `## Commands` heading in
  both files is not itself a defect.
- **Re-issue record** — the receipt a deny leaves behind:
  `sha256(session_id, path, content)` under the plugin's data dir. An identical
  re-issue of the denied write matches it and is allowed through once.
- **Prefilter** — the pure-bash script fronting every hook registration. It
  reads the payload on stdin and exits unless the payload looks like a
  candidate, so the common path never starts a python interpreter.
- **Rubric** — the file defining the tool-agnostic / Claude-specific split. A
  file rather than a skill, so it costs nothing until a deny names its path.

## Requirements

### CHECK — The check command

- [CHECK-01] The system shall provide `cleat check [DIR]`, reporting findings for
  `DIR` and defaulting to the current directory.
- [CHECK-02] `cleat check` shall exit 1 when it reports one or more error findings
  and 0 otherwise, so advisories alone leave the check green.
- [CHECK-03] Where `--json` is passed, `cleat check` shall emit its findings as
  JSON on stdout.
- [CHECK-04] When `CLAUDE.md` has substantive content and no `AGENTS.md` sibling
  exists, the check shall report `no-agents`.
- [CHECK-05] When `AGENTS.md` exists and no `CLAUDE.md` exists, the check shall
  report `no-claude` as an advisory. Claude Code reads the `AGENTS.md` by
  default, so the repo is guided; what the missing pointer costs is the
  sessions where direct reading is off — a third-party provider, telemetry
  disabled, the first session after an upgrade — plus `/memory` and `/context`
  listing and `InstructionsLoaded` hooks, none of which fire for an `AGENTS.md`
  read directly. That is a portability gap, not an unguided repo, and the two
  are worth telling apart.
- [CHECK-06] When both files exist and `CLAUDE.md` carries no `@AGENTS.md` import
  line, the check shall report `no-ref`.
- [CHECK-07] When `AGENTS.md` points at `CLAUDE.md`, the check shall report
  `inverted`.
- [CHECK-08] When the two files overlap in content, the check shall report
  `duplicated`.
- [CHECK-09] When neither file exists, the check shall report `unguided`.
- [CHECK-10] When a foreign config is present, the check shall report
  `foreign-config` naming that path.
- [CHECK-11] The check shall report duplication in two tiers: identical normalized
  headings present in both files as advisory, and identical normalized
  non-heading lines of 40 or more characters as the substantive signal.
- [CHECK-12] `unguided` shall be reported by `check` only, since no write hook has
  a write to act on.
- [CHECK-13] Each finding shall carry the repair that clears it: create the
  pointer, add the ref, flip the inversion, or delete the duplicated content
  from `CLAUDE.md`.
- [CHECK-14] Each finding shall carry a severity. `no-agents`, `no-ref`,
  `inverted`, `foreign-config`, `unlisted-rule`, `dead-rule-listed`, and
  line-level `duplicated` shall be errors; `no-claude`, `unguided`,
  `toc-bloat`, and heading-only `duplicated` shall be advisories.

### RULE — Topic rules and the index

- [RULE-01] The system shall discover topic rules as the `*.md` files under
  `.claude/rules/`, searching recursively.
- [RULE-02] The system shall classify each topic rule from its `paths:`
  frontmatter: always-on where the field is absent, retired where every glob it
  lists can match nothing, and path-scoped otherwise.
- [RULE-03] When a path-scoped rule's filename appears nowhere in `AGENTS.md`,
  the check shall report `unlisted-rule`, naming that rule.
- [RULE-04] When a retired rule's filename appears in `AGENTS.md`, the check
  shall report `dead-rule-listed`, naming that rule.
- [RULE-05] When the `AGENTS.md` lines naming topic rules exceed 2048 bytes in
  total, or name more than half the always-on rules, the check shall report
  `toc-bloat`.
- [RULE-06] The index shall be measured as the `AGENTS.md` lines that name a
  topic rule, so no heading convention is imposed on `AGENTS.md`.
- [RULE-07] Where the rules directory resolves under `$HOME/.claude`, the system
  shall report no rules findings, user-scope rules having no `AGENTS.md` to be
  indexed from.
- [RULE-08] Where `.claude/rules/` is absent or holds no rule, the system shall
  report no rules findings, so the convention costs a repo that has not adopted
  it nothing.
- [RULE-09] Where `AGENTS.md` is absent, the system shall report no rules
  findings, the missing pointer being the prior repair.

### INDEX — The index projector

- [INDEX-01] The system shall provide `cleat index [DIR]`, printing the rules
  index `AGENTS.md` should carry for `DIR` and defaulting to the current
  directory.
- [INDEX-02] The projector shall render the always-on rules as one line, the
  path-scoped rules as a row per distinct glob set, and the retired rules not at
  all.
- [INDEX-03] The projector shall write no file, the placement of the index within
  `AGENTS.md`'s prose being the reader's judgment rather than the check's fact.
- [INDEX-04] The index the projector prints shall clear `unlisted-rule`,
  `dead-rule-listed`, and `toc-bloat` for the directory it was rendered from.
- [INDEX-05] The projector shall run under the same constraints as the rest of the
  CLI — python3, standard library only — so a repo adopting the convention needs
  nothing installed to keep its index current.
- [INDEX-06] When the nudge reports an index finding, it shall carry the rendered
  index as `additionalContext`, composing the index by hand being where it
  drifts from the directory.

### HOOK — Hook dispatch

- [HOOK-01] `cleat hook` shall read the hook payload from stdin and dispatch on
  `hook_event_name`.
- [HOOK-02] `cleat hook` shall always exit 0, whatever it decides.
- [HOOK-03] `cleat hook` shall emit its decision as `hookSpecificOutput`.
- [HOOK-04] When the tool is `Write`, the hook shall judge `tool_input.content`.
- [HOOK-05] When the tool is `Edit`, the hook shall judge the on-disk file with
  `old_string` replaced by `new_string`.
- [HOOK-06] The plugin shall register exactly three hooks: `PreToolUse` on
  `Write|Edit`, `PostToolUse` on `Write|Edit`, and `PostToolUse` on `Read`.

### GATE — The write gate

- [GATE-01] The gate shall consider a write in scope when the target's basename
  is `CLAUDE.md`.
- [GATE-02] If the target is under `$HOME/.claude`, then the gate shall allow it
  untouched, user-scope memory being Claude-specific by nature.
- [GATE-03] If the target is `CLAUDE.local.md`, then the gate shall allow it
  untouched.
- [GATE-04] When a sibling `AGENTS.md` exists, the gate shall allow the write
  silently.
- [GATE-05] When the written content is empty or already the pointer shape, the
  gate shall allow the write, the dangling ref being the nudge's concern.
- [GATE-06] Otherwise the gate shall deny the write with a reason carrying why,
  the instruction to re-issue as two writes — tool-agnostic body to `AGENTS.md`,
  `CLAUDE.md` as the pointer plus any Claude-specific remainder — the short-form
  rubric, and the rubric file's path.
- [GATE-07] When the gate denies a write, it shall record
  `sha256(session_id, path, content)` under the plugin's data dir.
- [GATE-08] When a write matches an existing re-issue record, the gate shall
  allow it and clear the record.
- [GATE-09] The re-issue record shall be scoped to the session that produced the
  deny, so a stale record cannot pass a later write.

### NUDGE — The repair nudge

- [NUDGE-01] When a write to `CLAUDE.md` or `AGENTS.md` completes, the nudge shall
  run the check against that directory.
- [NUDGE-02] The nudge shall return the findings and their repairs as
  `additionalContext`, so the shape can be corrected in the same turn.
- [NUDGE-03] The nudge shall treat `AGENTS.md` as canonical, directing every
  duplication repair at `CLAUDE.md`.
- [NUDGE-04] If the finding set is unchanged from the last nudge in this session,
  then the nudge shall stay silent, so a finding the model will not clear cannot
  loop.
- [NUDGE-05] When a write under `.claude/rules/` completes, the nudge shall run
  the check against the directory that owns the rules directory rather than the
  rule's own parent, a new rule being unindexed by construction.

### BOOT — Bootstrap guidance

- [BOOT-01] When `AGENTS.md` is read in a directory with no `CLAUDE.md`, or with
  a `CLAUDE.md` carrying no ref, the system shall surface that the guidance
  should have been loaded at startup and offer to add the pointer.
- [BOOT-02] When a root `README.md` or `CONTRIBUTING.md` is read in a directory
  where neither instruction file exists, the system shall offer to bootstrap
  `AGENTS.md` plus the pointer.
- [BOOT-03] When a foreign tool's config is read, the system shall offer to
  consolidate it into `AGENTS.md`.
- [BOOT-04] Each bootstrap trigger shall fire at most once per session per
  directory.
- [BOOT-05] Each bootstrap trigger shall emit both `systemMessage`, so the user
  sees it, and `additionalContext`, so the model can act on a yes.

### PREFILTER — Prefilter and cost

- [PREFILTER-01] A single pure-bash prefilter shall front all three hook
  registrations.
- [PREFILTER-02] The prefilter shall read the payload on stdin and exit unless the raw
  payload contains one of a fixed set of substrings.
- [PREFILTER-03] The prefilter shall invoke neither `jq` nor python.
- [PREFILTER-04] If a payload is not a candidate, then no python process shall be
  spawned for it.

### PACKAGING — Packaging and layout

- [PACKAGING-01] `plugin.yml` shall be the source of record; `hooks/hooks.json`,
  `.claude-plugin/plugin.json`, and `docs/` shall be generated from source.
- [PACKAGING-02] The plugin shall declare suite group `record` and activations
  `[agent]`.
- [PACKAGING-03] The plugin shall register no commands and ship no skills, keeping
  nothing resident in session context.
- [PACKAGING-04] `scripts/cleat` shall run on python3 with the standard library only.
- [PACKAGING-05] The rubric shall be a file the deny reason names by path, read only
  when a deny happens.
- [PACKAGING-06] cleat's own repository shall hold the shape it enforces — `AGENTS.md`
  canonical plus a pointer `CLAUDE.md` — and shall pass `cleat check`.
- [PACKAGING-07] `cleat check`'s verdict for each shape in the founding issue's grading
  table shall agree with that table: the two A rows clean, the D row `inverted`,
  the C rows `no-claude`, and the F rows `unguided`. A disagreement is a defect in
  the check.

### STATE — Session state

- [STATE-01] Hook state shall live under `$CLAUDE_PLUGIN_DATA` when Claude Code sets
  it, and otherwise under the same canonical path derived from Claude Code's
  `<plugin>-<owner>` data-dir convention.
- [STATE-02] Hook state shall be partitioned by session, so the gate's re-issue
  record, the nudge's last reported finding set, and the bootstrap triggers
  already fired all expire together with the session that made them.
- [STATE-03] The plugin shall prune session state older than seven days, so state
  written on every session cannot grow without bound.

## Future Requirements

- [FUTURE-01] (→ GATE) Where the deny round trip proves expensive in practice, the
  gate may instead use `PreToolUse` `updatedInput` to retarget the write to
  `AGENTS.md`. Deferred: silently retargeting a write is surprising, and it
  assumes the content is tool-agnostic.
