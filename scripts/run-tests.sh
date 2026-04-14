#!/usr/bin/env bash
# Runs every tests/*.sql file in the container against a freshly-reset db.
# Each test file is expected to raise an exception on failure (DO blocks with
# ASSERT or RAISE). A file that completes without error is a pass.

set -euo pipefail

cd "$(dirname "$0")/.."

DC="docker compose"
PSQL="$DC exec -T db psql -U wiki -d wiki -v ON_ERROR_STOP=1 -q -X"

# Ensure stack is up and migrations applied from a clean slate.
make --no-print-directory reset >/dev/null

shopt -s nullglob
tests=(tests/*.sql)
if [ "${#tests[@]}" -eq 0 ]; then
  echo "no tests found"
  exit 0
fi

pass=0
fail=0
failed_files=()

for f in "${tests[@]}"; do
  name=$(basename "$f")
  printf "  %-40s " "$name"
  if out=$($PSQL -f "/$f" 2>&1); then
    echo "PASS"
    pass=$((pass + 1))
  else
    echo "FAIL"
    echo "----"
    echo "$out" | sed 's/^/    /'
    echo "----"
    fail=$((fail + 1))
    failed_files+=("$name")
  fi
done

echo
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failed_files[@]}"
  exit 1
fi
