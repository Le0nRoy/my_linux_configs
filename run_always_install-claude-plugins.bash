#!/bin/bash
# Installs ~/.claude/plugins.json with a curated set of Claude Code plugin
# marketplaces + enabled plugins. Runs on every `chezmoi apply`.
#
# Why a run-script instead of a plain source file: `.chezmoiignore` excludes
# the whole `.claude/` tree (AI-agent runtime state chezmoi shouldn't touch),
# so we can't ship this file via the normal `dot_claude/...` route. A merge
# semantic that preserves any downstream additions to plugins.json is also
# nicer than a blanket overwrite; keep it minimal for now (idempotent create
# when missing; leave alone if operator has edited it).

set -euo pipefail

PLUGINS_FILE="${HOME}/.claude/plugins.json"

mkdir -p "${HOME}/.claude"

if [[ -f "${PLUGINS_FILE}" ]]; then
    # Respect operator edits — don't clobber. To re-seed, delete the file and
    # re-run `chezmoi apply`.
    exit 0
fi

cat > "${PLUGINS_FILE}" <<'JSON'
{
  "extraKnownMarketplaces": {
    "caveman": {
      "source": {
        "source": "github",
        "repo": "JuliusBrussee/caveman"
      }
    },
    "ponytail": {
      "source": {
        "source": "github",
        "repo": "DietrichGebert/ponytail"
      }
    }
  },
  "enabledPlugins": {
    "caveman@caveman": true,
    "ponytail@ponytail": true
  }
}
JSON

echo "Seeded ${PLUGINS_FILE} with default Claude Code plugin marketplaces."
