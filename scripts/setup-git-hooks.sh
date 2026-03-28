#!/usr/bin/env bash
# Configures git to use the .githooks directory for this repository.
# Run once after cloning: just setup  (or bash scripts/setup-git-hooks.sh)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

git config core.hooksPath .githooks
chmod +x "$REPO_ROOT/.githooks/pre-push"

echo "✅ Git hooks configured. Hooks directory: .githooks"
