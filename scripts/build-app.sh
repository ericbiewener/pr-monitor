#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

swift build -c release

app_dir="$project_dir/dist/PR Monitor.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$project_dir/.build/release/PRMonitor" "$app_dir/Contents/MacOS/PRMonitor"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"

print "Built $app_dir"
