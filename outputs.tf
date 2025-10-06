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

output "cloudflare_tunnel_info" {
  description = "Cloudflare Tunnel setup information"
  value = {
    status = "cloudflared is being installed via cloud-init (takes ~2-3 minutes)"
    setup_instructions = [
      "1. SSH into the instance: ssh opc@${oci_core_instance.main.public_ip}",
      "2. Authenticate with Cloudflare: cloudflared tunnel login",
      "3. Create tunnel: cloudflared tunnel create oci-tunnel",
      "4. Copy example config: cp /root/cloudflared-config-example.yml ~/.cloudflared/config.yml",
      "5. Edit config with your tunnel ID and domains",
      "6. Route DNS: cloudflared tunnel route dns oci-tunnel ollama.yourdomain.com",
      "7. Run tunnel: cloudflared tunnel run oci-tunnel",
      "8. Install as service: cloudflared service install",
      "",
      "See SETUP_CLOUDFLARE_TUNNEL.md for complete Zero Trust setup guide"
    ]
  }
}

output "ollama_info" {
  description = "Ollama service information"
  value = {
    status          = "Ollama is being installed via cloud-init (takes ~2-3 minutes)"
    local_endpoint  = "http://localhost:11434"
    access_method   = "Via Cloudflare Tunnel only (not exposed publicly)"
    test_command    = "curl http://localhost:11434/api/version"
  }
}