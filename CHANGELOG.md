# Changelog

## 0.3.0

### Added
- `cleat check` reports `restated`, an advisory, when a run of three or more
  lines is copied between two documentation files, and keeps the copy in the
  file with the wider audience.
- `cleat check` reports `narrowing-ref`, an error, when a relative link points
  toward a narrower audience, such as a `docs/` page linking into the repo or
  `AGENTS.md` linking `CLAUDE.md`. A repo whose check was green can report it
  after upgrading.
- Before a write adds guidance to `CLAUDE.md`, `AGENTS.md`, or a topic rule,
  cleat asks once per file per session whether a hook could enforce it,
  whether every session needs it, and whether it's already written elsewhere.
  Re-issuing the same write lets it through.
- Rules directories beyond `.claude/rules/` are configured with
  `git config --add cleat.rulesDir <dir>`.
- A `CLAUDE.md` that is only the pointer, in a repo with no `AGENTS.md`, is
  reported as `dangling-ref`, with the repair to write `AGENTS.md`. It was
  reported as `no-agents`, whose repair asked for the pointer it already was.
- A topic rule whose glob is absolute, climbs out of the repo with `..`, or
  expands to more than 64 patterns is reported as `bad-glob` instead of being
  classified.

### Changed
- Re-issuing a denied write exempts that file for the rest of the session.
- The nudge also runs on writes to documentation files, and reports a finding
  once while it persists.
- The pointer `CLAUDE.md` cleat asks for is the single line `@AGENTS.md`, the
  shape Claude Code's docs give. A pointer that also links to `AGENTS.md` still
  passes the check.
- A hook run without `CLAUDE_PLUGIN_DATA` reports that in a `systemMessage`
  instead of keeping session state under a guessed path, which was right only
  for installs from one marketplace.
- Reading an `AGENTS.md` with no `CLAUDE.md` beside it no longer triggers a
  bootstrap offer, since Claude Code reads that `AGENTS.md` at startup by
  default. `cleat check` still reports `no-claude` as an advisory for the
  sessions that skip it. A `CLAUDE.md` without the `@AGENTS.md` ref still gets
  the offer.
- When the smallest index a repo's rules allow is itself over budget,
  `toc-bloat`'s repair says to consolidate rules into fewer glob sets, and the
  nudge no longer pastes rows that wouldn't clear it. A `toc-bloat` within
  budget now comes with the rendered index, as `unlisted-rule` does.
- A blank `AGENTS.md` no longer lets a full `CLAUDE.md` past the write gate.

### Fixed
- `cleat check` and the hooks no longer hang on a repo with a directory symlink
  cycle, or on a rule glob with many brace groups.

## 0.2.0

### Added
- First release. cleat keeps a repo's agent instructions in one canonical
  `AGENTS.md` with `CLAUDE.md` reduced to a pointer that imports it, so the same
  guidance reaches Claude Code and the tools that read `AGENTS.md`. Three hooks
  and no commands: a `PreToolUse` gate that stops a substantive `CLAUDE.md` write
  in a repo with no `AGENTS.md` and asks for it as two writes, a `PostToolUse`
  nudge that reports near-miss shapes with their repairs for in-turn correction,
  and a `PostToolUse` `Read` trigger that offers to bootstrap the convention
  where it's absent. `cleat check` reports the same findings from the command
  line, exiting non-zero on errors and green on advisories. (#1)
- cleat offers itself to sessions already working with agent instruction files.
  A session that reads `.cursorrules`, `.cursor/rules`,
  `.github/copilot-instructions.md`, `.windsurfrules`, `GEMINI.md`, or
  `AGENTS.md` sees an install suggestion for cleat. Suggestions appear only
  where an administrator has allowlisted this marketplace in managed settings'
  `pluginSuggestionMarketplaces`.
- `.claude/rules/` is a supported home for topic guidance, so long as
  `AGENTS.md` indexes it. `cleat check` reports a path-scoped rule the index
  misses, a row naming a rule whose globs match no file, and an index grown past
  what every session pays to load it. `cleat index` prints the index a repo
  should carry, derived from the rules themselves.
