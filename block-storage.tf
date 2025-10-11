# Block Volume for additional storage
resource "oci_core_volume" "data" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  display_name        = "volume-data"
  size_in_gbs         = var.block_volume_size_in_gbs
}

# Attach block volume to instance
resource "oci_core_volume_attachment" "data" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.main.id
  volume_id       = oci_core_volume.data.id
  display_name    = "data-volume-attachment"
}
