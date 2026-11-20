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
# Recorded MINORs never change their hash (a content change takes a new MINOR line, it never rewrites an old one).
# Compared with: the last commit (FROST_SUITE_HASHES_BASE, default HEAD; catches an edit before it is committed), the
# released branch (FROST_SUITE_RELEASED, default origin/main, when fetched; its FrostSuite.lua differing from ours also needs
# a higher MINOR), and each MINOR's own canonical tree, frost-suite-lib-r<N> next to the canonical folder, when present.
hashes_of() { grep -v '^#' | awk 'NF == 2 { print $1, $2 }'; }
recorded() { awk -v m="$1" '$1 == m { print $2 }' $LIB/HASHES; }
for REF in "${FROST_SUITE_HASHES_BASE:-HEAD}" "${FROST_SUITE_RELEASED:-origin/main}"; do
  git cat-file -e "$REF:$LIB/HASHES" 2>/dev/null || continue
  BAD=$(git show "$REF:$LIB/HASHES" | hashes_of | while read -r m h; do
    [ "$(recorded "$m")" = "$h" ] || echo "FAIL: MINOR $m is recorded as ${h%"${h#????????}"}… in $REF but differs (or is missing) here"; done)
  [ -z "$BAD" ] || { echo "$BAD"; status=1; }
done
REL=${FROST_SUITE_RELEASED:-origin/main}
if git cat-file -e "$REL:$LIB/FrostSuite.lua" 2>/dev/null; then
  RSUM=$(git show "$REL:$LIB/FrostSuite.lua" | sha256sum | cut -c1-64)
  RMIN=$(git show "$REL:$LIB/VERSION" 2>/dev/null || echo 0)
  if [ "$RSUM" != "$SUM" ] && [ "$MINOR" -le "$RMIN" ]; then echo "FAIL: FrostSuite.lua differs from $REL (r$RMIN) but MINOR is not higher"; status=1; fi
fi
if [ -n "$CANON" ] && [ "$CANON" != "none" ]; then
  for m in $(grep -v '^#' $LIB/HASHES | awk '{print $1}'); do
    T="$CANON/../frost-suite-lib-r$m/FrostSuite.lua"
    [ -f "$T" ] || continue
    [ "$(sha256sum "$T" | cut -c1-64)" = "$(recorded "$m")" ] || { echo "FAIL: frost-suite-lib-r$m does not match MINOR $m in HASHES"; status=1; }
  done
fi
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
