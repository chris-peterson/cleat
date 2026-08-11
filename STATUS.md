# cleat — Implementation Status

Tracks coverage of the requirements in [SPEC.md](./SPEC.md) against the single
in-repo implementation. Status vocabulary: **Covered** · **Partial** ·
**Missing** · **Contradicts**.

**Coverage: 56/56 requirements Covered (100%)**

## CHECK — The check command

| ID       | Status  | Location                                                                                              |
|----------|---------|-------------------------------------------------------------------------------------------------------|
| CHECK-01 | Covered | scripts/cleat:621 (`main`); scripts/cleat:568 (`cmd_check`)                                           |
| CHECK-02 | Covered | scripts/cleat:240 (`has_errors`); scripts/cleat:585                                                   |
| CHECK-03 | Covered | scripts/cleat:578                                                                                     |
| CHECK-04 | Covered | scripts/cleat:198                                                                                     |
| CHECK-05 | Covered | scripts/cleat:206                                                                                     |
| CHECK-06 | Covered | scripts/cleat:227                                                                                     |
| CHECK-07 | Covered | scripts/cleat:216; scripts/cleat:128 (`_is_backpointer`)                                              |
| CHECK-08 | Covered | scripts/cleat:159                                                                                     |
| CHECK-09 | Covered | scripts/cleat:190                                                                                     |
| CHECK-10 | Covered | scripts/cleat:136 (`_foreign_findings`)                                                               |
| CHECK-11 | Covered | scripts/cleat:152 (`_duplication_findings`); scripts/cleat:106 (`_classify`)                          |
| CHECK-12 | Covered | scripts/cleat:190 — reached only via `findings_for`, which no write hook calls with both files absent |
| CHECK-13 | Covered | scripts/cleat:68 (`Finding.repair`); scripts/cleat:244 (`render`)                                     |
| CHECK-14 | Covered | scripts/cleat:68 (`Finding.severity`); the constructors at 144–227                                    |
| CHECK-15 | Covered | scripts/cleat:179 (`_degradation_finding`); scripts/cleat:168 (`_present_config`)                     |
| CHECK-16 | Covered | scripts/cleat:289 — the `has_agents` guard in `findings_for`                                          |
| CHECK-17 | Covered | scripts/cleat:186 — the early return on a `.claude` mention                                           |

## HOOK — Hook dispatch

| ID      | Status  | Location                                 |
|---------|---------|------------------------------------------|
| HOOK-01 | Covered | scripts/cleat:588 (`cmd_hook`)           |
| HOOK-02 | Covered | scripts/cleat:588 — every path returns 0 |
| HOOK-03 | Covered | scripts/cleat:616 (`_emit`)              |
| HOOK-04 | Covered | scripts/cleat:350 (`_written_content`)   |
| HOOK-05 | Covered | scripts/cleat:350 (`_written_content`)   |
| HOOK-06 | Covered | hooks/hooks.yml                          |

## GATE — The write gate

| ID      | Status  | Location                                                              |
|---------|---------|-----------------------------------------------------------------------|
| GATE-01 | Covered | scripts/cleat:418                                                     |
| GATE-02 | Covered | scripts/cleat:420; scripts/cleat:333 (`_under_user_claude`)           |
| GATE-03 | Covered | scripts/cleat:418 — the basename scope excludes it                    |
| GATE-04 | Covered | scripts/cleat:422                                                     |
| GATE-05 | Covered | scripts/cleat:430                                                     |
| GATE-06 | Covered | scripts/cleat:371 (`DENY_REASON`); scripts/cleat:396 (`_deny_reason`) |
| GATE-07 | Covered | scripts/cleat:437; scripts/cleat:272 (`_key`)                         |
| GATE-08 | Covered | scripts/cleat:435; scripts/cleat:300 (`_claim`)                       |
| GATE-09 | Covered | scripts/cleat:290 (`_session_dir`)                                    |

## NUDGE — The repair nudge

| ID       | Status  | Location                                                          |
|----------|---------|-------------------------------------------------------------------|
| NUDGE-01 | Covered | scripts/cleat:447 (`_nudge`); scripts/cleat:548 (`post_tool_use`) |
| NUDGE-02 | Covered | scripts/cleat:460; scripts/cleat:468                              |
| NUDGE-03 | Covered | scripts/cleat:162; scripts/cleat:462                              |
| NUDGE-04 | Covered | scripts/cleat:456                                                 |

## BOOT — Bootstrap guidance

| ID      | Status  | Location                                                   |
|---------|---------|------------------------------------------------------------|
| BOOT-01 | Covered | scripts/cleat:493                                          |
| BOOT-02 | Covered | scripts/cleat:508; scripts/cleat:340 (`_repo_root`)        |
| BOOT-03 | Covered | scripts/cleat:523; scripts/cleat:474 (`_foreign_relative`) |
| BOOT-04 | Covered | scripts/cleat:534                                          |
| BOOT-05 | Covered | scripts/cleat:539; scripts/cleat:542                       |

## PREFILTER — Prefilter and cost

| ID           | Status  | Location                                            |
|--------------|---------|-----------------------------------------------------|
| PREFILTER-01 | Covered | hooks/hooks.yml; hooks/prefilter.sh                 |
| PREFILTER-02 | Covered | hooks/prefilter.sh                                  |
| PREFILTER-03 | Covered | hooks/prefilter.sh                                  |
| PREFILTER-04 | Covered | hooks/prefilter.sh; scripts/tests/prefilter.test.sh |

## PACKAGING — Packaging and layout

| ID           | Status  | Location                                                                                               |
|--------------|---------|--------------------------------------------------------------------------------------------------------|
| PACKAGING-01 | Covered | plugin.yml; hooks/hooks.yml; justfile; .gitignore                                                      |
| PACKAGING-02 | Covered | plugin.yml:20                                                                                          |
| PACKAGING-03 | Covered | plugin.yml — no `cmds:`; no `skills/` or `commands/` directory                                         |
| PACKAGING-04 | Covered | scripts/cleat:17–25 — stdlib imports only                                                              |
| PACKAGING-05 | Covered | guides/agents-vs-claude.md; guides/graceful-degradation.md; scripts/cleat:57 (`RUBRIC`, `DEGRADATION`) |
| PACKAGING-06 | Covered | AGENTS.md; CLAUDE.md; `just self-check`                                                                |
| PACKAGING-07 | Covered | scripts/tests/check.test.sh — the grading-table fixtures                                               |
| PACKAGING-08 | Covered | .github/workflows/test.yml                                                                             |

## STATE — Session state

| ID       | Status  | Location                              |
|----------|---------|---------------------------------------|
| STATE-01 | Covered | scripts/cleat:263 (`_state_root`)     |
| STATE-02 | Covered | scripts/cleat:290 (`_session_dir`)    |
| STATE-03 | Covered | scripts/cleat:280 (`_prune_sessions`) |
