# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure as Code project for connecting a local K3s cluster to Oracle Cloud Infrastructure (OCI) via Cloudflare Tunnel (Zero Trust). Includes:
- VCN with Class B networking (172.16.0.0/12)
- ARM A1.Flex compute instance (Always Free: 4 OCPUs, 24GB RAM)
- Cloudflare Tunnel (cloudflared) for Zero Trust Network Access to services
- Ollama (LLM inference server) accessible from K3s pods via Cloudflare
- Docker for running additional containerized services

**Use case**: Connect local Kubernetes cluster (Raspberry Pi) to OCI services securely via Cloudflare Zero Trust, allowing pods to access Ollama and other services without exposing ports or managing VPN certificates.

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
   - `private_key`: Your OCI API private key content (for Terraform Cloud)
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

### Cloudflare Tunnel Setup

After infrastructure is deployed:

```bash
# SSH into instance
ssh opc@<PUBLIC_IP>

# Authenticate with Cloudflare
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create oci-tunnel

# Copy and edit configuration
cp /root/cloudflared-config-example.yml ~/.cloudflared/config.yml
vim ~/.cloudflared/config.yml
# Edit with your tunnel ID and domain hostnames

# Configure DNS routing
cloudflared tunnel route dns oci-tunnel ollama.yourdomain.com

# Test tunnel manually
cloudflared tunnel run oci-tunnel

# Install as systemd service
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared

# View tunnel status
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f

# List tunnels
cloudflared tunnel list
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
- **Security List**: Minimal security rules (Cloudflare Tunnel handles access)
  - SSH (port 22): Open to 0.0.0.0/0 (for management)
  - HTTP (port 80): Open to 0.0.0.0/0
  - HTTPS (port 443): Open to 0.0.0.0/0
  - ICMP: Enabled for network diagnostics
  - **Note**: Ollama and Docker services NOT exposed directly (accessed via Cloudflare Tunnel only)
- **Subnet**: 172.16.1.0/24 public subnet in main VCN

**Compute Layer:**
- **Compute Instance**: ARM-based Oracle Linux 8 instance
- Default shape: VM.Standard.A1.Flex (Always Free: 4 OCPUs, 24GB RAM)
- Automatic selection of latest Oracle Linux 8 ARM image
- Public IP assigned for SSH access only
- SSH access via configured public key (user: `opc`)
- cloudflared auto-installed via cloud-init

**Zero Trust Layer:**
- **Cloudflare Tunnel (cloudflared)**: Installed automatically on instance boot via cloud-init
- Provides secure access to services without exposing ports
- TLS encryption handled by Cloudflare
- Zero Trust policies enforce authentication/authorization
- DNS-based access (e.g., ollama.yourdomain.com)
- Service Tokens for programmatic access (K3s pods)
- No certificate management needed (Cloudflare handles it)

**Application Layer:**
- **Ollama**: LLM inference server running on port 11434 (localhost only)
  - Accessible from K3s pods via Cloudflare Tunnel
  - ARM-optimized models (llama3.2, mistral, phi3, gemma2)
  - Systemd service configured to auto-start
- **Docker**: Container runtime for additional services
  - User `opc` added to docker group
  - Services accessible via Cloudflare Tunnel hostnames

### File Structure

- `provider.tf`: Terraform and OCI provider configuration (Terraform Cloud setup)
- `variables.tf`: Input variable declarations
- `terraform.tfvars.example`: Example variables file
- `network.tf`: VCN, subnet, security lists, and networking resources
- `compute.tf`: Compute instances and related resources
- `cloud-init.yaml`: Cloud-init script for cloudflared, Ollama, and Docker installation
- `SETUP_CLOUDFLARE_TUNNEL.md`: Complete guide for configuring Cloudflare Tunnel and K3s integration
- `outputs.tf`: Output values (IPs, OCIDs, SSH commands, Cloudflare Tunnel instructions)
- `README.md`: Detailed user documentation in Portuguese
- `CLAUDE.md`: This file

### Important Notes

**Instance Configuration:**
- Default shape: `VM.Standard.A1.Flex` (Always Free: 4 OCPUs ARM, 24GB RAM)
- Alternative Always Free option: `VM.Standard.E2.1.Micro` (x86, lower resources)
- ARM A1 instances are in high demand - may require multiple attempts or different availability domains

**Cloudflare Tunnel Setup:**
- Automatically installed via cloud-init on first boot (takes ~2-3 minutes)
- Binary installed at `/usr/local/bin/cloudflared`
- Example config at `/root/cloudflared-config-example.yml`
- Must be configured manually after deployment:
  1. Authenticate: `cloudflared tunnel login`
  2. Create tunnel: `cloudflared tunnel create oci-tunnel`
  3. Configure services in `~/.cloudflared/config.yml`
  4. Route DNS: `cloudflared tunnel route dns oci-tunnel <hostname>`
  5. Install as service: `sudo cloudflared service install`
- Service logs: `sudo journalctl -u cloudflared -f`
- Tunnel status: Check Cloudflare dashboard at https://one.dash.cloudflare.com/

**Ollama Setup:**
- Automatically installed via cloud-init (takes ~2-3 minutes)
- Service runs as user `opc` on port 11434 (localhost only, not exposed)
- No models pre-installed (download as needed: `ollama pull <model>`)
- Logs: `sudo journalctl -u ollama`
- Recommended small models for 24GB RAM: llama3.2:1b, llama3.2:3b, mistral:7b
- Accessible from K3s via Cloudflare Tunnel: `https://ollama.yourdomain.com`

**Docker Setup:**
- Automatically installed via cloud-init
- User `opc` has docker permissions (no sudo needed)
- Docker Compose available
- Services accessible via Cloudflare Tunnel hostnames

**Networking:**
- VCN uses Class B private addressing (172.16.0.0/12)
- IPv6 is explicitly disabled on VCN and subnet
- No VPN subnets needed (Cloudflare handles connectivity)
- K3s pods access services via DNS (ollama.yourdomain.com)
- No IP routing or forwarding configuration needed

**Security:**
- Security list only exposes SSH (22), HTTP (80), HTTPS (443), and ICMP
- Ollama and Docker services NOT exposed directly (no open ports)
- All application traffic goes through Cloudflare Zero Trust
- Zero Trust policies enforce authentication/authorization
- Service Tokens allow K3s pods to authenticate programmatically
- Boot volume is not preserved when instance is destroyed
- Resources are created in the specified availability domain

**Customization:**
- Add more services by editing `~/.cloudflared/config.yml` ingress rules
- Configure Zero Trust policies in Cloudflare dashboard
- Restrict SSH access by editing Security List in `network.tf`

**Typical Workflow:**
1. Deploy infrastructure with `terraform apply`
2. Wait ~3 minutes for cloud-init to complete
3. SSH into instance: `ssh opc@<PUBLIC_IP>`
4. Configure Cloudflare Tunnel (authenticate, create, configure)
5. Install tunnel as systemd service
6. Configure Zero Trust policies (optional but recommended)
7. Create Service Token for K3s in Cloudflare dashboard
8. Configure K3s pods with Service Token to access Ollama
9. K3s pods can now access Ollama at `https://ollama.yourdomain.com`
10. Pull Ollama models: `ollama pull llama3.2:1b`

**See SETUP_CLOUDFLARE_TUNNEL.md for detailed configuration guide**
- use a chave ssh em ~/.ssh/oci_instance