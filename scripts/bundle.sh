#!/usr/bin/env bash
# Build nocchi and assemble build/nocchi.app.
# Usage: scripts/bundle.sh [debug|release]   (default: release)
set -euo pipefail

config="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/nocchi.app"

cd "$root"
swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)/nocchi"
version="$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/NocchiCore/Nocchi.swift)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/nocchi"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>nocchi</string>
    <key>CFBundleDisplayName</key>         <string>nocchi</string>
    <key>CFBundleIdentifier</key>          <string>com.github.nicbet.nocchi</string>
    <key>CFBundleExecutable</key>          <string>nocchi</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>${version}</string>
    <key>CFBundleVersion</key>             <string>${version}</string>
    <key>LSMinimumSystemVersion</key>      <string>15.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSHighResolutionCapable</key>     <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app" >/dev/null
echo "$app"
