#!/usr/bin/env sh
# Собирает WASM-ядро и кладёт его рядом с файлами расширения.
set -eu
cd "$(dirname "$0")/.."
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true
cargo build --release -p bip39-pm-wasm --target wasm32-unknown-unknown
cp target/wasm32-unknown-unknown/release/bip39_pm_wasm.wasm extension/pm_core.wasm
echo "Готово: extension/pm_core.wasm. Загрузите папку extension/ как распакованное расширение."
