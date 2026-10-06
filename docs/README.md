<div class="ph-hero" style="--accent: var(--color-green)">

<h1 class="ph-lede"><span class="ph-name">cleat</span> your instructions once, for any agent.</h1>

<div class="ph-badge"><img class="ph-mark" src="favicon.svg" alt="cleat" width="26" height="26">

[](_tags.md ':include')

</div>

</div>

Teams evaluating AI coding tools are rarely on one. `AGENTS.md` is the file most
of them read. Claude Code always reads `CLAUDE.md`, and reads `AGENTS.md` only
where no `CLAUDE.md` sits at or above the working directory, and not in every
session. Guidance kept in either file alone reaches some of your tools and misses
others. cleat holds a repo in the one shape that satisfies both, using hooks, so
there's no command to remember, and nothing sitting in your context window.

cleat is one layer of a harness: the guidance and checks around a coding agent
that steer its work. [Harness engineering](/harness-engineering) shows each
kind of layer as a toddler at a hot stove, with what each one costs, and the
[lab](/lab) lets you build a harness and run 100 edits through it.

## In action

<div class="cw-session" data-cw-session="session"></div>

## Install

```bash
claude plugin marketplace add chris-peterson/claude-marketplace
claude plugin install cleat@chris-peterson
```

## The shape it holds

`AGENTS.md` carries the body of the guidance. `CLAUDE.md` is the `@AGENTS.md`
ref:

```markdown
@AGENTS.md
```

That's the shape [Claude Code's docs](https://code.claude.com/docs/en/memory#share-one-file-with-other-coding-tools)
give for sharing one file with other coding tools. Genuinely Claude-specific
guidance (slash commands, hooks, `settings.json`) goes below the ref. That's why
this is an import and not a symlink: a symlink surprises whoever opens the file
next, and `CLAUDE.md` has a use beyond pointing.

## What it does

Three hooks, no commands:

| When | What happens |
|---|---|
| You write a substantive `CLAUDE.md` into a repo with no `AGENTS.md` | The write is stopped, with the reason and the instruction to split it in two. The content isn't lost: the model still holds it, so it re-issues rather than regenerates. |
| A write leaves `AGENTS.md`/`CLAUDE.md` in a near-miss shape | The finding and its repair come back in the same turn: add the missing ref, write the `AGENTS.md` a pointer imports, flip an inversion, drop content duplicated from `AGENTS.md`. |
| An agent reads an `AGENTS.md` that `CLAUDE.md` doesn't import, a nested `AGENTS.md` with no pointer beside it, the `README.md` of a repo with no agent guidance, or a rival tool's config | You get one offer to fix it. Once per session per directory. |

### When `CLAUDE.md` really is all Claude-specific

Re-issue the same write. cleat remembers the denied content for the session and
lets an identical retry through, then forgets it. One speed bump, not a wall,
and no configuration to maintain.

## Fixing a repo that already drifted

There's no migration command. Ask Claude to split `CLAUDE.md`, and the writes it
makes are gated and checked like any others:

```text
Split this repo's CLAUDE.md: tool-agnostic guidance into AGENTS.md,
Claude-specific bits below the pointer.
```

To see where a repo stands first:

```bash
scripts/cleat check .
```

Findings come in two severities. **Errors** (a missing `AGENTS.md`, a pointer
to an `AGENTS.md` that doesn't exist, a missing ref, an inversion, a nested
`AGENTS.md` that Claude Code skips for want of a pointer beside it, content
duplicated across both files, a rival tool's config sitting alongside, a topic
rule glob cleat can't evaluate) exit non-zero, so CI can gate on them.
**Advisories** (a repo with no agent guidance at all, an `AGENTS.md` with no
`CLAUDE.md` pointer, or a heading like `## Commands` legitimately present in
both files) are reported and leave the check green.

## Why "cleat"

The fitting on a dock that a line is made fast to. Every tool's line ties to the
same fixed point.
