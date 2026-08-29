# shipyard runs from its git ref, with no checkout and no install. CI is the
# writer for what lands; these recipes are for seeing the projection first.
shipyard := "uvx --from 'git+https://github.com/chris-peterson/shipyard@v2' shipyard"

default:
    @just --list

# run the shell script test suite
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in scripts/tests/*.test.sh; do echo "== $t =="; bash "$t"; done

# project source into the generated artifacts (plugin.json, hooks.json, describe, docs)
generate:
    {{shipyard}} generate

# read what the projection job would commit, without keeping it; `git restore .` discards
check:
    {{shipyard}} generate
    git --no-pager diff --stat

# preview the docsify docs site locally
docs:
    {{shipyard}} build-docs
    docsify serve docs --open

# regenerate .claude-plugin/plugin.json from plugin.yml (the canonical descriptor)
plugin-json:
    {{shipyard}} gen-plugin-json

# resync plugin.yml suite.describe from the hooks sources
describe:
    {{shipyard}} gen-describe

# report cleat's findings for this repo — it should hold the shape it enforces
self-check:
    scripts/cleat check .
