# cleat — Implementation Status

Tracks coverage of the requirements in [SPEC.md](./SPEC.md) against the single
in-repo implementation. Status vocabulary: **Covered** · **Partial** ·
**Missing** · **Contradicts**.

**Coverage: 52/52 requirements Covered (100%)**

## CHK — The check command

| ID     | Status  | Location |
|--------|---------|----------|
| CHK-01 | Covered | scripts/cleat:621 (`main`); scripts/cleat:568 (`cmd_check`) |
| CHK-02 | Covered | scripts/cleat:240 (`has_errors`); scripts/cleat:585 |
| CHK-03 | Covered | scripts/cleat:578 |
| CHK-04 | Covered | scripts/cleat:198 |
| CHK-05 | Covered | scripts/cleat:206 |
| CHK-06 | Covered | scripts/cleat:227 |
| CHK-07 | Covered | scripts/cleat:216; scripts/cleat:128 (`_is_backpointer`) |
| CHK-08 | Covered | scripts/cleat:159 |
| CHK-09 | Covered | scripts/cleat:190 |
| CHK-10 | Covered | scripts/cleat:136 (`_foreign_findings`) |
| CHK-11 | Covered | scripts/cleat:152 (`_duplication_findings`); scripts/cleat:106 (`_classify`) |
| CHK-12 | Covered | scripts/cleat:190 — reached only via `findings_for`, which no write hook calls with both files absent |
| CHK-13 | Covered | scripts/cleat:68 (`Finding.repair`); scripts/cleat:244 (`render`) |
| CHK-14 | Covered | scripts/cleat:68 (`Finding.severity`); the constructors at 144–227 |

## HOOK — Hook dispatch

| ID      | Status  | Location |
|---------|---------|----------|
| HOOK-01 | Covered | scripts/cleat:588 (`cmd_hook`) |
| HOOK-02 | Covered | scripts/cleat:588 — every path returns 0 |
| HOOK-03 | Covered | scripts/cleat:616 (`_emit`) |
| HOOK-04 | Covered | scripts/cleat:350 (`_written_content`) |
| HOOK-05 | Covered | scripts/cleat:350 (`_written_content`) |
| HOOK-06 | Covered | hooks/hooks.yml |

## GATE — The write gate

| ID      | Status  | Location |
|---------|---------|----------|
| GATE-01 | Covered | scripts/cleat:418 |
| GATE-02 | Covered | scripts/cleat:420; scripts/cleat:333 (`_under_user_claude`) |
| GATE-03 | Covered | scripts/cleat:418 — the basename scope excludes it |
| GATE-04 | Covered | scripts/cleat:422 |
| GATE-05 | Covered | scripts/cleat:430 |
| GATE-06 | Covered | scripts/cleat:371 (`DENY_REASON`); scripts/cleat:396 (`_deny_reason`) |
| GATE-07 | Covered | scripts/cleat:437; scripts/cleat:272 (`_key`) |
| GATE-08 | Covered | scripts/cleat:435; scripts/cleat:300 (`_claim`) |
| GATE-09 | Covered | scripts/cleat:290 (`_session_dir`) |

## NUDG — The repair nudge

| ID      | Status  | Location |
|---------|---------|----------|
| NUDG-01 | Covered | scripts/cleat:447 (`_nudge`); scripts/cleat:548 (`post_tool_use`) |
| NUDG-02 | Covered | scripts/cleat:460; scripts/cleat:468 |
| NUDG-03 | Covered | scripts/cleat:162; scripts/cleat:462 |
| NUDG-04 | Covered | scripts/cleat:456 |

## BOOT — Bootstrap guidance

| ID      | Status  | Location |
|---------|---------|----------|
| BOOT-01 | Covered | scripts/cleat:493 |
| BOOT-02 | Covered | scripts/cleat:508; scripts/cleat:340 (`_repo_root`) |
| BOOT-03 | Covered | scripts/cleat:523; scripts/cleat:474 (`_foreign_relative`) |
| BOOT-04 | Covered | scripts/cleat:534 |
| BOOT-05 | Covered | scripts/cleat:539; scripts/cleat:542 |

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
| PKG-02 | Covered | plugin.yml:20 |
| PKG-03 | Covered | plugin.yml — no `cmds:`; no `skills/` or `commands/` directory |
| PKG-04 | Covered | scripts/cleat:17–25 — stdlib imports only |
| PKG-05 | Covered | guides/agents-vs-claude.md; scripts/cleat:57 (`RUBRIC`) |
| PKG-06 | Covered | AGENTS.md; CLAUDE.md; `just self-check` |
| PKG-07 | Covered | scripts/tests/check.test.sh — the grading-table fixtures |

## ST — Session state

| ID    | Status  | Location |
|-------|---------|----------|
| ST-01 | Covered | scripts/cleat:263 (`_state_root`) |
| ST-02 | Covered | scripts/cleat:290 (`_session_dir`) |
| ST-03 | Covered | scripts/cleat:280 (`_prune_sessions`) |
