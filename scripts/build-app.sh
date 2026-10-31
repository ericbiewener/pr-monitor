#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

swift build -c release

app_dir="$project_dir/dist/PR Monitor.app"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/PRMonitor" "$app_dir/Contents/MacOS/PRMonitor"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/pr-monitor-icon.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
iconset_dir="$temporary_dir/AppIcon.iconset"
mkdir -p "$iconset_dir"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$project_dir/icon.png" \
        --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    retina_size=$(( size * 2 ))
    sips -s format png -z "$retina_size" "$retina_size" "$project_dir/icon.png" \
        --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app_dir"

print "Built $app_dir"
