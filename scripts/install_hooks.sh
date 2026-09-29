#!/usr/bin/env bash
# Instala os hooks locais do repositório.
set -euo pipefail

cd "$(dirname "$0")/.."
hooks_dir="$(git rev-parse --git-path hooks)"

ln -sf "../../scripts/commit-msg-hook.sh" "$hooks_dir/commit-msg"
chmod +x scripts/commit-msg-hook.sh

printf '\033[32m✓\033[0m hook commit-msg instalado em %s\n' "$hooks_dir"
