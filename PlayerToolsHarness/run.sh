#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/enkapp-player-tools.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

cd "$repo_dir"
# A standalone Foundation executable resolves Bundle.main resources beside itself.
cp encx-cli/Resources/ru_dict.bin "$test_dir/ru_dict.bin"
swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
    encx-cli/Anagramizer/*.swift \
    encx-cli/AnagramizerViewModel.swift \
    encx-cli/Ciphers/CipherEngine.swift \
    PlayerToolsHarness/PlayerToolsRegression.swift \
    -o "$test_dir/player-tools-tests"
"$test_dir/player-tools-tests"
