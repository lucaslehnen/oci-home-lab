variable "tenancy_ocid" {
  description = "OCID of your tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user calling the API"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint for the key pair being used"
  type        = string
}

variable "private_key_path" {
  description = "Path to your private key file"
  type        = string
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "sa-saopaulo-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment where resources will be created"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain where resources will be created"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

variable "instance_shape" {
  description = "Shape of the compute instance (ARM A1.Flex for Always Free)"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs for flexible shapes (Always Free: up to 4 for ARM)"
  type        = number
  default     = 4
}

variable "instance_memory_in_gbs" {
  description = "Amount of memory in GBs for flexible shapes (Always Free: up to 24GB for ARM)"
  type        = number
  default     = 24
}

variable "openvpn_port" {
  description = "Port for OpenVPN server"
  type        = number
  default     = 1194
}

variable "local_network_cidr" {
  description = "CIDR of your local network (e.g., 192.168.0.0/24) for site-to-site VPN routing"
  type        = string
  default     = "192.168.0.0/24"
}