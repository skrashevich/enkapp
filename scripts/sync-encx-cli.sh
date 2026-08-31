#!/usr/bin/env bash
# Подтягивает исходники encx-cli из upstream в локальный кэш под build/.
#
# Раньше Makefile по умолчанию брал соседний чекаут ../encx-cli. Если тот отставал,
# gomobile собирал урезанный Encx.xcframework, он затирал вендоренный, и сборка падала
# пачкой "has no member" в EncounterClient.swift. Кэш из upstream убирает эту зависимость
# от состояния случайной папки рядом с репозиторием.
#
# Явно заданный ENCX_CLI_ROOT сюда не попадает — Makefile тогда работает с ним как есть.
set -euo pipefail

dest=${1:?usage: sync-encx-cli.sh <dest-dir> [repo-url] [ref]}
repo=${2:-https://github.com/skrashevich/encx-cli}
ref=${3:-HEAD}

if [[ -d "$dest/.git" ]]; then
  echo "==> обновляю $dest до последнего коммита $repo"
  if ! git -C "$dest" fetch --depth 1 origin "$ref"; then
    echo "!! не удалось связаться с upstream — собираю на закэшированном чекауте" >&2
    git -C "$dest" rev-parse --short HEAD
    exit 0
  fi
  git -C "$dest" reset --hard FETCH_HEAD
else
  echo "==> клонирую $repo в $dest"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  git clone --depth 1 --branch "${ref#HEAD}" "$repo" "$dest" 2>/dev/null \
    || git clone --depth 1 "$repo" "$dest"
fi

echo "==> encx-cli @ $(git -C "$dest" rev-parse --short HEAD) ($(git -C "$dest" log -1 --format=%s))"
