#!/bin/bash

# Script to upgrade ARM A1 instance from 1 OCPU + 6GB to 4 OCPUs + 24GB
# This script uses OCI CLI to resize the instance without destroying it

set -e

TARGET_OCPUS=4
TARGET_MEMORY_GB=24

echo "=========================================="
echo "ARM A1 Instance Shape Upgrade Script"
echo "=========================================="
echo "Target: ${TARGET_OCPUS} OCPUs + ${TARGET_MEMORY_GB}GB RAM"
echo ""

# Get instance OCID from Terraform output
echo "Getting instance OCID from Terraform..."
INSTANCE_OCID=$(terraform output -raw instance_id 2>/dev/null)

if [ -z "$INSTANCE_OCID" ]; then
  echo "❌ ERROR: Could not get instance OCID from Terraform output"
  echo "Make sure the instance is created first"
  exit 1
fi

echo "✅ Instance OCID: $INSTANCE_OCID"
echo ""

# Get current shape config
echo "Getting current instance shape..."
CURRENT_OCPUS=$(terraform output -json | jq -r '.instance_id.value' | xargs -I {} oci compute instance get --instance-id {} --query 'data."shape-config".ocpus' --raw-output 2>/dev/null || echo "unknown")

echo "Current shape: $CURRENT_OCPUS OCPUs"
echo ""

# Check if instance is running
echo "Checking instance state..."
INSTANCE_STATE=$(oci compute instance get --instance-id "$INSTANCE_OCID" --query 'data."lifecycle-state"' --raw-output)

if [ "$INSTANCE_STATE" != "RUNNING" ] && [ "$INSTANCE_STATE" != "STOPPED" ]; then
  echo "❌ ERROR: Instance is in state: $INSTANCE_STATE"
  echo "Instance must be RUNNING or STOPPED to resize"
  exit 1
fi

echo "✅ Instance state: $INSTANCE_STATE"
echo ""

# Stop instance if running (required for resize)
if [ "$INSTANCE_STATE" = "RUNNING" ]; then
  echo "Stopping instance (required for resize)..."
  oci compute instance action --instance-id "$INSTANCE_OCID" --action STOP --wait-for-state STOPPED
  echo "✅ Instance stopped"
  echo ""
fi

# Resize instance
echo "Resizing instance to ${TARGET_OCPUS} OCPUs + ${TARGET_MEMORY_GB}GB RAM..."
oci compute instance update \
  --instance-id "$INSTANCE_OCID" \
  --shape-config "{\"ocpus\": ${TARGET_OCPUS}, \"memoryInGBs\": ${TARGET_MEMORY_GB}}" \
  --force \
  --wait-for-state STOPPED

echo "✅ Instance resized successfully!"
echo ""

# Start instance
echo "Starting instance..."
oci compute instance action --instance-id "$INSTANCE_OCID" --action START --wait-for-state RUNNING
echo "✅ Instance started"
echo ""

# Update variables.tf with new values
echo "Updating variables.tf with new default values..."
sed -i.bak "s/default     = [0-9]\+$/default     = ${TARGET_OCPUS}/" variables.tf
sed -i.bak "s/default     = [0-9]\+$/default     = ${TARGET_MEMORY_GB}/" variables.tf

# More precise update using awk
awk -v ocpus="$TARGET_OCPUS" -v mem="$TARGET_MEMORY_GB" '
/^variable "instance_ocpus"/ { in_ocpus=1 }
/^variable "instance_memory_in_gbs"/ { in_ocpus=0; in_memory=1 }
/^variable/ && !/^variable "instance_(ocpus|memory_in_gbs)"/ { in_ocpus=0; in_memory=0 }
in_ocpus && /default/ { sub(/default *= *[0-9]+/, "default     = " ocpus); in_ocpus=0 }
in_memory && /default/ { sub(/default *= *[0-9]+/, "default     = " mem); in_memory=0 }
{ print }
' variables.tf > variables.tf.tmp && mv variables.tf.tmp variables.tf

echo "✅ variables.tf updated"
echo ""

# Sync Terraform state
echo "Syncing Terraform state..."
terraform apply -refresh-only -auto-approve

echo ""
echo "=========================================="
echo "✅ SUCCESS! Instance upgraded to ${TARGET_OCPUS} OCPUs + ${TARGET_MEMORY_GB}GB RAM"
echo "=========================================="
echo ""
echo "Terraform state is now synchronized."
echo ""

# Show final output
terraform output