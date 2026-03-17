#!/bin/bash

# Script to retry ARM A1 instance creation until successful
# Usage: ./retry-arm-instance.sh [wait_seconds]

set -e

WAIT_TIME=${1:-60}  # Default: wait 60 seconds between attempts
ATTEMPT=1

echo "=========================================="
echo "ARM A1 Instance Creation Retry Script"
echo "=========================================="
echo "Wait time between attempts: ${WAIT_TIME}s"
echo "Press Ctrl+C to stop"
echo ""

while true; do
  echo "----------------------------------------"
  echo "Attempt #${ATTEMPT} at $(date '+%Y-%m-%d %H:%M:%S')"
  echo "----------------------------------------"

  # Try to apply
  if terraform apply -auto-approve 2>&1 | tee /tmp/terraform-apply.log; then
    # Check if instance was created successfully
    if grep -q "Apply complete!" /tmp/terraform-apply.log; then
      echo ""
      echo "=========================================="
      echo "✅ SUCCESS! Instance created after ${ATTEMPT} attempt(s)"
      echo "=========================================="
      terraform output
      exit 0
    fi
  fi

  # Check if error is capacity related
  if grep -q "Out of host capacity" /tmp/terraform-apply.log; then
    echo ""
    echo "⏳ No capacity available. Waiting ${WAIT_TIME}s before retry #$((ATTEMPT + 1))..."
    echo "   (Started at $(date '+%H:%M:%S'), next attempt at $(date -v+${WAIT_TIME}S '+%H:%M:%S' 2>/dev/null || date -d "+${WAIT_TIME} seconds" '+%H:%M:%S' 2>/dev/null || echo 'soon'))"
    sleep ${WAIT_TIME}
    ATTEMPT=$((ATTEMPT + 1))
  else
    # Different error - stop and show
    echo ""
    echo "❌ Unexpected error occurred. Check output above."
    exit 1
  fi
done