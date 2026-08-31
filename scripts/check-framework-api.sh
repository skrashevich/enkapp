#!/usr/bin/env bash
# Отказывает, если свежесобранный Encx.xcframework потерял API, которое есть в закоммиченном.
#
# Устаревший чекаут encx-cli собирается без ошибок, но отдаёт xcframework с
# выпавшими кусками API (управление командой, экспорт HAR). rsync затирает
# вендоренную копию, и сборка падает пачкой "has no member" в EncounterClient.swift —
# далеко от настоящей причины. Проверка ловит это до перезаписи.
#
# Обход осознанного удаления API: ALLOW_FRAMEWORK_API_REMOVAL=1 make framework
set -euo pipefail

new_header=${1:?usage: check-framework-api.sh <new-header> [baseline-ref] [baseline-path]}
baseline_ref=${2:-HEAD}
baseline_path=${3:-encx-cli/Frameworks/Encx.xcframework/ios-arm64_x86_64-simulator/Encx.framework/Headers/Encxmobile.objc.h}

if [[ "${ALLOW_FRAMEWORK_API_REMOVAL:-0}" == "1" ]]; then
  echo "==> ALLOW_FRAMEWORK_API_REMOVAL=1 — проверка API пропущена"
  exit 0
fi

if [[ ! -f "$new_header" ]]; then
  echo "ERROR: не найден заголовок собранного фреймворка: $new_header" >&2
  exit 1
fi

# Селекторы Obj-C плюс все экспортируемые имена Encxmobile*.
symbols() {
  grep -oE '^- \([^)]*\)[A-Za-z_][A-Za-z0-9_]*|Encxmobile[A-Za-z0-9_]+' "$1" \
    | sed -E 's/^- \([^)]*\)//' \
    | sort -u
}

baseline_tmp=$(mktemp)
trap 'rm -f "$baseline_tmp"' EXIT

if ! git show "$baseline_ref:$baseline_path" >"$baseline_tmp" 2>/dev/null; then
  echo "==> нет закоммиченного эталона $baseline_ref:$baseline_path — проверка пропущена"
  exit 0
fi

missing=$(comm -23 <(symbols "$baseline_tmp") <(symbols "$new_header") || true)

if [[ -n "$missing" ]]; then
  count=$(printf '%s\n' "$missing" | wc -l | tr -d ' ')
  cat >&2 <<EOF
ERROR: собранный Encx.xcframework потерял $count имён, которые есть в $baseline_ref.
Почти наверняка ENCX_CLI_ROOT указывает на устаревший чекаут encx-cli.
Вендоренный фреймворк НЕ перезаписан.

Пропало:
EOF
  printf '%s\n' "$missing" | sed 's/^/  - /' >&2
  cat >&2 <<'EOF'

Сборка из нужного чекаута:
  make framework ENCX_CLI_ROOT=/path/to/актуальный/encx-cli

Если API удалено намеренно:
  ALLOW_FRAMEWORK_API_REMOVAL=1 make framework
EOF
  exit 1
fi

echo "==> проверка API пройдена: ничего из $baseline_ref не потеряно"
