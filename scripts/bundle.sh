#!/usr/bin/env bash
# Build nocchi and assemble build/Nocchi.app (the app is "Nocchi"; its executable stays `nocchi`).
# Usage: scripts/bundle.sh [debug|release]   (default: release)
set -euo pipefail

config="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Nocchi.app"

cd "$root"
swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)/nocchi"
version="$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/NocchiCore/Nocchi.swift)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/nocchi"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>Nocchi</string>
    <key>CFBundleDisplayName</key>         <string>Nocchi</string>
    <key>CFBundleIdentifier</key>          <string>com.github.nicbet.nocchi</string>
    <key>CFBundleExecutable</key>          <string>nocchi</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>${version}</string>
    <key>CFBundleVersion</key>             <string>${version}</string>
    <key>LSMinimumSystemVersion</key>      <string>15.0</string>
    <key>LSUIElement</key>                 <true/>
    <key>NSHighResolutionCapable</key>     <true/>
</dict>
</plist>
PLIST

# Sign with the stable local identity when it exists, so privacy grants survive rebuilds.
# Otherwise sign ad hoc. Hints go to stderr: dev.sh reads the app path from the last line.
identity="${SIGNING_IDENTITY:-Local App Signing}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$identity\""; then
    codesign --force --sign "$identity" "$app" >/dev/null 2>&1
else
    echo "Signing ad hoc: permissions reset on every rebuild. Run 'make signing-cert' once to fix that." >&2
    codesign --force --sign - "$app" >/dev/null
fi
echo "$app"
