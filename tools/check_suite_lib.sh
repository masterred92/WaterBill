#!/bin/sh
# Frost Suite library checks. Fails when:
#   * this addon's copy of FrostSuite-1.0 (or the suite's shared test/tool files) differs from the canonical copy;
#   * FrostSuite.lua's content changed without a MINOR bump: newest-version-wins compares MINOR only, so an edit under the
#     same MINOR would be silently ignored in game whenever another addon loads the older copy first. Libs/FrostSuite/HASHES
#     records the sha256 of FrostSuite.lua for every MINOR; the current MINOR must be recorded with the current content,
#     VERSION must equal MINOR, and no two MINORs may share a hash.
# Usage: tools/check_suite_lib.sh [canonical folder]
# The folder may also be set as FROST_SUITE_LIB. Pass "none" to skip the drift check (e.g. in CI).
set -e
cd "$(dirname "$0")/.."
CANON=${1:-${FROST_SUITE_LIB:-}}
status=0
LIB=Libs/FrostSuite
MINOR=$(sed -n 's/^local MAJOR, MINOR = "FrostSuite-1.0", \([0-9][0-9]*\)$/\1/p' $LIB/FrostSuite.lua)
SUM=$(sha256sum $LIB/FrostSuite.lua | cut -c1-64)
[ -n "$MINOR" ] || { echo "FAIL: no MINOR line in $LIB/FrostSuite.lua"; exit 1; }
[ "$(cat $LIB/VERSION)" = "$MINOR" ] || { echo "FAIL: $LIB/VERSION ($(cat $LIB/VERSION)) is not MINOR $MINOR"; status=1; }
REC=$(awk -v m="$MINOR" '$1 == m { print $2 }' $LIB/HASHES)
if [ -z "$REC" ]; then echo "FAIL: MINOR $MINOR is not recorded in $LIB/HASHES"; status=1
elif [ "$REC" != "$SUM" ]; then echo "FAIL: FrostSuite.lua changed without a MINOR bump (MINOR $MINOR is recorded with a different hash)"; status=1; fi
DUP=$(grep -v '^#' $LIB/HASHES | awk '{print $2}' | sort | uniq -d)
[ -z "$DUP" ] || { echo "FAIL: two MINORs share one hash in $LIB/HASHES"; status=1; }
if [ "$CANON" = "none" ]; then
  :
elif [ -z "$CANON" ]; then
  echo "FAIL: no canonical folder (pass one, or set FROST_SUITE_LIB; use 'none' to skip)"
  status=1
else
  for f in FrostSuite.lua VERSION HASHES; do cmp -s "$CANON/$f" "$LIB/$f" || { echo "DRIFT: $LIB/$f"; status=1; }; done
  for f in tests/mock_wow.lua tests/mock_secrets.lua tests/test_frostsuite.lua tools/check_suite_lib.sh tools/verify_unit_events.py tools/verify_media.sh; do
    cmp -s "$CANON/$f" "$f" || { echo "DRIFT: $f"; status=1; }
  done
fi
[ $status -eq 0 ] && echo "FrostSuite-1.0 r$MINOR in sync, content matches its MINOR"
exit $status
