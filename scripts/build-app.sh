#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/McTiler.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/McTilerAgent" "$app_dir/Contents/MacOS/McTilerAgent"
cp Resources/McTiler-icon-graphite-orange.png "$app_dir/Contents/Resources/McTiler-icon-graphite-orange.png"
iconset_dir="$PWD/.build/McTiler.iconset"
mkdir -p "$iconset_dir"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/McTiler-icon-graphite-orange.png --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Resources/McTiler-icon-graphite-orange.png --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/McTiler.icns"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp config.example.toml "$app_dir/Contents/Resources/config.example.toml"
cp "$binary_dir/mctiler" dist/mctiler
codesign --force --sign - --identifier local.mctiler.cli dist/mctiler
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
printf 'Built %s and %s/dist/mctiler\n' "$app_dir" "$PWD"
