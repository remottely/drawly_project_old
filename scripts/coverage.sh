#!/usr/bin/env bash
#
# Cobertura por módulo, com piso mínimo por alvo.
#
# Cobertura é piso, não meta: linha coberta sem asserção útil não conta. O gate
# existe para impedir regressão, não para virar objetivo.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/coverage"
mkdir -p "$OUT"

# módulo:piso:meta
#
# O PISO é anti-regressão: trava o nível já conquistado e falha se cair.
# A META é o alvo da fase 2 (CLAUDE.md §6). Ao atingir a meta, promova o piso.
#
# Por que os pisos ainda estão abaixo das metas:
#   drawly_core     — SocketManager (60% do package) precisa de um duplo do
#                     socket_io_client; coberto de verdade só na fase 3.
#   drawing_board   — canvas_side_bar.dart (552 linhas de UI) ainda sem teste.
#   app             — as páginas grandes só saem do zero quando virarem
#                     controllers testáveis (fase 3.2).
TARGETS=(
  "packages/drawly_core:60:90"
  "packages/drawing_board:60:90"
  "packages/drawly_design_system:40:60"
  ".:35:85"
)
GO_FLOOR=50
GO_GOAL=80

failed=0
summary=()

percent_of_lcov() {
  # LCOV: LF = linhas encontradas, LH = linhas atingidas.
  awk -F: '
    /^LF:/ { found += $2 }
    /^LH:/ { hit   += $2 }
    END    { if (found > 0) printf "%.1f", (hit / found) * 100; else print "0.0" }
  ' "$1"
}

for target in "${TARGETS[@]}"; do
  IFS=':' read -r module floor goal <<< "$target"
  name="$([ "$module" = "." ] && echo "app" || basename "$module")"

  printf '\n\033[1m▸ cobertura — %s\033[0m\n' "$name"

  if ! (cd "$ROOT/$module" && flutter test --coverage --reporter=compact >/dev/null 2>&1); then
    printf '  \033[31m✗ a suíte falhou; cobertura não calculada\033[0m\n'
    failed=1
    continue
  fi

  lcov="$ROOT/$module/coverage/lcov.info"
  if [ ! -f "$lcov" ]; then
    printf '  \033[31m✗ lcov.info não gerado\033[0m\n'
    failed=1
    continue
  fi

  cp "$lcov" "$OUT/$name.lcov.info"
  pct="$(percent_of_lcov "$lcov")"

  if awk "BEGIN { exit !($pct >= $floor) }"; then
    printf '  \033[32m✓ %s%%\033[0m \033[2m(piso %s%% · meta %s%%)\033[0m\n' \
      "$pct" "$floor" "$goal"
    summary+=("$(printf '  ✓ %-22s %6s%%   piso %3s%%   meta %3s%%' \
      "$name" "$pct" "$floor" "$goal")")
  else
    printf '  \033[31m✗ %s%% — abaixo do piso de %s%%\033[0m\n' "$pct" "$floor"
    summary+=("$(printf '  ✗ %-22s %6s%%   piso %3s%%   meta %3s%%' \
      "$name" "$pct" "$floor" "$goal")")
    failed=1
  fi
done

printf '\n\033[1m▸ cobertura — backend-go\033[0m\n'
if (cd "$ROOT/backend-go" && go test -coverprofile="$OUT/go.cover" ./src/... >/dev/null 2>&1); then
  go_pct="$(cd "$ROOT/backend-go" && go tool cover -func="$OUT/go.cover" | awk '/^total:/ { gsub(/%/, "", $3); print $3 }')"
  if awk "BEGIN { exit !($go_pct >= $GO_FLOOR) }"; then
    printf '  \033[32m✓ %s%%\033[0m \033[2m(piso %s%% · meta %s%%)\033[0m\n' \
      "$go_pct" "$GO_FLOOR" "$GO_GOAL"
    summary+=("$(printf '  ✓ %-22s %6s%%   piso %3s%%   meta %3s%%' \
      "backend-go" "$go_pct" "$GO_FLOOR" "$GO_GOAL")")
  else
    printf '  \033[31m✗ %s%% — abaixo do piso de %s%%\033[0m\n' \
      "$go_pct" "$GO_FLOOR"
    summary+=("$(printf '  ✗ %-22s %6s%%   piso %3s%%   meta %3s%%' \
      "backend-go" "$go_pct" "$GO_FLOOR" "$GO_GOAL")")
    failed=1
  fi
  (cd "$ROOT/backend-go" && go tool cover -html="$OUT/go.cover" -o "$OUT/go.html")
else
  printf '  \033[31m✗ a suíte Go falhou\033[0m\n'
  failed=1
fi

printf '\n\033[1mResumo\033[0m\n'
printf '%s\n' "${summary[@]}"
printf '\nRelatórios em %s\n' "$OUT"

# lcov/genhtml é opcional: gera o HTML se estiver instalado.
if command -v genhtml >/dev/null 2>&1; then
  genhtml "$OUT"/*.lcov.info -o "$OUT/dart-html" --quiet 2>/dev/null &&
    printf 'HTML do Dart em %s/dart-html/index.html\n' "$OUT"
fi

[ "$failed" -eq 0 ] || exit 1
