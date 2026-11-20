#!/bin/sh
# Frost Suite: checks every built-in FileDataID the suite uses (sounds and icons in Libs/FrostSuite and the addon's own
# files, plus the chrome textures) exists in the WoW: Forever client build, by asking wago.tools for the file.
# Usage: tools/verify_media.sh [build]   (default 1.60.1.70862). Needs network; not part of the offline tests.
set -e
cd "$(dirname "$0")/.."
BUILD=${1:-1.60.1.70862}
# chrome: ui-tooltip-background, ui-tooltip-border, ui-statusbar, lockbutton-locked-up / -unlocked-up, INV_Drink_18
TEX="137056 137057 137012 525906 525908 132805"
IDS=$( (cat Libs/FrostSuite/FrostSuite.lua *.lua | grep -oE '(sound|icon) = [0-9]{6,}|[0-9]{6,}, *--' | grep -oE '[0-9]{6,}'; echo $TEX | tr ' ' '\n') | sort -un)
fail=0; n=0
for id in $IDS; do
  n=$((n+1))
  type=$(curl -s -A 'Mozilla/5.0' -o /dev/null -w '%{content_type}' --max-time 30 "https://wago.tools/api/casc/$id?version=$BUILD")
  case "$type" in application/octet-stream*) echo "OK   $id" ;; *) echo "MISS $id ($type)"; fail=1 ;; esac
done
echo "$n files checked against $BUILD"
exit $fail
