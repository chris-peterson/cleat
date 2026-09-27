# cleat — Implementation Status

Tracks coverage of the requirements in [SPEC.md](./SPEC.md) against the single
in-repo implementation. Status vocabulary: **Covered** · **Partial** ·
**Missing** · **Contradicts**.

**Evidence pointers:** file + enclosing symbol. A line number is invalidated by
any edit above it, and the ledger is read long after that edit.

**Coverage: 73/73 requirements Covered (100%)**

## CHECK — The check command

CHECK-12 is retired and not counted.

| ID     | Status  | Location |
|--------|---------|----------|
| CHECK-01 | Covered | scripts/cleat (`main`, `cmd_check`) |
| CHECK-02 | Covered | scripts/cleat (`has_errors`, `cmd_check`) |
| CHECK-03 | Covered | scripts/cleat (`cmd_check`) — the `--json` branch |
| CHECK-04 | Covered | scripts/cleat (`findings_for`) — the `no-agents` constructor, after `_pointer_only` rules out a bare pointer |
| CHECK-05 | Covered | scripts/cleat (`findings_for`) — the `no-claude` constructor |
| CHECK-06 | Covered | scripts/cleat (`findings_for`) — the `no-ref` constructor, guarded by `inverted` |
| CHECK-07 | Covered | scripts/cleat (`findings_for`, `_is_backpointer`) |
| CHECK-08 | Covered | scripts/cleat (`_duplication_findings`) |
| CHECK-09 | Covered | scripts/cleat (`findings_for`) — the `unguided` constructor |
| CHECK-10 | Covered | scripts/cleat (`_foreign_findings`) |
| CHECK-11 | Covered | scripts/cleat (`_duplication_findings`, `_classify`) |
| CHECK-13 | Covered | scripts/cleat (`Finding`, `render`) |
| CHECK-14 | Covered | scripts/cleat (`Finding`); the finding constructors in `findings_for` and `_rules_findings` |
| CHECK-15 | Covered | scripts/cleat (`findings_for`, `_pointer_only`) — the `dangling-ref` constructor |
| CHECK-16 | Covered | scripts/cleat (`cmd_check`, `cmd_index`) |

## RULE — Topic rules and the index

| ID      | Status  | Location |
|---------|---------|----------|
| RULE-01 | Covered | scripts/cleat (`_topic_rules`) — `rglob("*.md")` |
| RULE-02 | Covered | scripts/cleat (`_topic_rules`, `_rule_globs`, `_matches_any_file`) |
| RULE-03 | Covered | scripts/cleat (`_rules_findings`) — the `unlisted-rule` constructor |
| RULE-04 | Covered | scripts/cleat (`_rules_findings`) — the `dead-rule-listed` constructor |
| RULE-05 | Covered | scripts/cleat (`_rules_findings`, `_rendered_index`) — the two `toc-bloat` constructors |
| RULE-06 | Covered | scripts/cleat (`_index_lines`, `_names_rule`) |
| RULE-07 | Covered | scripts/cleat (`_rules_findings`) — `_under_user_claude(root / RULES_DIR)` |
| RULE-08 | Covered | scripts/cleat (`_topic_rules`, `_rules_findings`) |
| RULE-09 | Covered | scripts/cleat (`findings_for`) — guarded by `has_agents` |
| RULE-10 | Covered | scripts/cleat (`_matches_any_file`) — `os.walk` without `followlinks`; scripts/tests/rules.test.sh |
| RULE-11 | Covered | scripts/cleat (`_expanded`, `_expand_braces`, `_rules_findings`) — the `bad-glob` constructor |

## INDEX — The index projector

| ID     | Status  | Location |
|--------|---------|----------|
| INDEX-01 | Covered | scripts/cleat (`cmd_index`, `main`) |
| INDEX-02 | Covered | scripts/cleat (`_render_index`) |
| INDEX-03 | Covered | scripts/cleat (`cmd_index`) — prints only; scripts/tests/rules.test.sh |
| INDEX-04 | Covered | scripts/tests/rules.test.sh — the round-trip and over-budget cases |
| INDEX-05 | Covered | scripts/cleat — the import block, stdlib only |
| INDEX-06 | Covered | scripts/cleat (`_nudge`, `INDEX_CODES`) |

## HOOK — Hook dispatch

| ID      | Status  | Location |
|---------|---------|----------|
| HOOK-01 | Covered | scripts/cleat (`cmd_hook`) |
| HOOK-02 | Covered | scripts/cleat (`cmd_hook`) — every path returns 0 |
| HOOK-03 | Covered | scripts/cleat (`_emit`) |
| HOOK-04 | Covered | scripts/cleat (`_written_content`) |
| HOOK-05 | Covered | scripts/cleat (`_written_content`) |
| HOOK-06 | Covered | hooks/hooks.yml |
| HOOK-07 | Covered | scripts/cleat (`cmd_hook`) — the unparseable-payload and exception branches |
| HOOK-08 | Covered | scripts/cleat (`post_tool_use`, `_bootstrap`) — `_under_user_claude` |

## GATE — The write gate

| ID      | Status  | Location |
|---------|---------|----------|
| GATE-01 | Covered | scripts/cleat (`pre_tool_use`) |
| GATE-02 | Covered | scripts/cleat (`pre_tool_use`, `_under_user_claude`) |
| GATE-03 | Covered | scripts/cleat (`pre_tool_use`) — the basename scope excludes it |
| GATE-04 | Covered | scripts/cleat (`pre_tool_use`) — `_substantive` on the sibling |
| GATE-05 | Covered | scripts/cleat (`pre_tool_use`) |
| GATE-06 | Covered | scripts/cleat (`DENY_REASON`, `_deny_reason`) |
| GATE-07 | Covered | scripts/cleat (`pre_tool_use`, `_key`) |
| GATE-08 | Covered | scripts/cleat (`pre_tool_use`, `_claim`) |
| GATE-09 | Covered | scripts/cleat (`_session_dir`) |

## NUDGE — The repair nudge

| ID      | Status  | Location |
|---------|---------|----------|
| NUDGE-01 | Covered | scripts/cleat (`_nudge`, `post_tool_use`) |
| NUDGE-02 | Covered | scripts/cleat (`_nudge`) |
| NUDGE-03 | Covered | scripts/cleat (`_duplication_findings`, `_nudge`) |
| NUDGE-04 | Covered | scripts/cleat (`_nudge`) |
| NUDGE-05 | Covered | scripts/cleat (`post_tool_use`, `_rules_owner`) |

## BOOT — Bootstrap guidance

| ID      | Status  | Location |
|---------|---------|----------|
| BOOT-01 | Covered | scripts/cleat (`_bootstrap`) |
| BOOT-02 | Covered | scripts/cleat (`_bootstrap`, `_repo_root`) |
| BOOT-03 | Covered | scripts/cleat (`_bootstrap`, `_foreign_relative`) |
| BOOT-04 | Covered | scripts/cleat (`_bootstrap`) |
| BOOT-05 | Covered | scripts/cleat (`_bootstrap`) |

## PREFILTER — Prefilter and cost

| ID     | Status  | Location |
|--------|---------|----------|
| PREFILTER-01 | Covered | hooks/hooks.yml; hooks/prefilter.sh |
| PREFILTER-02 | Covered | hooks/prefilter.sh |
| PREFILTER-03 | Covered | hooks/prefilter.sh |
| PREFILTER-04 | Covered | hooks/prefilter.sh; scripts/tests/prefilter.test.sh |

## PACKAGING — Packaging and layout

| ID     | Status  | Location |
|--------|---------|----------|
| PACKAGING-01 | Covered | plugin.yml; hooks/hooks.yml; justfile; .gitignore |
| PACKAGING-02 | Covered | plugin.yml (`suite`) |
| PACKAGING-03 | Covered | plugin.yml — no `cmds:`; no `skills/` or `commands/` directory |
| PACKAGING-04 | Covered | scripts/cleat — the import block, stdlib only |
| PACKAGING-05 | Covered | guides/agents-vs-claude.md; scripts/cleat (`RUBRIC`, `_deny_reason`, `_bootstrap`) |
| PACKAGING-06 | Covered | AGENTS.md; CLAUDE.md; `just self-check` |
| PACKAGING-07 | Covered | scripts/tests/check.test.sh — the grading-table fixtures |

## STATE — Session state

| ID    | Status  | Location |
|-------|---------|----------|
| STATE-01 | Covered | scripts/cleat (`_state_root`) |
| STATE-02 | Covered | scripts/cleat (`_session_dir`) |
| STATE-03 | Covered | scripts/cleat (`_prune_sessions`) |

## Audit history

### 2026-09-25 — Coverage refresh (spec-status)

STATUS.md updated: +6 IDs (CHECK-15, CHECK-16, RULE-10, RULE-11, HOOK-07, HOOK-08), CHECK-12 retired; 73/73 Covered. The spec-sync pass that found CHECK-04 and CHECK-12 contradicting the code, and INDEX-04 and INDEX-06 partial, was resolved in the same change.
