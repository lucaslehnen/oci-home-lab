# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure as Code project for connecting a local K3s cluster to Oracle Cloud Infrastructure (OCI) via site-to-site VPN. Includes:
- VCN with Class B networking (172.16.0.0/12)
- ARM A1.Flex compute instance (Always Free: 4 OCPUs, 24GB RAM)
- OpenVPN server for site-to-site VPN connectivity to local network (192.168.0.0/24)
- Ollama (LLM inference server) accessible from K3s pods
- Docker for running additional containerized services

**Use case**: Connect local Kubernetes cluster (Raspberry Pi) to OCI, allowing pods to access Ollama and other services running on OCI infrastructure.

## Development Commands

### Initial Setup

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your OCI credentials and settings:
   - `tenancy_ocid`: Your OCI tenancy OCID
   - `user_ocid`: Your user OCID
   - `fingerprint`: Your API key fingerprint
   - `private_key_path`: Path to your OCI API private key
   - `region`: OCI region (default: sa-saopaulo-1)
   - `compartment_ocid`: Target compartment OCID
   - `availability_domain`: Availability domain for resources
   - `ssh_public_key`: Your SSH public key for instance access

### Terraform Commands

```bash
# Initialize Terraform and download providers
terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Apply infrastructure changes
terraform apply

# Destroy all resources
terraform destroy

# Format Terraform files
terraform fmt

# Show current state
terraform show

# List resources in state
terraform state list
```

### OpenVPN Site-to-Site Setup

After infrastructure is deployed:

```bash
# SSH into instance
ssh opc@<PUBLIC_IP>

# Generate client configuration for K3s cluster
sudo /root/generate-client-config.sh k3s-cluster

# Configure site-to-site routing for local network
sudo /root/setup-site-to-site.sh k3s-cluster 192.168.0.0/24

# View connected clients
sudo cat /var/log/openvpn/openvpn-status.log

# View OpenVPN logs
sudo tail -f /var/log/openvpn/openvpn.log

# Restart OpenVPN service
sudo systemctl restart openvpn-server@server

# Download client config to local machine
scp opc@<PUBLIC_IP>:/root/client-configs/k3s-cluster.ovpn .
```

### Ollama Management

```bash
# Check Ollama status
sudo systemctl status ollama

# List installed models
ollama list

# Pull a model
ollama pull llama3.2:1b

# Test model
ollama run llama3.2:1b "Hello!"

# Test API
curl http://localhost:11434/api/version

# View logs
sudo journalctl -u ollama -f
```

### Docker Management

```bash
# Check Docker status
sudo systemctl status docker

# List containers
docker ps -a

# Run test container
docker run -d -p 8080:80 nginx
```

## Architecture

### Infrastructure Components

**Network Layer:**
- **VCN (Virtual Cloud Network)**: Class B network with 172.16.0.0/12 CIDR block (IPv6 disabled)
- **Internet Gateway**: Provides internet access for public resources
- **Route Table**: Routes traffic from subnet to internet gateway (0.0.0.0/0)
- **Security List**: Controls inbound/outbound traffic
  - SSH (port 22): Open to 0.0.0.0/0
  - HTTP (port 80): Open to 0.0.0.0/0
  - HTTPS (port 443): Open to 0.0.0.0/0
  - OpenVPN UDP (port 1194): Open to 0.0.0.0/0
  - OpenVPN TCP (port 1194): Open to 0.0.0.0/0 (alternative)
  - ICMP: Enabled for network diagnostics
- **Subnet**: 172.16.1.0/24 public subnet in main VCN

**Compute Layer:**
- **Compute Instance**: ARM-based Oracle Linux 8 instance
- Default shape: VM.Standard.A1.Flex (Always Free: 4 OCPUs, 24GB RAM)
- Automatic selection of latest Oracle Linux 8 ARM image
- Public IP assigned for internet access
- SSH access via configured public key (user: `opc`)
- OpenVPN server auto-installed via cloud-init

**VPN Layer:**
- **OpenVPN Server**: Installed automatically on instance boot via cloud-init
- VPN subnet: 192.168.100.0/24 (avoids K3s 10.42.0.0/16 and 10.43.0.0/16 conflict)
- Routes OCI VCN (172.16.0.0/12) to VPN clients
- Routes local network (192.168.0.0/24) to OCI via site-to-site config
- Encryption: AES-256-GCM with SHA256 authentication
- Certificate management: Easy-RSA for PKI
- Firewalld configured with IP forwarding and masquerading
- Client-specific configs in `/etc/openvpn/server/ccd/` for site-to-site routing

**Application Layer:**
- **Ollama**: LLM inference server running on port 11434
  - Accessible from K3s pods via private IP
  - ARM-optimized models (llama3.2, mistral, phi3, gemma2)
  - Systemd service configured to auto-start
- **Docker**: Container runtime for additional services
  - User `opc` added to docker group
  - Accessible from K3s for service integration

### File Structure

- `provider.tf`: Terraform and OCI provider configuration
- `variables.tf`: Input variable declarations
- `terraform.tfvars.example`: Example variables file
- `network.tf`: VCN, subnet, security lists, and networking resources
- `compute.tf`: Compute instances and related resources
- `cloud-init.yaml`: Cloud-init script for OpenVPN, Ollama, and Docker installation
- `SETUP_SITE_TO_SITE.md`: Complete guide for configuring K3s to OCI site-to-site VPN
- `outputs.tf`: Output values (IPs, OCIDs, SSH commands, OpenVPN instructions)
- `README.md`: Detailed user documentation in Portuguese
- `CLAUDE.md`: This file

### Important Notes

**Instance Configuration:**
- Default shape: `VM.Standard.A1.Flex` (Always Free: 4 OCPUs ARM, 24GB RAM)
- Alternative Always Free option: `VM.Standard.E2.1.Micro` (x86, lower resources)
- ARM A1 instances are in high demand - may require multiple attempts or different availability domains

**OpenVPN Setup:**
- Automatically configured via cloud-init on first boot (takes 5-10 minutes)
- Scripts available on instance:
  - `/root/setup-openvpn.sh`: Main installation script (runs automatically)
  - `/root/generate-client-config.sh`: Generate client .ovpn files
  - `/root/setup-site-to-site.sh`: Configure site-to-site routing for a client
- Client configurations stored in `/root/client-configs/`
- PKI certificates in `/usr/share/easy-rsa/3/pki/`
- Server logs: `/var/log/openvpn/openvpn.log` and `openvpn-status.log`
- Site-to-site configs: `/etc/openvpn/server/ccd/<client-name>`

**Ollama Setup:**
- Automatically installed via cloud-init (takes ~2-3 minutes)
- Service runs as user `opc` on port 11434 (0.0.0.0)
- No models pre-installed (download as needed: `ollama pull <model>`)
- Logs: `sudo journalctl -u ollama`
- Recommended small models for 24GB RAM: llama3.2:1b, llama3.2:3b, mistral:7b

**Docker Setup:**
- Automatically installed via cloud-init
- User `opc` has docker permissions (no sudo needed)
- Docker Compose available

**Networking:**
- VCN uses Class B private addressing (172.16.0.0/12)
- VPN clients get IPs from 192.168.100.0/24 (avoids K3s 10.x.x.x ranges)
- VPN clients can access entire OCI VCN (172.16.0.0/12)
- IPv6 is explicitly disabled on VCN and subnet
- No conflict with K3s default ranges (10.42.0.0/16 for pods, 10.43.0.0/16 for services)

**Security:**
- Security list allows SSH, HTTP, HTTPS, and OpenVPN from anywhere (0.0.0.0/0)
- For production: restrict source IPs in `network.tf`
- Boot volume is not preserved when instance is destroyed
- Resources are created in the specified availability domain

**Customization:**
- OpenVPN port configurable via `openvpn_port` variable (default: 1194 UDP)
- Local network CIDR configurable via `local_network_cidr` variable (default: 192.168.0.0/24)
- Can use TCP port 443 for restrictive networks
- Ollama accessible on port 11434 (configured in Security List)

**Typical Workflow:**
1. Deploy infrastructure with `terraform apply`
2. Wait ~10 minutes for cloud-init to complete
3. Generate VPN config for K3s: `sudo /root/generate-client-config.sh k3s-cluster`
4. Configure site-to-site: `sudo /root/setup-site-to-site.sh k3s-cluster 192.168.0.0/24`
5. Install OpenVPN client on Raspberry Pi (K3s gateway)
6. Configure IP forwarding and routing on Raspberry Pi
7. K3s pods can now access Ollama at `http://172.16.1.x:11434`
8. Pull Ollama models: `ollama pull llama3.2:1b`

**See SETUP_SITE_TO_SITE.md for detailed K3s integration guide**