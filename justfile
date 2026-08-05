default:
    @just --list

# run the shell script test suite
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in scripts/tests/*.test.sh; do echo "== $t =="; bash "$t"; done

# regenerate all generated artifacts from source (describe, plugin.json, docs)
generate:
    scripts/shipyard generate

# validate source projects cleanly and preview the pending projection (no write)
check:
    scripts/shipyard generate --dry-run

# preview the docsify docs site locally
docs:
    scripts/shipyard build-docs
    docsify serve docs --open

# regenerate .claude-plugin/plugin.json from plugin.yml (the canonical descriptor)
plugin-json:
    scripts/shipyard gen-plugin-json

# resync plugin.yml suite.describe from the hooks sources
describe:
    scripts/shipyard gen-describe

# report cleat's findings for this repo — it should hold the shape it enforces
self-check:
    scripts/cleat check .
