# Object Storage Bucket for Backups
# Tier: Standard (default)
# Lifecycle: Objects move to Archive after 1 week, deleted after 30 days

resource "oci_objectstorage_bucket" "backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace

  name       = "backups"
  storage_tier = "Standard"
}

resource "oci_objectstorage_object_lifecycle_policy" "backups_lifecycle" {
  namespace = data.oci_objectstorage_namespace.ns.namespace
  bucket    = oci_objectstorage_bucket.backups.name

  rules {
    name        = "archive_after_7_days"
    action      = "ARCHIVE"
    target      = "objects"
    time_amount = 7
    time_unit   = "DAYS"
    is_enabled  = true
  }

  rules {
    name        = "delete_after_30_days"
    action      = "DELETE"
    target      = "objects"
    time_amount = 30
    time_unit   = "DAYS"
    is_enabled  = true
  }
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# Output bucket details
output "bucket_name" {
  description = "Name of the backups bucket"
  value       = oci_objectstorage_bucket.backups.name
}

output "bucket_id" {
  description = "OCID of the backups bucket"
  value       = oci_objectstorage_bucket.backups.id
}

output "bucket_namespace" {
  description = "Object Storage namespace"
  value       = data.oci_objectstorage_namespace.ns.namespace
}