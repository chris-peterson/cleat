---
paths:
  - "scripts/cleat"
  - "scripts/cleat_graph.*"
  - "scripts/tests/graph.test.sh"
  - "scripts/tests/deep.test.sh"
---

# Every view has the same features

The terminal browser, the `--html` page, and `--json` are views of one model
(`DESIGN-02` in SPEC.md). A feature lands in all of them in the same change: a
rollup in the terminal is a panel on the page and a field in the JSON, and a
control on the page is a key in the terminal. A test pins each view's half.
