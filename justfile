# shipyard runs from its git ref, with no checkout and no install. CI is the
# writer for what lands; these recipes are for seeing the projection first.
shipyard := "uvx --from 'git+https://github.com/chris-peterson/shipyard@v2' shipyard"

# what this is, and every recipe there is
[private]
default:
    @echo ""
    @echo "  cleat: one canonical AGENTS.md, with CLAUDE.md as a pointer to it"
    @echo ""
    @echo "  New here?   just demo     what a session here can load, and where it's heaviest"
    @echo "              just docs     the docs site"
    @echo ""
    @just --list --unsorted --list-heading '' --list-prefix '    '
    @echo ""
    @echo "  Generated files are written by CI on PRs and main; edit the source, not the output."
    @echo ""

# Each demo runs against this repo by default; pass another directory to look there.
# the context graph in the terminal: what a session can load, hotspots colored
[group('start here')]
demo dir=".":
    scripts/cleat graph {{quote(dir)}}

# the context graph as an interactive page in your browser
[group('start here')]
demo-html dir=".":
    scripts/cleat graph {{quote(dir)}} --html

# the graph's JSON through an example tool: heaviest branches, shared hubs, cost by owner
[group('start here')]
demo-json dir="." *filters:
    scripts/cleat graph {{quote(dir)}} --json {{filters}} | python3 examples/graph-hotspots.py

# append a snapshot of the graph's numbers to ~/.local/state/cleat/metrics.yml, and print it
[group('start here')]
metrics dir=".":
    scripts/cleat metrics {{quote(dir)}}

# run the shell script test suite
[group('work on cleat')]
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in scripts/tests/*.test.sh; do echo "== $t =="; bash "$t"; done

# report cleat's findings for this repo — it should hold the shape it enforces
[group('work on cleat')]
self-check:
    scripts/cleat check .

# preview the docsify docs site locally, the lab included
[group('start here')]
docs:
    {{shipyard}} build-docs
    docsify serve docs --open

# project source into the generated artifacts (plugin.json, hooks.json, describe, docs)
[group('generated files')]
generate:
    {{shipyard}} generate

# regenerate the artifacts and list what the projection job would commit
[group('generated files')]
check-generated:
    {{shipyard}} generate
    git --no-pager diff --stat

# regenerate .claude-plugin/plugin.json from plugin.yml (the canonical descriptor)
[group('generated files')]
generate-plugin-json:
    {{shipyard}} gen-plugin-json

# resync plugin.yml suite.describe from the hooks sources
[group('generated files')]
generate-describe:
    {{shipyard}} gen-describe
