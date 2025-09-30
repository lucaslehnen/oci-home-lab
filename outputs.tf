output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.main.id
}

output "subnet_id" {
  description = "OCID of the subnet"
  value       = oci_core_subnet.main.id
}

output "instance_id" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.main.id
}

output "instance_public_ip" {
  description = "Public IP address of the compute instance"
  value       = oci_core_instance.main.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the compute instance"
  value       = oci_core_instance.main.private_ip
}

output "ssh_connection" {
  description = "SSH connection command"
  value       = "ssh opc@${oci_core_instance.main.public_ip}"
}

output "openvpn_info" {
  description = "OpenVPN server information"
  value = {
    status = "OpenVPN server is being configured via cloud-init (takes ~5-10 minutes)"
    port   = var.openvpn_port
    setup_instructions = [
      "1. SSH into the instance: ssh opc@${oci_core_instance.main.public_ip}",
      "2. Check OpenVPN status: sudo systemctl status openvpn-server@server",
      "3. Generate client config: sudo /root/generate-client-config.sh client1",
      "4. Download config: scp opc@${oci_core_instance.main.public_ip}:/root/client-configs/client1.ovpn .",
      "5. Import the .ovpn file into your OpenVPN client (available for Windows, Mac, Linux, iOS, Android)"
    ]
  }
}