#!/usr/bin/env bash
#
# Invariantes de arquitetura verificáveis por grep.
#
# Arquitetura que não é checada é arquitetura que já foi violada. Cada regra
# aqui corresponde a uma seção do CLAUDE.md; quando uma fase da refatoração
# conclui, a regra correspondente sai de "informativa" para bloqueante.
set -uo pipefail

cd "$(dirname "$0")/.."

failed=0

# violation <bloqueante:0|1> <descrição> <comando de busca...>
violation() {
  local blocking="$1"; shift
  local description="$1"; shift
  local hits
  hits="$("$@" 2>/dev/null || true)"

  if [ -z "$hits" ]; then
    printf '  \033[32m✓\033[0m %s\n' "$description"
    return
  fi

  if [ "$blocking" -eq 1 ]; then
    printf '  \033[31m✗\033[0m %s\n' "$description"
    failed=1
  else
    printf '  \033[33m•\033[0m %s \033[2m(pendente da refatoração)\033[0m\n' \
      "$description"
  fi
  printf '%s\n' "$hits" | sed 's/^/      /' | head -12
}

printf '  regras ativas\n'

violation 1 'nenhuma string literal de evento fora do contrato' \
  grep -rnE "'(room|game|chat|drawing):[a-zA-Z:]+'" \
    --include='*.dart' lib packages/drawing_board/lib packages/drawly_core/lib/src/managers

violation 1 'nenhuma string literal de evento no Go fora do contrato' \
  grep -rnE --include='*.go' --exclude='*_test.go' \
    '^[^/]*\.(On|Emit)\("(room|game|chat|drawing):' backend-go/src

violation 1 'drawing_board não conhece o app' \
  grep -rn "package:drawly/" packages/

violation 1 'design system não conhece transporte' \
  grep -rn "SocketManager\|RealtimeGateway" packages/drawly_design_system/lib

violation 1 'host de rede não é hardcoded fora do AppConfig' \
  grep -rn "localhost:5555" --include='*.dart' lib packages/*/lib/src/managers \
    packages/*/lib/src/realtime

printf '\n  regras pendentes das fases 3 e 4\n'

violation 0 'domínio do drawing_board não importa Flutter material' \
  grep -rn "package:flutter/material" packages/drawing_board/lib/src/domain/

violation 0 'nenhum ViewModel estende State' \
  grep -rn "ViewModel extends State" --include='*.dart' lib packages

violation 0 'widgets não falam direto com o SocketManager' \
  grep -rln "SocketManager.instance" --include='*.dart' lib packages/drawing_board/lib

violation 0 'nenhum fromJson fora da camada de dados' \
  grep -rln "fromJson" --include='*.dart' lib/features

violation 0 'código de teste não vai para produção' \
  grep -rn "package:drawly/testing/" --include='*.dart' lib

violation 0 'estado do jogo não é global no Go' \
  grep -nE '^var \(' backend-go/src/rooms_manager.go

printf '\n'
if [ "$failed" -ne 0 ]; then
  printf '  \033[31m✗ invariantes de arquitetura violados\033[0m\n'
  exit 1
fi
printf '  \033[32m✓ invariantes de arquitetura respeitados\033[0m\n'
