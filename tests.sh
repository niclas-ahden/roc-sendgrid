#!/usr/bin/env bash
set -eo pipefail

cd "$(dirname "$0")"

FILTER="${1:-}"
FAILED=0
PASSED=0

for test_file in tests/test_*.roc; do
    test_name=$(basename "$test_file" .roc)

    # Apply filter if provided
    if [[ -n "$FILTER" && ! "$test_name" =~ $FILTER ]]; then
        continue
    fi

    echo -n "Running: $test_name ... "
    if roc dev "$test_file" --linker=legacy 2>&1; then
        echo "PASS"
        ((PASSED++))
    else
        echo "FAIL"
        ((FAILED++))
        if [[ "${2:-}" == "--fail-fast" ]]; then
            echo "Stopping on first failure."
            exit 1
        fi
    fi
done

echo
echo "Results: $PASSED passed, $FAILED failed"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
