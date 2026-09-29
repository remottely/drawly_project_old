#!/usr/bin/env bash
#
# Valida a mensagem de commit contra a convenção do CLAUDE.md §9:
#
#   0.53.5+4; chore: remove legacy Node.js backend version implementation
#
# Instalar:  ./scripts/install_hooks.sh
set -euo pipefail

message_file="$1"
# Ignora linhas de comentário do git.
subject="$(grep -v '^#' "$message_file" | sed '/^[[:space:]]*$/d' | head -1)"

# Merges e reverts gerados pelo git passam direto.
case "$subject" in
  "Merge "*|"Revert "*|"fixup! "*|"squash! "*) exit 0 ;;
esac

PATTERN='^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?; (feat|fix|refactor|test|perf|docs|style|build|ci|chore): [a-z].{0,60}$'

fail() {
  printf '\033[31m✗ mensagem de commit fora do padrão\033[0m\n\n' >&2
  printf '  recebido: %s\n\n' "$subject" >&2
  printf '  esperado: <versão>; <tipo>: <descrição imperativa em inglês>\n' >&2
  printf '  exemplo:  0.53.5+4; chore: remove legacy Node.js backend\n\n' >&2
  printf '  tipos: feat fix refactor test perf docs style build ci chore\n' >&2
  printf '  regras: descrição em minúscula, sem ponto final, até 60 caracteres\n' >&2
  printf '  %s\n' "$1" >&2
  exit 1
}

printf '%s' "$subject" | grep -qE "$PATTERN" || fail ''

# A versão da mensagem precisa bater com a do pubspec raiz.
repo_root="$(git rev-parse --show-toplevel)"
pubspec_version="$(sed -nE 's/^version: (.+)$/\1/p' "$repo_root/pubspec.yaml")"
message_version="${subject%%;*}"

if [ "$message_version" != "$pubspec_version" ]; then
  fail "versão na mensagem ($message_version) difere do pubspec.yaml ($pubspec_version)"
fi

case "$subject" in
  *.) fail 'a descrição não deve terminar com ponto' ;;
esac
