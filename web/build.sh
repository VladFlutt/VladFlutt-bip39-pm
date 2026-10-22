#!/usr/bin/env sh
# Собирает статическое веб-приложение в web/dist: WASM-ядро + общий core.js.
set -eu
cd "$(dirname "$0")/.."
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true
cargo build --release -p bip39-pm-wasm --target wasm32-unknown-unknown
rm -rf web/dist
mkdir -p web/dist
cp web/index.html web/app.js web/style.css extension/core.js web/dist/
cp target/wasm32-unknown-unknown/release/bip39_pm_wasm.wasm web/dist/pm_core.wasm
echo "Готово: web/dist"
