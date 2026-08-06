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
