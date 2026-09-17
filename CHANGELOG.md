# Changelog

## Unreleased

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
