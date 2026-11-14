#!/usr/bin/env bash
# All test series in parallel (4 at a time), with duration and result.
#   GODOT=/pfad/zu/godot tests/run_all.sh
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="$(mktemp -d)"
START=$(date +%s)
# The slow series start first, so that the four slots finish about at the same time
SLOW="test_systems run_tests test_resume test_core test_world test_match"
{ printf '%s\n' $SLOW; ls tests/*.gd | xargs -n1 basename | sed 's/\.gd$//' | grep -vE "^(boot|test_base|_)" | grep -vxF -f <(printf '%s\n' $SLOW); } | \
  xargs -P4 -I{} bash -c "s=\$(date +%s); timeout ${TEST_TIMEOUT:-900} \"$GODOT\" --headless --path . --script res://tests/boot.gd -- {} > \"$OUT/{}.log\" 2>&1; \
    printf '%-16s %4ss  %s\n' {} \$((\$(date +%s)-s)) \"\$(grep -E 'Fehler\$' \"$OUT/{}.log\")\"; grep -h '^FEHLER' \"$OUT/{}.log\" | sed 's/^/    /'"
echo "Gesamt: $(( $(date +%s) - START ))s  (Protokolle: $OUT)"
