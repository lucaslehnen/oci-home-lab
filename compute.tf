# Data source to get the latest Oracle Linux ARM image
data "oci_core_images" "oracle_linux_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Compute Instance - ARM A1 (Always Free: 4 OCPUs, 24GB RAM)
resource "oci_core_instance" "main" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  display_name        = "instance-main"
  shape               = var.instance_shape

  # Shape config for ARM A1 Flex
  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_in_gbs
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux_arm.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.main.id
    assign_public_ip = "true"
    display_name     = "vnic-main"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("${path.module}/cloud-init.yaml"))
  }

  preserve_boot_volume = false
}