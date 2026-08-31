#!/bin/bash
# Runs the package test suite on the first available iPhone simulator.
# Runner images ship different simulator sets, so the device is discovered,
# never hardcoded.
set -euo pipefail

DEVICE_ID=$(xcrun simctl list devices available --json \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for device in devices:
        if device['name'].startswith('iPhone'):
            print(device['udid'])
            sys.exit(0)
sys.exit(1)
")

echo "Using simulator: $DEVICE_ID"

# SPACEZ_CAPTURE_BUDGET_MS: perf-test ceiling. 50 ms is an order of magnitude
# above the 5 ms design budget — generous enough for noisy shared runners,
# tight enough that a real main-thread capture regression still fails CI.
xcodebuild \
  -scheme SpaceZ-Package \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  SPACEZ_CAPTURE_BUDGET_MS="${SPACEZ_CAPTURE_BUDGET_MS:-50}" \
  test | tee /tmp/xcodebuild-test.log | grep -E "Test Suite|Executed|error|SpaceZ perf" || true

# xcodebuild's exit code is lost in the pipe above; verify from the log.
if grep -q "** TEST FAILED **" /tmp/xcodebuild-test.log; then
  exit 1
fi
grep -q "** TEST SUCCEEDED **" /tmp/xcodebuild-test.log
