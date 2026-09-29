#!/usr/bin/env bash
#
# Gate de qualidade estática: formatação, análise e vet.
# Mesmo comando local e no CI — não existe "passa na minha máquina".
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
fail() { printf '\033[31m  ✗ %s\033[0m\n' "$1"; failed=1; }
ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }

for module in "${DART_MODULES[@]}"; do
  step "dart format — $module"
  if (cd "$ROOT/$module" && dart format --output=none --set-exit-if-changed lib test 2>/dev/null); then
    ok "formatado"
  else
    fail "arquivos fora do formato em $module (rode: dart format .)"
  fi

  step "flutter analyze — $module"
  if (cd "$ROOT/$module" && flutter analyze --no-fatal-infos); then
    ok "sem erros"
  else
    fail "análise falhou em $module"
  fi
done

step "gofmt — backend-go"
unformatted="$(gofmt -l "$ROOT/backend-go/src")"
if [ -z "$unformatted" ]; then
  ok "formatado"
else
  fail "arquivos fora do formato:"$'\n'"$unformatted"
fi

step "go vet — backend-go"
if (cd "$ROOT/backend-go" && go vet ./src/...); then
  ok "sem apontamentos"
else
  fail "go vet falhou"
fi

step "invariantes de arquitetura"
"$ROOT/scripts/check_architecture.sh" || failed=1

printf '\n'
if [ "$failed" -ne 0 ]; then
  printf '\033[31m✗ análise falhou\033[0m\n'
  exit 1
fi
printf '\033[32m✓ análise limpa\033[0m\n'
