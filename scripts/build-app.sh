#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/McTiler.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/McTilerAgent" "$app_dir/Contents/MacOS/McTilerAgent"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp config.example.toml "$app_dir/Contents/Resources/config.example.toml"
cp "$binary_dir/mctiler" dist/mctiler
codesign --force --sign - --identifier local.mctiler.cli dist/mctiler
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
printf 'Built %s and %s/dist/mctiler\n' "$app_dir" "$PWD"
