# cleat — Implementation Status

Tracks coverage of the requirements in [SPEC.md](./SPEC.md) against the single
in-repo implementation. Status vocabulary: **Covered** · **Partial** ·
**Missing** · **Contradicts**.

**Evidence pointers:** file + enclosing symbol. A line number is invalidated by
any edit above it, and the ledger is read long after that edit.

**Coverage: 141/141 requirements Covered (100%)**

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
| CHECK-13 | Covered | scripts/cleat (`Finding`, `render`); the `restated` and `narrowing-ref` repairs in `_restated_findings`, `_narrowing_findings` |
| CHECK-14 | Covered | scripts/cleat (`Finding`); the finding constructors in `findings_for`, `_rules_findings`, `_restated_findings`, `_narrowing_findings`, `_launch_findings` |
| CHECK-15 | Covered | scripts/cleat (`findings_for`, `_pointer_only`) — the `dangling-ref` constructor |
| CHECK-16 | Covered | scripts/cleat (`cmd_check`, `cmd_index`, `cmd_cost`) |
| CHECK-17 | Covered | scripts/cleat (`_restated_findings`, `_content_lines`, `_runs`, `_markdown_files`, `_generated`); scripts/tests/check.test.sh, scripts/tests/nudge.test.sh |
| CHECK-18 | Covered | scripts/cleat (`_narrowing_findings`, `_link_targets`, `_resolve_link`, `_tier`); scripts/tests/check.test.sh |
| CHECK-19 | Covered | scripts/cleat (`findings_for`, `_shadowing`, `_shadowed_finding`); scripts/tests/check.test.sh |
| CHECK-20 | Covered | scripts/cleat (`_nested_findings`); scripts/tests/check.test.sh |

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
| RULE-12 | Covered | scripts/cleat (`_rules_owner`, `_topic_rules`); scripts/tests/rules.test.sh |

## INDEX — The index projector

| ID     | Status  | Location |
|--------|---------|----------|
| INDEX-01 | Covered | scripts/cleat (`cmd_index`, `main`) |
| INDEX-02 | Covered | scripts/cleat (`_render_index`) |
| INDEX-03 | Covered | scripts/cleat (`cmd_index`) — prints only; scripts/tests/rules.test.sh |
| INDEX-04 | Covered | scripts/tests/rules.test.sh — the round-trip and over-budget cases |
| INDEX-05 | Covered | scripts/cleat — the import block, stdlib only |
| INDEX-06 | Covered | scripts/cleat (`_nudge`, `INDEX_CODES`) |

## COST — What a session loads at launch

| ID      | Status  | Location |
|---------|---------|----------|
| COST-01 | Covered | scripts/cleat (`cmd_cost`, `launch_items`, `render_cost`, `main`); scripts/tests/cost.test.sh |
| COST-02 | Covered | scripts/cleat (`_instruction_items`, `_rule_items`) — `IMPORT_MAX_HOPS`; scripts/tests/cost.test.sh |
| COST-03 | Covered | scripts/cleat (`_imports`, `IMPORT`); scripts/tests/cost.test.sh |
| COST-04 | Covered | scripts/cleat (`_as_loaded`, `_frontmatter`, `_rule_items`); scripts/tests/cost.test.sh |
| COST-05 | Covered | scripts/cleat (`_listing_items`, `_listing_entry`) — `LISTING_MAX_DESC_CHARS`; scripts/tests/cost.test.sh |
| COST-06 | Covered | scripts/cleat (`_listing_items`, `_rule_items`, `launch_total`); scripts/tests/cost.test.sh |
| COST-07 | Covered | scripts/cleat (`launch_budget`, `cmd_cost`) — `LAUNCH_MAX_BYTES`; scripts/tests/cost.test.sh |
| COST-08 | Covered | scripts/cleat (`cmd_cost`); scripts/tests/cost.test.sh |
| COST-09 | Covered | scripts/cleat (`cmd_cost`) — the `--json` branch |
| COST-10 | Covered | scripts/cleat (`_launch_findings`, `TIERING_GUIDE`); scripts/tests/cost.test.sh |

## GRAPH — The context graph

| ID       | Status  | Location |
|----------|---------|----------|
| GRAPH-01 | Covered | scripts/cleat (`cmd_graph`, `main`); scripts/cleat_graph.py (`run`); scripts/tests/graph.test.sh |
| GRAPH-02 | Covered | scripts/cleat_graph.py (`Walker.walk`, `enabled_plugins`, `settings_files`, `config_dir`); scripts/tests/graph.test.sh |
| GRAPH-03 | Covered | scripts/cleat_graph.py (`Walker.file_node`, `Walker.invocable`, `Scope.attrs`); scripts/tests/graph.test.sh |
| GRAPH-04 | Covered | scripts/cleat_graph.py (`Walker.scan`, `Walker.resolve`, `Walker.hooks`) — `PATH_REF`, `SLASH_NAME`, `QUALIFIED_NAME`; scripts/tests/graph.test.sh |
| GRAPH-05 | Covered | scripts/cleat_graph.py (`Walker.instructions`); scripts/tests/graph.test.sh |
| GRAPH-06 | Covered | scripts/cleat_graph.py (`compute_costs`); scripts/tests/graph.test.sh |
| GRAPH-07 | Covered | scripts/cleat_graph.py (`compute_costs`, `totals`); scripts/tests/graph.test.sh |
| GRAPH-08 | Covered | scripts/cleat_graph.py (`filtered`, `matches`, `parse_filter`); scripts/cleat (`main`); scripts/tests/graph.test.sh |
| GRAPH-09 | Covered | scripts/cleat_graph.py (`Browser`, `rollup`, `group_stats`, `left_rows`, `tree_rows`, `heat_level`); scripts/tests/graph.test.sh, under a pty |
| GRAPH-10 | Covered | scripts/cleat_graph.py (`render_html`, `write_page`); scripts/cleat_graph.html; scripts/tests/graph.test.sh |
| GRAPH-11 | Covered | scripts/cleat_graph.py (`as_json`, `run`); scripts/tests/graph.test.sh |
| GRAPH-12 | Covered | scripts/cleat_graph.py (`run`); scripts/tests/graph.test.sh |
| GRAPH-13 | Covered | scripts/cleat_graph.py (`_json_file`, `enabled_plugins`, `run`); scripts/tests/graph.test.sh |
| GRAPH-14 | Covered | scripts/cleat_graph.py (`BYTES_PER_TOKEN`, `tokens`, `write_page`); scripts/cleat_graph.html (`tok`); scripts/tests/graph.test.sh |
| GRAPH-15 | Covered | scripts/cleat_graph.py (`insights`, `_insight`, `Browser.refresh_rows`); scripts/cleat_graph.html (the Insights card, `focusSet`); scripts/tests/graph.test.sh |
| GRAPH-16 | Covered | scripts/cleat_graph.py (`Walker.ref`, `Walker.retired`, the `when` and `trigger` fields, `Graph.refs`, `Browser.details`, `tag`); scripts/cleat_graph.html (Loads, Opened by); scripts/tests/graph.test.sh |
| GRAPH-17 | Covered | scripts/cleat_graph.html (`drawUniverse`, `lightTo`, `setMode`, `chooseOwner`, `ownerPanel`, `drill`, `expand`, `tourSteps`) |
| GRAPH-18 | Covered | scripts/cleat_graph.py (`depth_cost`, `totals`, `owners`, `group_stats`, `Browser.draw`, `write_page`); scripts/cleat_graph.html (`totals`, `ownerPanel`); scripts/tests/graph.test.sh |
| GRAPH-19 | Covered | scripts/cleat_graph.py (`vs_ideal`, `checks`, `_reads_below`, `has_toc`, `Walker.file_node` — the `lines` and `toc` fields, `build` — `launch_budget`); scripts/tests/ideal.test.sh |
| GRAPH-20 | Covered | scripts/cleat_graph.py (`vs_ideal` — `improve`, the ranking sort); scripts/tests/ideal.test.sh |
| GRAPH-21 | Covered | scripts/cleat_graph.py (`vs_ideal` — `counted`, the owner cards); scripts/tests/ideal.test.sh |
| GRAPH-22 | Covered | scripts/cleat_graph.py (`as_json`, `Browser` — the `IDEAL` group, `details`); scripts/cleat_graph.html (`drawIdeal`, `setView`, the details panel's vs ideal section); scripts/tests/ideal.test.sh, under a pty |
| GRAPH-23 | Covered | scripts/cleat_graph.py (`osc8`, `Browser.link`, `Browser.emit_links`, `Browser.sgr`, `Browser.selected_path`, the details strip's file line); scripts/cleat_graph.html (`fileLinks`); scripts/tests/graph.test.sh, under a pty |
| GRAPH-24 | Covered | scripts/cleat_graph.py (`MOUSE_ON`, `MOUSE_OFF`, `SGR_MOUSE`, `Browser.run`, `Browser.read_escape`, `Browser.mouse`, `Browser.regroup`); scripts/tests/graph.test.sh, under a pty |
| GRAPH-25 | Covered | scripts/cleat_graph.html (the sky's dblclick handler, `crumb`, `#key`); scripts/tests/graph.test.sh |
| GRAPH-26 | Covered | scripts/cleat_graph.html (`planFor`, `whereText`, `promptText`, `drawPlan`, `ownerLabel`, `ownerPanel`'s What to change); scripts/tests/graph.test.sh |

## METRICS — Context metrics

| ID         | Status  | Location |
|------------|---------|----------|
| METRICS-01 | Covered | scripts/cleat (`cmd_metrics`, `main`); scripts/cleat_graph.py (`run_metrics`); scripts/tests/metrics.test.sh |
| METRICS-02 | Covered | scripts/cleat_graph.py (`history_path`, `run_metrics`, `yaml_lines`, `_scalar`); scripts/tests/metrics.test.sh |
| METRICS-03 | Covered | scripts/cleat_graph.py (`snapshot`); scripts/tests/metrics.test.sh |
| METRICS-04 | Covered | scripts/cleat_graph.py (`snapshot`, `_stats`); scripts/tests/metrics.test.sh |
| METRICS-05 | Covered | scripts/cleat_graph.py (`hop_counts`, `snapshot`); scripts/tests/metrics.test.sh |
| METRICS-06 | Covered | scripts/cleat_graph.py (`depth_curve`, `CURVE_START_TOKENS`, `snapshot`); scripts/tests/metrics.test.sh |
| METRICS-07 | Covered | scripts/cleat_graph.py (`owner_digest`, `snapshot`, `enabled_plugins`, `Graph.plugins`); scripts/tests/metrics.test.sh |
| METRICS-08 | Covered | scripts/cleat_graph.py (`run_metrics`); scripts/tests/metrics.test.sh |

## DESIGN — Design tenets

| ID        | Status  | Location |
|-----------|---------|----------|
| DESIGN-01 | Covered | hooks/hooks.yml; skills/context-tiering/SKILL.md, the one listing entry; guides/ named by path from scripts/cleat (`RUBRIC`, `PLACEMENT_GUIDE`, `TIERING_GUIDE`) |

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
| HOOK-09 | Covered | scripts/cleat (`pre_tool_use`) — the `overridden` bucket; scripts/tests/gate.test.sh |

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
| NUDGE-06 | Covered | scripts/cleat (`post_tool_use`, `_in_doc_set`, `_relative_to`); scripts/tests/nudge.test.sh |
| NUDGE-07 | Covered | scripts/cleat (`_nudge`, `_finding_key`); scripts/tests/nudge.test.sh |
| NUDGE-08 | Covered | scripts/cleat (`_restated_directive`, `_nudge`, `render`, `post_tool_use`); scripts/tests/nudge.test.sh |
| NUDGE-09 | Covered | scripts/cleat (`_nudge`); scripts/tests/nudge.test.sh |

## PLACEMENT — Where new guidance goes

| ID      | Status  | Location |
|---------|---------|----------|
| PLACEMENT-01 | Covered | scripts/cleat (`_placement_reason`, `PLACEMENT_REASON`, `_placement_scope`); scripts/tests/gate.test.sh |
| PLACEMENT-02 | Covered | scripts/cleat (`_placement_reason`, `PLACEMENT_TOPIC`) |
| PLACEMENT-03 | Covered | scripts/cleat (`_existing_copies`, `PLACEMENT_EXISTING`) |
| PLACEMENT-04 | Covered | scripts/cleat (`_placement_reason`) — the `placed` bucket; `pre_tool_use`, `_claim` |
| PLACEMENT-05 | Covered | scripts/cleat (`pre_tool_use`) — one deny joining `_gate_reason` and `_placement_reason` |
| PLACEMENT-06 | Covered | scripts/cleat (`_added_lines`, `pre_tool_use`) — `_under_user_claude`; CLAUDE.local.md falls outside `_placement_scope` |
| PLACEMENT-07 | Covered | scripts/cleat (`_extra_rules_dirs`, `_placement_scope`); hooks/prefilter.sh (`rules/`) |
| PLACEMENT-08 | Covered | scripts/cleat (`PLACEMENT_GUIDE`, `PLACEMENT_REASON`) |

## BOOT — Bootstrap guidance

| ID      | Status  | Location |
|---------|---------|----------|
| BOOT-01 | Covered | scripts/cleat (`_bootstrap`) |
| BOOT-02 | Covered | scripts/cleat (`_bootstrap`, `_repo_root`) |
| BOOT-03 | Covered | scripts/cleat (`_bootstrap`, `_foreign_relative`) |
| BOOT-04 | Covered | scripts/cleat (`_bootstrap`) |
| BOOT-05 | Covered | scripts/cleat (`_bootstrap`) |
| BOOT-06 | Covered | scripts/cleat (`_bootstrap`, `_shadowing`); scripts/tests/bootstrap.test.sh |

## PREFILTER — Prefilter and cost

| ID     | Status  | Location |
|--------|---------|----------|
| PREFILTER-01 | Covered | hooks/hooks.yml; hooks/prefilter.sh |
| PREFILTER-02 | Covered | hooks/prefilter.sh — the `write` needles; hooks/hooks.yml; scripts/tests/prefilter.test.sh |
| PREFILTER-03 | Covered | hooks/prefilter.sh |
| PREFILTER-04 | Covered | hooks/prefilter.sh; scripts/tests/prefilter.test.sh |

## PACKAGING — Packaging and layout

PACKAGING-03 is retired and not counted.

| ID     | Status  | Location |
|--------|---------|----------|
| PACKAGING-01 | Covered | plugin.yml; hooks/hooks.yml; justfile; .gitignore |
| PACKAGING-02 | Covered | plugin.yml (`suite`) |
| PACKAGING-04 | Covered | scripts/cleat — the import block, stdlib only |
| PACKAGING-05 | Covered | guides/agents-vs-claude.md; scripts/cleat (`RUBRIC`, `_deny_reason`, `_bootstrap`) |
| PACKAGING-06 | Covered | AGENTS.md; CLAUDE.md; `just self-check` |
| PACKAGING-07 | Covered | scripts/tests/check.test.sh — the grading-table fixtures |
| PACKAGING-08 | Covered | guides/placement.md; docs/placement.md; docs/agents-vs-claude.md; docs/_sidebar.md |
| PACKAGING-09 | Covered | docs/feedback-loops.md; docs/_sidebar.md |
| PACKAGING-10 | Covered | docs/harness-engineering.md; docs/_sidebar.md |
| PACKAGING-11 | Covered | docs/background.md; docs/_sidebar.md; .gitignore |
| PACKAGING-12 | Covered | guides/tiering.md; docs/tiering.md; docs/_sidebar.md; scripts/cleat (`_launch_findings`); skills/context-tiering/SKILL.md |

## STATE — Session state

| ID    | Status  | Location |
|-------|---------|----------|
| STATE-01 | Covered | scripts/cleat (`_state_root`); scripts/tests/gate.test.sh ("a hook with no data dir") |
| STATE-02 | Covered | scripts/cleat (`_session_dir`) |
| STATE-03 | Covered | scripts/cleat (`_prune_sessions`) |

## Audit history

### 2026-11-06 — Opening files, the mouse, focus, and a plan per owner (spec-req)

+4 IDs (GRAPH-23–26). Files open from where they're shown: OSC 8 links in the terminal browser and links on the page, each to the file and its folder. The terminal browser takes clicks and the wheel. Double-clicking a star narrows the universe to what it pulls in, and a key explains its marks. Selecting an owner in vs ideal gives a plan of what to change there and a starter prompt to hand a coding agent. 141/141 Covered.

### 2026-11-06 — vs ideal (spec-req)

+4 IDs (GRAPH-19–22) and two concepts (ideal, excess). `cleat graph` checks each file against the budget for its tier (Anthropic's published skill budgets, and cleat's launch budget for launch), ranks the improvements by how often a session pays for them, and scores each owner, in a vs ideal view on the page, a group in the terminal browser, and the JSON. 137/137 Covered.

### 2026-11-06 — Context metrics (spec-req)

+8 IDs (METRICS-01–08) and four concepts (depth cost, hop count, depth curve, metrics history). `cleat metrics` appends a YAML snapshot of the context graph's numbers to a history on the machine that took it: totals, per load tier, per hop count, the depth curve with b50 and b90, the largest step, and per-owner totals with plugin versions and content digests. 133/133 Covered.

### 2026-11-05 — The context graph (spec-req)

+18 IDs (GRAPH-01–18) and seven concepts (context graph, load tier, root, reach cost, next cost, closure cost, unmeasured). `cleat graph` walks the repo, user scope, and enabled plugins for the deferred loads `cleat cost` leaves out, and browses them in the terminal, as an HTML page, or as JSON, with costs in estimated tokens insights on what stands out, the condition and reference behind each load, and a universe view of context spent by depth or breadth. 125/125 Covered.

### 2026-10-26 — What to do with a restated finding (spec-req)

+2 IDs (NUDGE-08, NUDGE-09); CHECK-17 amended. Issue #13. 107/107 Covered.

### 2026-10-20 — Launch cost and context tiering (spec-req)

+12 IDs (COST-01–10, DESIGN-01, PACKAGING-12); CHECK-14 and CHECK-16 amended; PACKAGING-03 retired in favor of DESIGN-01. `cleat cost` and the `launch-cost` advisory land with the context-tiering skill and the tiering guide, toward issue #9. 105/105 Covered.

### 2026-10-05 — Background page and reading order (spec-req)

+1 ID (PACKAGING-11). A background page for readers new to coding agents comes before harness engineering, and feedback loops follows the lab; the guides and SPEC sit under Reference. 94/94 Covered.

### 2026-10-04 — Agent guides and their docs pages (spec-req)

PACKAGING-08 and PACKAGING-09 amended. The placement guide holds only what the agent acts on, and the docs site's Placement and Rubric pages include each guide verbatim. The background the guide carried moves to the feedback loops page (how to tell whether each kind works, how cleat applies the model) and the harness engineering page (further reading). 93/93 Covered.

### 2026-10-02 — Harness engineering page and lab (spec-req)

+1 ID (PACKAGING-10); PACKAGING-09 amended. The background moves from the feedback loops page to its own page with an interactive stove scene and a lab, and the feedback loops page links to it. 93/93 Covered.

### 2026-10-01 — Nested instruction files (spec-req)

+5 IDs (CHECK-19, CHECK-20, RULE-12, BOOT-06, PACKAGING-09); CHECK-13, CHECK-14, PLACEMENT-02, and PACKAGING-08 amended. RULE-12 records behavior the nudge already had; the rest landed with the `shadowed` finding and the feedback loops page. 92/92 Covered.

### 2026-09-28 — Placement and reference direction (spec-req)

+14 IDs (CHECK-17, CHECK-18, HOOK-09, NUDGE-06, NUDGE-07, PLACEMENT-01–08, PACKAGING-08); CHECK-13, CHECK-14, and NUDGE-03 amended. PLACEMENT absorbs issue #6. All 87 Covered once the check, nudge, gate, and prefilter changes landed on the same branch.

### 2026-09-25 — Coverage refresh (spec-status)

STATUS.md updated: +6 IDs (CHECK-15, CHECK-16, RULE-10, RULE-11, HOOK-07, HOOK-08), CHECK-12 retired; 73/73 Covered. The spec-sync pass that found CHECK-04 and CHECK-12 contradicting the code, and INDEX-04 and INDEX-06 partial, was resolved in the same change.
