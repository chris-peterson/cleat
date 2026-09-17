# cleat — Implementation Status

Tracks coverage of the requirements in [SPEC.md](./SPEC.md) against the single
in-repo implementation. Status vocabulary: **Covered** · **Partial** ·
**Missing** · **Contradicts**.

**Evidence pointers:** file + enclosing symbol. A line number is invalidated by
any edit above it, and the ledger is read long after that edit.

**Coverage: 68/68 requirements Covered (100%)**

## CHK — The check command

| ID     | Status  | Location |
|--------|---------|----------|
| CHK-01 | Covered | scripts/cleat (`main`, `cmd_check`) |
| CHK-02 | Covered | scripts/cleat (`has_errors`, `cmd_check`) |
| CHK-03 | Covered | scripts/cleat (`cmd_check`) — the `--json` branch |
| CHK-04 | Covered | scripts/cleat (`findings_for`) — the `no-agents` constructor |
| CHK-05 | Covered | scripts/cleat (`findings_for`) — the `no-claude` constructor |
| CHK-06 | Covered | scripts/cleat (`findings_for`) — the `no-ref` constructor |
| CHK-07 | Covered | scripts/cleat (`findings_for`, `_is_backpointer`) |
| CHK-08 | Covered | scripts/cleat (`_duplication_findings`) |
| CHK-09 | Covered | scripts/cleat (`findings_for`) — the `unguided` constructor |
| CHK-10 | Covered | scripts/cleat (`_foreign_findings`) |
| CHK-11 | Covered | scripts/cleat (`_duplication_findings`, `_classify`) |
| CHK-12 | Covered | scripts/cleat (`findings_for`) — reached only via `findings_for`, which no write hook calls with both files absent |
| CHK-13 | Covered | scripts/cleat (`Finding`, `render`) |
| CHK-14 | Covered | scripts/cleat (`Finding`); the finding constructors in `findings_for` and `_rules_findings` |

## RULE — Topic rules and the index

| ID      | Status  | Location |
|---------|---------|----------|
| RULE-01 | Covered | scripts/cleat (`_topic_rules`) — `rglob("*.md")` |
| RULE-02 | Covered | scripts/cleat (`_rule_globs`, `_matches_any_file`) |
| RULE-03 | Covered | scripts/cleat (`_rules_findings`) — the `unlisted-rule` constructor |
| RULE-04 | Covered | scripts/cleat (`_rules_findings`) — the `dead-rule-listed` constructor |
| RULE-05 | Covered | scripts/cleat (`_rules_findings`) — the two `toc-bloat` constructors |
| RULE-06 | Covered | scripts/cleat (`_index_lines`, `_names_rule`) |
| RULE-07 | Covered | scripts/cleat (`_rules_findings`) — `_under_user_claude(root / RULES_DIR)` |
| RULE-08 | Covered | scripts/cleat (`_topic_rules`, `_rules_findings`) |
| RULE-09 | Covered | scripts/cleat (`findings_for`) — guarded by `has_agents` |

## IDX — The index projector

| ID     | Status  | Location |
|--------|---------|----------|
| IDX-01 | Covered | scripts/cleat (`cmd_index`, `main`) |
| IDX-02 | Covered | scripts/cleat (`_render_index`) |
| IDX-03 | Covered | scripts/cleat (`cmd_index`) — prints only; scripts/tests/rules.test.sh |
| IDX-04 | Covered | scripts/tests/rules.test.sh — the round-trip case |
| IDX-05 | Covered | scripts/cleat — the import block, stdlib only |
| IDX-06 | Covered | scripts/cleat (`_nudge`) |

## HOOK — Hook dispatch

| ID      | Status  | Location |
|---------|---------|----------|
| HOOK-01 | Covered | scripts/cleat (`cmd_hook`) |
| HOOK-02 | Covered | scripts/cleat (`cmd_hook`) — every path returns 0 |
| HOOK-03 | Covered | scripts/cleat (`_emit`) |
| HOOK-04 | Covered | scripts/cleat (`_written_content`) |
| HOOK-05 | Covered | scripts/cleat (`_written_content`) |
| HOOK-06 | Covered | hooks/hooks.yml |

## GATE — The write gate

| ID      | Status  | Location |
|---------|---------|----------|
| GATE-01 | Covered | scripts/cleat (`pre_tool_use`) |
| GATE-02 | Covered | scripts/cleat (`pre_tool_use`, `_under_user_claude`) |
| GATE-03 | Covered | scripts/cleat (`pre_tool_use`) — the basename scope excludes it |
| GATE-04 | Covered | scripts/cleat (`pre_tool_use`) |
| GATE-05 | Covered | scripts/cleat (`pre_tool_use`) |
| GATE-06 | Covered | scripts/cleat (`DENY_REASON`, `_deny_reason`) |
| GATE-07 | Covered | scripts/cleat (`pre_tool_use`, `_key`) |
| GATE-08 | Covered | scripts/cleat (`pre_tool_use`, `_claim`) |
| GATE-09 | Covered | scripts/cleat (`_session_dir`) |

## NUDG — The repair nudge

| ID      | Status  | Location |
|---------|---------|----------|
| NUDG-01 | Covered | scripts/cleat (`_nudge`, `post_tool_use`) |
| NUDG-02 | Covered | scripts/cleat (`_nudge`) |
| NUDG-03 | Covered | scripts/cleat (`_duplication_findings`, `_nudge`) |
| NUDG-04 | Covered | scripts/cleat (`_nudge`) |
| NUDG-05 | Covered | scripts/cleat (`post_tool_use`, `_rules_owner`) |

## BOOT — Bootstrap guidance

| ID      | Status  | Location |
|---------|---------|----------|
| BOOT-01 | Covered | scripts/cleat (`_bootstrap`) |
| BOOT-02 | Covered | scripts/cleat (`_bootstrap`, `_repo_root`) |
| BOOT-03 | Covered | scripts/cleat (`_bootstrap`, `_foreign_relative`) |
| BOOT-04 | Covered | scripts/cleat (`_bootstrap`) |
| BOOT-05 | Covered | scripts/cleat (`_bootstrap`) |

## PRE — Prefilter and cost

| ID     | Status  | Location |
|--------|---------|----------|
| PRE-01 | Covered | hooks/hooks.yml; hooks/prefilter.sh |
| PRE-02 | Covered | hooks/prefilter.sh |
| PRE-03 | Covered | hooks/prefilter.sh |
| PRE-04 | Covered | hooks/prefilter.sh; scripts/tests/prefilter.test.sh |

## PKG — Packaging and layout

| ID     | Status  | Location |
|--------|---------|----------|
| PKG-01 | Covered | plugin.yml; hooks/hooks.yml; justfile; .gitignore |
| PKG-02 | Covered | plugin.yml (`suite`) |
| PKG-03 | Covered | plugin.yml — no `cmds:`; no `skills/` or `commands/` directory |
| PKG-04 | Covered | scripts/cleat — the import block, stdlib only |
| PKG-05 | Covered | guides/agents-vs-claude.md; scripts/cleat (`RUBRIC`) |
| PKG-06 | Covered | AGENTS.md; CLAUDE.md; `just self-check` |
| PKG-07 | Covered | scripts/tests/check.test.sh — the grading-table fixtures |

## ST — Session state

| ID    | Status  | Location |
|-------|---------|----------|
| ST-01 | Covered | scripts/cleat (`_state_root`) |
| ST-02 | Covered | scripts/cleat (`_session_dir`) |
| ST-03 | Covered | scripts/cleat (`_prune_sessions`) |
