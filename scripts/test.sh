#!/usr/bin/env bash
#
# Roda toda a suíte: os 4 módulos Dart e o backend Go com detector de corrida.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

DART_MODULES=(
  "."
  "packages/drawly_core"
  "packages/drawly_design_system"
  "packages/drawing_board"
)

failed=0
step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

for module in "${DART_MODULES[@]}"; do
  step "flutter test — $module"
  (cd "$ROOT/$module" && flutter test --reporter=compact) || failed=1
done

step "go test -race — backend-go"
# -race é obrigatório: foi ele que revelou a corrida no estado global do jogo.
(cd "$ROOT/backend-go" && go test -race ./src/...) || failed=1

printf '\n'
if [ "$failed" -ne 0 ]; then
  printf '\033[31m✗ suíte vermelha\033[0m\n'
  exit 1
fi
printf '\033[32m✓ suíte verde\033[0m\n'
