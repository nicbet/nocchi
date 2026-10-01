#!/usr/bin/env bash
# Rebuild a debug bundle and relaunch it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$("$root/scripts/bundle.sh" debug | tail -1)"
pkill -x nocchi 2>/dev/null || true
open "$app"
