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
#
# The verdict is xcodebuild's own exit code — never scraped from its output,
# which varies across Xcode versions and greps.
set +e
xcodebuild \
  -scheme SpaceZ-Package \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  SPACEZ_CAPTURE_BUDGET_MS="${SPACEZ_CAPTURE_BUDGET_MS:-50}" \
  test > /tmp/xcodebuild-test.log 2>&1
STATUS=$?
set -e

grep -E "Test Suite '.*' (started|passed|failed)|Executed .* tests|error:|SpaceZ perf" \
  /tmp/xcodebuild-test.log || true

echo "xcodebuild exit status: $STATUS"
exit "$STATUS"
