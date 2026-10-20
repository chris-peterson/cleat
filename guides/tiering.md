# Tiering what a session loads

cleat names this guide when `launch-cost` reports that a session loads more at
launch than the budget allows, and the `context-tiering` skill reads it before
its first edit. It covers where each piece of guidance can load, the order to
move things in, and the mistakes that make a pass report a cut it didn't make.

## Guidance is a tree

The launch files are the root. Every other piece of guidance is a node one or
more triggers away: a rule opens when a matching file is touched, a nested
`AGENTS.md` when the agent works in that directory, a skill's body when it's
invoked, and a guide when a node that already loaded points to it and the agent
needs the detail. Write each node to hold what's needed to act at that depth,
and a pointer to the next node for whoever needs more. Push everything else
down a level. `cleat cost` measures the root.

## The tiers

The ways a branch can open, cheapest first:

| Tier | How | Paid at launch | Reaches the agent when | Other tools |
| --- | --- | --- | --- | --- |
| Hook | a `PreToolUse` or `PostToolUse` script | nothing | the tool event fires | each tool has its own |
| Retired rule | every `paths:` glob matches nothing, file kept | nothing | never | none |
| Typed-only skill | `disable-model-invocation: true` | nothing | the user types `/name` | none |
| Path-scoped rule | `.claude/rules/` file with `paths:` | nothing | a matching file is read, written, or edited | via the `AGENTS.md` index row |
| Directory | a nested `AGENTS.md` and a `CLAUDE.md` pointer beside it | nothing | a file in that directory is read, written, or edited | every tool that reads nested files |
| Skill | `SKILL.md`, model-invocable | the listing entry: name and description | the model or the user invokes it | none |
| Always-on | `AGENTS.md`, `CLAUDE.md`, their `@` imports, a rule without `paths:` | every byte | every session | `AGENTS.md` only |

An `@` import organizes a long file but costs the same: imported files load at
launch with the file that imports them. A block-level HTML comment in an
instruction file is stripped before it loads, so a maintainer note there is
free.

A skill with `paths:` stays out of the listing until a matching file is touched.

## The four moves

Do them in this order. Each one can remove work for the next, so tiering first
means tiering things that shouldn't exist.

### 1. Delete what the harness already says

Read each always-on piece against the system prompt the agent already has. Look
for three things:

- guidance telling the agent the opposite of the harness, which spends context
  fighting it
- guidance the harness or an installed plugin already gives
- a cluster of files that all cite each other, which is one topic split up

This runs both ways. A quarantined or retired rule that keeps getting corrected
by hand is a slot given up wrongly: bring it back.

### 2. Merge before tiering

Files governing the same thing are one file with a formatting problem. Tiering
each separately keeps the duplication at a discount. When you merge, keep each
old file at its path as a retired rule so links to it resolve, and repoint
every link to it in the same pass. Search for the old file's name to find them:
a link from guidance that loads to a rule that doesn't sends the agent to text
it can't reach.

### 3. Scope by path or directory

A rule bound to a file type becomes a path-scoped rule. Guidance bound to one
directory goes in that directory's `AGENTS.md` with a pointer beside it, which
reaches every tool rather than only Claude Code. Derive a glob from the paths
the rule talks about and check it matches a real file; a glob guessed from the
topic is a claim nobody tested. `cleat check` reports a path-scoped rule with
no `AGENTS.md` row (`unlisted-rule`), and `cleat index` prints the row.

Guidance triggered by a situation rather than a file (a review comment, a red
test, a short confirmation from the user) has no file to hang a glob on. It
stays always-on or moves to step 4.

### 4. Push detail down a level, then trim what's left

Split the piece into a stub that stays where it is and a guide one level down,
which loads when the stub sends the agent there. A stub is:

- the constraint, stated once
- when it applies
- one pointer to the guide

Worked examples, exceptions, the incident behind it, and edge cases go in the
guide. **Trimming the stub is the step that gets skipped.** In one pass, eight
split rules ended with stubs larger on average than the rules left whole: the
detail had been copied to the guides and never cut from the stubs, so the
split raised the launch cost. Re-measure after trimming, not after splitting.

Below about 1.4 KB (roughly 350 tokens), trim in place instead of splitting.
Reading the guide costs a file read and the agent's attention, and under that
size the split costs more than it saves.

## Hiding something another file calls

`disable-model-invocation: true` takes a skill out of the listing and also
stops the model from invoking it, even when a skill the user typed is the
caller. A skill another skill, command, or agent invokes may be path-scoped,
but never typed-only. Nothing reports the breakage when you make the edit; it
surfaces the next time the caller runs. Before you hide anything, search every
skill, command, and agent body for its name.

When a skill and a command share a name, the skill is the one that runs, and
`cleat cost` counts only the skill.

## Checking a loader claim

What loads when changes between Claude Code versions, and much of it is
undocumented. Before relying on a mechanism this guide doesn't state, check it
against the installed binary:

1. Make a throwaway project with one skill, command, or rule.
2. Put a marker that appears nowhere else (`ZQALPHA`) in the part you're
   testing: the description, or the body.
3. Run one headless turn from that project:

   ```bash
   claude -p 'Do not use any tools. Quote verbatim every line in your context containing ZQ.'
   ```

4. A quoted marker reached the context; a missing one didn't.

Change one thing between runs. Record the `claude --version` with the result.

## Measuring

`cleat cost` lists what a session in a directory loads, by tier, with each
size in bytes and the total against the budget (16 KiB unless
`git config cleat.launchBudget` sets another). It exits 1 past the budget, so
it can gate CI. It counts the repo's files only. `/context` shows a live
session's whole context, user scope and plugins included, and `/skill-doctor`
lists each skill's listing cost next to how often it gets used.

Report a pass as two measured numbers, before and after. A cut you didn't
measure is a guess.
