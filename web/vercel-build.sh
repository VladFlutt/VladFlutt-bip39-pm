#!/usr/bin/env sh
# Сборка на Vercel: в образе сборки Rust обычно уже есть (/rust), иначе ставим rustup.
set -eu
for env in "$HOME/.cargo/env" /rust/env; do
  if [ -f "$env" ]; then . "$env"; fi
done
if ! command -v cargo >/dev/null 2>&1; then
  curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  . "$HOME/.cargo/env"
fi
rustup target add wasm32-unknown-unknown
cargo --version
sh web/build.sh
