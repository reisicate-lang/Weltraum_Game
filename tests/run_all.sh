#!/usr/bin/env bash
# Alle Testreihen parallel (4 gleichzeitig), mit Dauer und Ergebnis.
#   GODOT=/pfad/zu/godot tests/run_all.sh
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="$(mktemp -d)"
START=$(date +%s)
ls tests/*.gd | xargs -n1 basename | sed 's/\.gd$//' | grep -vE "^(screenshot|shot_build|balance_week|boot|test_base|_)" | \
  xargs -P4 -I{} bash -c "s=\$(date +%s); timeout ${TEST_TIMEOUT:-900} \"$GODOT\" --headless --path . --script res://tests/boot.gd -- {} > \"$OUT/{}.log\" 2>&1; \
    printf '%-16s %4ss  %s\n' {} \$((\$(date +%s)-s)) \"\$(grep -E 'Fehler\$' \"$OUT/{}.log\")\"; grep -h '^FEHLER' \"$OUT/{}.log\" | sed 's/^/    /'"
echo "Gesamt: $(( $(date +%s) - START ))s  (Protokolle: $OUT)"
