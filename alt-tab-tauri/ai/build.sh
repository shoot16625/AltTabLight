#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "=== Installing frontend dependencies ==="
npm install

echo "=== Building frontend ==="
npx tsc --noEmit
npx vite build

echo "=== Building Rust backend ==="
cargo build --manifest-path src-tauri/Cargo.toml

echo "=== Bundling AltTab.app ==="
npx tauri build --bundles app

echo "=== AltTab Tauri build complete ==="
echo "App bundle: src-tauri/target/release/bundle/macos/AltTab.app"
