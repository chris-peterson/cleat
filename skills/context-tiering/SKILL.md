---
name: context-tiering
description: This skill should be used when the user asks to "reduce startup context", "trim CLAUDE.md", "tier these rules", or "why is my context so big". Measures what a repo's agent instructions load at launch and moves each piece to the cheapest tier that still reaches the agent.
argument-hint: "[directory]"
---

# Context tiering

Reduce what a session in this repo loads at launch, then keep it there. The
tiers, the order to move things in, and the traps are in
`${CLAUDE_PLUGIN_ROOT}/guides/tiering.md`. Read it before step 5.

1. **Run the test suite** and report its state before any edit, so a failure
   found at commit time isn't blamed on this pass.

2. **Measure.** Run this on the repo root, or on the directory the user named:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/cleat" cost <directory>
   ```

   It lists every file and listing entry the repo puts in a session at launch,
   each with its tier and size, and the total against the budget. Report that
   total and say what it leaves out: user scope, plugins, and the harness
   prompt. For those, ask the user to run `/context`, which shows a live
   session's whole context. `claude -p '/skill-doctor'` prints each skill's
   listing cost next to how often it's used, across every installed source;
   the unused ones are the cheapest to cut.

3. **Map what calls what.** Search every skill, command, agent, and hook body
   for the names of the others: Skill-tool calls, `/name` references, script
   paths. Anything another file invokes may be path-scoped but must not get
   `disable-model-invocation: true`.

4. **Ask before editing**, in one `AskUserQuestion` carrying the measured
   total: trim in place or split into tiers, which files are in scope, and
   whether to fold in or park anything adjacent you found.

5. **Apply the four moves** from the guide, in its order.

6. **Re-measure** with `cleat cost` and report before and after as two
   numbers. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/cleat" check` too: a newly
   path-scoped rule needs an `AGENTS.md` row (`cleat index` prints it).

7. **Offer a guard.** `cleat cost` exits 1 past the budget, so it can run in
   CI. A repo sets its own budget with `git config cleat.launchBudget <bytes>`.
