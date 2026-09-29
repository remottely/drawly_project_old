#!/usr/bin/env bash
#
# Sincroniza a versão do produto nos 5 lugares onde ela existe.
#
# App, os três packages e a constante Version do Go sobem juntos. Versão
# divergente é bug de release, não flexibilidade (CLAUDE.md §8).
#
#   ./scripts/set_version.sh 0.54.0+5   define a versão
#   ./scripts/set_version.sh --check    apenas valida que estão iguais
set -euo pipefail

cd "$(dirname "$0")/.."

ROOT_PUBSPEC="pubspec.yaml"
PACKAGE_PUBSPECS=(
  "packages/drawly_core/pubspec.yaml"
  "packages/drawly_design_system/pubspec.yaml"
  "packages/drawing_board/pubspec.yaml"
)
GO_VERSION_FILE="backend-go/src/main.go"

read_pubspec_version() { sed -nE 's/^version: (.+)$/\1/p' "$1"; }
read_go_version()      { sed -nE 's/.*Version = "(.+)".*/\1/p' "$GO_VERSION_FILE"; }

# Os packages e o Go não carregam o sufixo +BUILD; só o app publicável carrega.
strip_build() { printf '%s' "${1%%+*}"; }

usage() {
  echo "uso: $0 <versão MAJOR.MINOR.PATCH[+BUILD]> | --check" >&2
  exit 2
}

[ $# -eq 1 ] || usage

if [ "$1" = "--check" ]; then
  root="$(read_pubspec_version "$ROOT_PUBSPEC")"
  expected="$(strip_build "$root")"
  failed=0

  for pubspec in "${PACKAGE_PUBSPECS[@]}"; do
    actual="$(read_pubspec_version "$pubspec")"
    if [ "$actual" != "$expected" ]; then
      printf '\033[31m✗\033[0m %s está em %s, esperado %s\n' \
        "$pubspec" "$actual" "$expected"
      failed=1
    fi
  done

  go_version="$(read_go_version)"
  if [ "$go_version" != "$expected" ]; then
    printf '\033[31m✗\033[0m %s está em %s, esperado %s\n' \
      "$GO_VERSION_FILE" "$go_version" "$expected"
    failed=1
  fi

  if [ "$failed" -ne 0 ]; then
    printf '\n\033[31mVersões divergentes.\033[0m Rode: %s %s\n' "$0" "$root"
    exit 1
  fi

  printf '\033[32m✓\033[0m versões sincronizadas em %s (app: %s)\n' \
    "$expected" "$root"
  exit 0
fi

version="$1"
if ! printf '%s' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$'; then
  echo "versão inválida: $version" >&2
  usage
fi

base="$(strip_build "$version")"

sed -i.bak -E "s/^version: .+$/version: $version/" "$ROOT_PUBSPEC"
for pubspec in "${PACKAGE_PUBSPECS[@]}"; do
  sed -i.bak -E "s/^version: .+$/version: $base/" "$pubspec"
done
sed -i.bak -E "s/Version = \".+\"/Version = \"$base\"/" "$GO_VERSION_FILE"

find . -name '*.bak' -maxdepth 4 -delete

printf '\033[32m✓\033[0m versão definida: app %s, módulos %s\n' "$version" "$base"
printf '\nCommit sugerido:\n  %s; chore: bump version\n' "$version"
