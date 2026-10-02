# Feedback loops

cleat decides where guidance belongs by when it reaches the agent. This page is
the model behind those decisions: the four kinds of guidance an agent gets,
which to invest in, and how to tell whether each one works. For the background,
what each kind costs and why a block can't do the job alone, see
[Harness engineering](/harness-engineering).

## Feedforward and feedback

Feedforward reaches the agent before it acts and makes a mistake less likely.
Feedback reaches it after, and is the only thing that catches one. Each splits
on one more question, and the answer decides what it costs and how far to trust
it:

- **Feedforward: does it load in every session?** Always-on guidance is paid for
  in every session, whether that session needs it or not. Just-in-time guidance
  costs context only when its trigger fires, and arrives when the agent needs
  it, before there's a mistake to catch.
- **Feedback: can the agent decline it?** Advisory feedback can be declined.
  Blocking feedback can't, which makes it the backstop for what still gets
  through.

Move what you can from always-on to just-in-time. Judge the harness by what
still reaches review across many edits. A single edit's path depends on how the
harness and the model's own judgment interact, so it can't be predicted, and
credit for one element comes from comparing outcomes with it turned off.

What makes a hook feedforward is when it fires relative to the act it's about.
Guidance on a read arrives before the edit it shapes, so it's feedforward. A
check on a write judges content the agent already drafted, so it's feedback,
even from a `PreToolUse` hook that runs before the write lands.

## Pair a rule with a hook

Guidance scoped to the act and delivered just before it works best. Most
guidance can't be scoped that tightly, and none of it is guaranteed to be
followed, so the strongest placement is often a pair: feedforward that makes the
mistake less likely, and feedback that catches what gets through.

Em dashes in prose are a worked case:

- **The rule** is one always-on line: no em dashes; recast with a comma, a
  colon, parentheses, or two sentences.
- **The hook** blocks a reply or a prose write that carries one. A regex finds
  an em dash with full precision, so the block never misfires.
- **Together** they measure each other. Every block is a case the rule didn't
  prevent, so a hook that marks its catches with a stable string gives the rule
  a miss rate, the one measure always-on feedforward otherwise lacks.

Running the pair taught two things. Feedback fixed every instance it blocked,
but not the habit: the same trigger came back later in the session. And
just-in-time feedforward can work against an always-on rule: drafts written
from a skill whose own text was full of em dashes were blocked far more often
than other prose. Guidance loaded at the moment of drafting sets the style of
what follows it, so a skill's own text is part of the guidance it gives.

## Nested instruction files

An instruction file in a subdirectory, such as a package in a monorepo, loads
when the agent works there, and every session elsewhere in the repo skips it.
That makes it just-in-time feedforward triggered by the directory. Its trigger
is as loose as a glob: any read in the directory loads it, not only a read
ahead of an edit, so it suits conventions that apply to most work there.

Each tool loads a nested `AGENTS.md` its own way:

| Tool | How a nested `AGENTS.md` combines | When it loads |
|---|---|---|
| Claude Code | Concatenated after the parent directories' files, through the `CLAUDE.md` beside it that imports it | When a file in that directory is read |
| Cursor | Combined with the parent directories' files, the more specific taking precedence | When working with files in that directory or below |
| GitHub Copilot | The nearest one to the file takes precedence | When working on a file under it |
| Codex | One per directory from the repo root down to the working directory, later ones overriding earlier | At launch; files below the working directory aren't read |

Claude Code needs the `CLAUDE.md` beside a nested `AGENTS.md` because it reads
an `AGENTS.md` directly only where no `CLAUDE.md`, `.claude/CLAUDE.md`, or
`CLAUDE.local.md` sits in the working directory or above it. A repo in cleat's
shape has one at the root, so the pointer repeats in each directory that has
its own guidance.

A `.claude/rules/` directory can sit below the root too. Claude Code loads its
rules when it reads a file in that directory, and their `paths:` globs are
relative to the directory that holds `.claude/`, not to the repo root. A rule
there without `paths:` is scoped to the directory rather than loaded in every
session. The Claude Code docs don't state the glob anchoring; it was checked
against Claude Code 2.1.287.

Sources: Claude Code's
[memory](https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md)
and [large codebase](https://code.claude.com/docs/en/large-codebases) docs,
[Cursor rules](https://cursor.com/docs/context/rules),
[Copilot repository instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions),
and [Codex's AGENTS.md guide](https://developers.openai.com/codex/guides/agents-md).
