# Background

What you need to know before the rest of this site: what an instruction file
is, what it costs to load one, and the other ways guidance can reach a coding
agent.

## Instruction files

A coding agent starts every session knowing nothing about your repo. An
instruction file is a markdown file in the repo that the agent loads on its
own: the commands to build and test, the conventions to follow, the mistakes to
avoid. You write it once, and every session starts with it.

Two filenames matter:

| File | Read by |
| --- | --- |
| `AGENTS.md` | Most coding tools, among them Cursor, Codex, and GitHub Copilot |
| `CLAUDE.md` | Claude Code, in every session |

Claude Code also reads `AGENTS.md`, but only where no `CLAUDE.md` sits in the
working directory or above it, and not in every session. Guidance kept in only
one of the two files reaches some tools and not others. cleat keeps a repo in
the shape that reaches all of them: the guidance in `AGENTS.md`, and
`CLAUDE.md` a one-line pointer that imports it. [Home](/) shows that shape.

## The context window

Everything the agent knows during a session sits in its context window: your
messages, the files it has read, the output of the commands it ran, and every
instruction file it loaded. The window is finite, and everything in it competes
for the model's attention. An instruction file loaded at launch is paid for in
every session, whether that session needs it or not, and the longer it grows,
the less of it gets followed.

## Context tiering

Not all guidance has to load at launch. Each tool offers ways to load guidance
only when it applies, and each way is a tier:

| Tier | Loads | Example |
| --- | --- | --- |
| Every session | At launch | `AGENTS.md` or `CLAUDE.md` at the repo root |
| By directory | When the agent works in that directory | A nested `AGENTS.md` in one package of a monorepo |
| By file | When the agent reads a file matching a pattern | A Claude Code rule in `.claude/rules/` with `paths:` globs |
| By task | When the task calls for it | A Claude Code skill: its one-line description loads at launch, the rest when it's used |

Context tiering is placing each piece of guidance in the narrowest tier that
still reaches the agent when it's needed. A testing convention that matters
only in `*.test.ts` files costs nothing in a session that never opens one.

## Hooks

A hook is a command Claude Code runs at a fixed point in a session, such as
just before or just after a tool call. It runs outside the model, so it takes
no room in the context window until it fires. When it fires, it can stop the
action, or add a message the agent reads before its next step.

Hooks are how cleat works: it has no commands to run and loads nothing at
launch. It checks each write to an instruction file, and reports what's off in
the same turn.

## Next

The tiers above are guidance given *before* the agent acts. Hooks can also
check its work *after*. [Harness engineering](/harness-engineering) puts both
together, with what each costs and when to use which.
