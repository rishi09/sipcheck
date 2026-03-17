#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="SipCheck"
DESTINATION="platform=iOS Simulator,id=48FF0EDE-5280-4C70-AB5C-F06C750443DB"
RESULT_DIR="/tmp/sipcheck-test-results"

# Parse args
RUN_UNIT=true
RUN_UI=true
VERBOSE=false

for arg in "$@"; do
  case $arg in
    --unit-only) RUN_UI=false ;;
    --ui-only) RUN_UNIT=false ;;
    --verbose) VERBOSE=true ;;
    --destination=*) DESTINATION="${arg#*=}" ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"

echo "=== SipCheck Test Runner ==="
echo "Project: $PROJECT_DIR"
echo "Destination: $DESTINATION"
echo ""

FAILED=0

# Layer A: Unit Tests
if $RUN_UNIT; then
  echo "--- Layer A: Unit Tests (SipCheckTests) ---"
  if xcodebuild test \
    -project "$PROJECT_DIR/SipCheck.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:SipCheckTests \
    -resultBundlePath "$RESULT_DIR/unit-tests.xcresult" \
    2>&1 | { if $VERBOSE; then cat; else grep -E '(Test Suite|Test Case|passed|failed|error:|\*\*)'; fi }; then
    echo "UNIT TESTS: PASSED"
  else
    echo "UNIT TESTS: FAILED"
    FAILED=1
  fi
  echo ""
fi

# Layer C: UI Tests
if $RUN_UI; then
  echo "--- Layer C: UI Tests (SipCheckUITests) ---"
  if xcodebuild test \
    -project "$PROJECT_DIR/SipCheck.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:SipCheckUITests \
    -resultBundlePath "$RESULT_DIR/ui-tests.xcresult" \
    2>&1 | { if $VERBOSE; then cat; else grep -E '(Test Suite|Test Case|passed|failed|error:|\*\*)'; fi }; then
    echo "UI TESTS: PASSED"
  else
    echo "UI TESTS: FAILED"
    FAILED=1
  fi
  echo ""
fi

echo "=== Summary ==="
if [ $FAILED -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
