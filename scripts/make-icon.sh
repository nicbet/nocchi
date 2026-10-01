#!/usr/bin/env bash
# Render the app icon in every size and build Resources/AppIcon.icns (committed; bundle.sh copies it).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
swift build -c release
work="$(mktemp -d)/AppIcon.iconset"
"$(swift build -c release --show-bin-path)/nocchi" --render-iconset "$work" >/dev/null
iconutil -c icns "$work" -o Resources/AppIcon.icns
echo "$root/Resources/AppIcon.icns"
