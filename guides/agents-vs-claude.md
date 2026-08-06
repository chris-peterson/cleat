# Which guidance goes where

You're reading this because a `CLAUDE.md` write was denied and you need to split
it. `AGENTS.md` takes the body; `CLAUDE.md` becomes the pointer plus whatever
remainder is genuinely Claude-specific.

## The test

**Would Cursor, Codex, or Copilot act correctly on this line?**

If yes, it belongs in `AGENTS.md`. Everything a project knows about itself — how
to build it, what its words mean, which patterns it holds to — is true regardless
of which agent is reading. That is nearly all of a normal instruction file.

If the line only means something to Claude Code — it names a slash command, a
hook event, a `settings.json` key — it stays in `CLAUDE.md`, below the ref.

## Tool-agnostic → `AGENTS.md`

- What the project is and does
- Build, test, lint, and run commands
- Repo layout, and which files are generated
- Code conventions, naming, error-handling posture
- Domain glossary and key abstractions
- Architecture constraints and the reasons behind them
- Commit, branch, and review conventions
- Environment and dependency setup
- Security and data-handling rules

## Claude-specific → below the ref in `CLAUDE.md`

- Slash commands and skills (`/deploy`, `skills/*/SKILL.md`)
- Hooks and hook events (`PreToolUse`, `SessionStart`)
- `settings.json`, permissions, and allowlists
- Plugins and marketplaces
- Subagent definitions and delegation instructions
- Claude Code tool names where the instruction is about the tool rather than the
  task (`use Grep rather than shelling out to grep`)
- `@`-imports of other files

## When it's ambiguous, put it in `AGENTS.md`

The two errors are not symmetric. A line in `AGENTS.md` that only Claude can act
on is read and ignored by everything else — a few wasted tokens. A line kept in
`CLAUDE.md` that every tool needed is invisible to all of them, and nothing
reports the absence. Bias toward `AGENTS.md`.

## Worked splits

**MCP servers.** The fact that the project talks to a particular service, and
what that service is for, is tool-agnostic. The `.mcp.json` wiring that connects
Claude Code to it is not. Describe the service in `AGENTS.md`; keep the
configuration note in `CLAUDE.md`.

**"Run the tests with `/verify` before committing."** Two claims wearing one
sentence. `AGENTS.md` gets the requirement — tests pass before a commit, and the
command that runs them. `CLAUDE.md` gets the shortcut.

**Tool-usage preferences.** "Prefer ripgrep over find" is advice any agent can
take: `AGENTS.md`. "Use the Read tool rather than `cat`" names a Claude Code tool:
`CLAUDE.md`.

**A rival tool's config.** `.cursorrules`, `.windsurfrules`,
`.github/copilot-instructions.md`, `GEMINI.md` — the guidance inside these is
almost always tool-agnostic and should be consolidated into `AGENTS.md`. The
tool-specific residue, if there is any, stays in the tool's own file.

## The shape you're writing toward

`CLAUDE.md`:

```markdown
Agent instructions live in [AGENTS.md](./AGENTS.md).

@AGENTS.md

## Claude Code

- `/deploy` runs the staging deploy; it needs `AWS_PROFILE` set.
```

An import, not a symlink — a symlink surprises whoever opens the file next, and
`CLAUDE.md` has a legitimate use beyond pointing. And the ref is what does the
work: the markdown link above it is for humans, and Claude Code loads nothing
from it.

## If it really is all Claude-specific

Re-issue the identical write. cleat remembers what it denied for the rest of the
session and lets a byte-identical retry through, then forgets it.
