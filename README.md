# OCI Base Infrastructure

Projeto Terraform para provisionar infraestrutura na Oracle Cloud Infrastructure (OCI) com:
- **Cloudflare Tunnel (Zero Trust)** para conectar seu cluster K3s local de forma segura
- **Ollama** (LLM inference server) rodando em ARM
- **Docker** para containers adicionais

Ideal para conectar seu cluster Kubernetes local à nuvem OCI via Zero Trust Network Access, permitindo que seus pods acessem Ollama e outros serviços de forma segura, sem portas abertas ou VPN tradicional.

---

## 🏗️ Diagrama de Arquitetura

```
╔══════════════════════════════════════════════════════════════════════════╗
║                         REDE LOCAL (192.168.0.0/24)                      ║
╚══════════════════════════════════════════════════════════════════════════╝
                                    │
          ┌─────────────────────────┴─────────────────────────┐
          │                                                     │
    ┌─────▼──────┐                                      ┌──────▼──────┐
    │  Raspberry │                                      │   Outros    │
    │  Pi K3s    │                                      │ Dispositivos│
    │ 192.168.0.34│                                      │             │
    └─────┬──────┘                                      └─────────────┘
          │
          │  ┌──────────────────────────────────────────────────┐
          └──┤  K3s Cluster                                     │
             │  • Pods: 10.42.0.0/16                           │
             │  • Services: 10.43.0.0/16                       │
             │  • Service Token para autenticação              │
             └──────────────────┬───────────────────────────────┘
                                │
                    ┌───────────▼────────────┐
                    │   DNS Query            │
                    │   ollama.seudominio.com│
                    └───────────┬────────────┘
                                │
                       ═════════▼═════════
                      CLOUDFLARE EDGE NETWORK
                      (Zero Trust Gateway)
                       ═════════┬═════════
                                │
                      ┌─────────▼──────────┐
                      │ Access Policies    │
                      │ • Service Token ✓  │
                      │ • TLS encryption   │
                      └─────────┬──────────┘
                                │
╔═══════════════════════════════▼══════════════════════════════════════════╗
║                    ORACLE CLOUD INFRASTRUCTURE                           ║
║                          VCN: 172.16.0.0/12                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  ┌────────────────────────────────────────────────────────────────┐    ║
║  │  Instância ARM A1.Flex (Always Free)                           │    ║
║  │  • 4 OCPUs ARM64 + 24GB RAM                                    │    ║
║  │  • Oracle Linux 8                                               │    ║
║  │  • IP Público: XXX.XXX.XXX.XXX (apenas SSH)                    │    ║
║  │  • IP Privado: 172.16.1.x                                      │    ║
║  └────────────────────────────────────────────────────────────────┘    ║
║         │                        │                         │             ║
║  ┌──────▼──────┐          ┌──────▼──────┐         ┌───────▼────────┐   ║
║  │ cloudflared │          │   Ollama    │         │     Docker     │   ║
║  │   Tunnel    │──────────│   :11434    │         │   Containers   │   ║
║  │             │          │             │         │                │   ║
║  │ • Sem porta │          │ LLM Models: │         │  • nginx       │   ║
║  │   aberta    │          │ • llama3.2  │         │  • postgres    │   ║
║  │ • TLS auto  │          │ • mistral   │         │  • redis       │   ║
║  │ • Zero Trust│          │ • phi3      │         │  • custom...   │   ║
║  └─────────────┘          └─────────────┘         └────────────────┘   ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────┐
│  FLUXO DE COMUNICAÇÃO                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. K3s Pod → DNS → Cloudflare Edge → Cloudflare Tunnel → Ollama       │
│     curl -H "CF-Access-Client-Id: xxx" \                               │
│          -H "CF-Access-Client-Secret: xxx" \                           │
│          https://ollama.seudominio.com/api/generate                    │
│                                                                         │
│  2. K3s Pod → Cloudflare → Docker Container                            │
│     https://app.seudominio.com                                         │
│                                                                         │
│  3. Navegador → Cloudflare (com autenticação) → OCI Services           │
│     https://ssh.seudominio.com (SSH via browser)                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  SEGURANÇA ZERO TRUST                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  🔐 Sem portas abertas    Apenas SSH (22) aberto na OCI                │
│  🛡️  Zero Trust ZTNA      Autenticação por serviço                      │
│  🔑 Service Tokens        K3s pods se autenticam automaticamente        │
│  🌐 DNS-based access      ollama.seudominio.com (sem IPs)              │
│  📊 Logs centralizados    Dashboard Cloudflare                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Recursos Criados

- **Virtual Cloud Network (VCN)** Classe B com CIDR 172.16.0.0/12 (IPv6 desabilitado)
- **Internet Gateway** para acesso à internet
- **Subnet pública** (172.16.1.0/24)
- **Security List** com regras mínimas (SSH, HTTP, HTTPS, ICMP)
- **Instância ARM A1.Flex** (4 OCPUs, 24GB RAM) com Oracle Linux 8 - Always Free
- **cloudflared** (Cloudflare Tunnel) instalado e pronto para configurar
- **Ollama** rodando na porta 11434 (acesso via Cloudflare Tunnel apenas)
- **Docker** e Docker Compose instalados

## Pré-requisitos

1. Conta na Oracle Cloud Infrastructure
2. **Conta Cloudflare** (plano Free suficiente)
3. **Domínio** configurado no Cloudflare
4. Terraform >= 1.0 instalado
5. Credenciais OCI configuradas (API Key)
6. Par de chaves SSH para acesso à instância

## Configuração Inicial

### 1. Obter Credenciais OCI

Você precisará dos seguintes valores da sua conta OCI:

- **Tenancy OCID**: Settings > Tenancy Details
- **User OCID**: User Settings > User Information
- **API Key Fingerprint**: User Settings > API Keys
- **Private Key**: Arquivo `.pem` da sua API Key
- **Compartment OCID**: Identity > Compartments
- **Availability Domain**: Varia por região (ex: WrbL:SA-SAOPAULO-1-AD-1)

### 2. Configurar Variáveis

```bash
# Copiar arquivo de exemplo
cp terraform.tfvars.example terraform.tfvars

# Editar com suas credenciais
nano terraform.tfvars
```

### 3. Gerar ou usar chave SSH existente

```bash
# Gerar nova chave (opcional)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/oci_instance

# Copiar chave pública para usar no terraform.tfvars
cat ~/.ssh/oci_instance.pub
```

## Uso

### Inicializar Terraform

```bash
terraform init
```

### Validar Configuração

```bash
terraform validate
```

### Planejar Mudanças

```bash
terraform plan
```

### Aplicar Infraestrutura

```bash
terraform apply
```

### Conectar via SSH

Após o apply, o Terraform exibirá o IP público e o comando SSH:

```bash
ssh opc@<PUBLIC_IP>
```

### Configurar Cloudflare Tunnel

**Para guia completo, veja [SETUP_CLOUDFLARE_TUNNEL.md](SETUP_CLOUDFLARE_TUNNEL.md)**

Resumo rápido:

```bash
# 1. SSH na instância OCI
ssh opc@<PUBLIC_IP>

# 2. Autenticar com Cloudflare
cloudflared tunnel login

# 3. Criar tunnel
cloudflared tunnel create oci-tunnel

# 4. Configurar (copiar e editar exemplo)
cp /root/cloudflared-config-example.yml ~/.cloudflared/config.yml
vim ~/.cloudflared/config.yml

# 5. Configurar DNS
cloudflared tunnel route dns oci-tunnel ollama.seudominio.com

# 6. Rodar tunnel
cloudflared tunnel run oci-tunnel

# 7. Instalar como serviço (após testar)
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared

```

Após configurar, seu cluster K3s poderá acessar:
- Ollama: `https://ollama.seudominio.com`
- Serviços Docker na OCI via hostnames
- Acesso via Zero Trust (sem IPs, sem portas abertas)

### Verificar Serviços

```bash
# SSH na instância
ssh opc@<PUBLIC_IP>

# Verificar Cloudflare Tunnel
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -n 20

# Verificar Ollama
sudo systemctl status ollama
curl http://localhost:11434/api/version

# Verificar Docker
docker --version
docker ps

# Baixar e testar um modelo Ollama
ollama pull llama3.2:1b
ollama run llama3.2:1b "Hello!"

# Testar acesso via Cloudflare Tunnel (de fora)
curl https://ollama.seudominio.com/api/version
```

### Destruir Infraestrutura

```bash
terraform destroy
```

## Estrutura de Arquivos

```
.
├── provider.tf                  # Configuração do provider OCI
├── variables.tf                 # Declaração de variáveis
├── terraform.tfvars.example     # Exemplo de valores de variáveis
├── network.tf                   # Recursos de rede (VCN, subnet, etc)
├── compute.tf                   # Instâncias de computação
├── cloud-init.yaml              # Script de inicialização (cloudflared + Ollama + Docker)
├── outputs.tf                   # Valores de saída
├── README.md                    # Este arquivo (documentação principal)
├── CLAUDE.md                    # Documentação para Claude Code
└── SETUP_CLOUDFLARE_TUNNEL.md   # Guia detalhado de configuração Cloudflare Tunnel
```

## Personalização

### Alterar Shape da Instância

Edite em `terraform.tfvars`:

```hcl
# Always Free ARM (padrão)
instance_shape = "VM.Standard.A1.Flex"
instance_ocpus = 4
instance_memory_in_gbs = 24

# Always Free x86
instance_shape = "VM.Standard.E2.1.Micro"

# Shapes pagos (flexíveis)
instance_shape = "VM.Standard.E3.Flex"
instance_ocpus = 2
instance_memory_in_gbs = 16
```

### Adicionar Mais Serviços ao Tunnel

Edite `~/.cloudflared/config.yml` na instância OCI:

```yaml
ingress:
  - hostname: ollama.seudominio.com
    service: http://localhost:11434

  # Adicionar novo serviço
  - hostname: app.seudominio.com
    service: http://localhost:8080

  - service: http_status:404
```

E configure o DNS:
```bash
cloudflared tunnel route dns oci-tunnel app.seudominio.com
```

### Alterar Região

```hcl
region = "us-ashburn-1"  # ou outra região OCI
```

### Personalizar Security Rules

Edite `network.tf` para adicionar ou modificar regras de firewall na Security List.

## Custos

Esta configuração utiliza recursos Always Free da OCI:
- **VM.Standard.A1.Flex**: 4 OCPUs ARM, 24GB RAM (sempre gratuito)
- **VCN e Networking**: Gratuito
- **Public IP**: 1 IP público gratuito

⚠️ **Importante**: O Always Free Tier tem limites. Esta configuração usa o máximo de recursos ARM gratuitos disponíveis.

## Segurança

✅ **Com Cloudflare Tunnel:**
- Ollama e serviços Docker **não estão** expostos diretamente (sem portas abertas)
- Apenas SSH (22) está acessível publicamente
- Todo tráfego passa pelo Zero Trust da Cloudflare
- Autenticação e autorização por serviço
- TLS/HTTPS automático via Cloudflare

**Boas práticas recomendadas:**
- Configure políticas Zero Trust no dashboard Cloudflare
- Use Service Tokens para acesso programático (K3s)
- Restrinja SSH apenas ao seu IP editando `network.tf`
- Monitore logs no dashboard Cloudflare
- Habilite autenticação para serviços sensíveis

## Troubleshooting

### Erro de Autenticação

Verifique se as credenciais em `terraform.tfvars` estão corretas e se o caminho para a chave privada está acessível.

### Erro de Capacity (ARM A1)

Instâncias ARM A1 são muito procuradas. Se receber erro de capacidade:
- Tente outro Availability Domain
- Tente outra região
- Tente em horários diferentes
- Como fallback, use `VM.Standard.E2.1.Micro` (x86, também Always Free mas com menos recursos)

### Erro de Service Limits

Verifique os limites da sua conta OCI para o compartment e região selecionados.

### Cloudflare Tunnel não conecta

```bash
# Verificar logs
sudo journalctl -u cloudflared -n 50

# Testar manualmente
cloudflared tunnel run oci-tunnel

# Verificar configuração
cat ~/.cloudflared/config.yml

# Verificar se o tunnel existe
cloudflared tunnel list

# Reiniciar serviço
sudo systemctl restart cloudflared
```

### Não consigo acessar serviços via Cloudflare

1. Verifique se o DNS está configurado:
   ```bash
   dig ollama.seudominio.com
   # Deve retornar CNAME para o tunnel
   ```

2. Verifique políticas Zero Trust no dashboard Cloudflare

3. Teste acesso local primeiro:
   ```bash
   curl http://localhost:11434/api/version
   ```

4. Verifique se o serviço está no config.yml do tunnel

## Comandos Úteis

### Cloudflare Tunnel

```bash
# Listar tunnels
cloudflared tunnel list

# Ver informações do tunnel
cloudflared tunnel info oci-tunnel

# Adicionar novo hostname
cloudflared tunnel route dns oci-tunnel app.seudominio.com

# Ver rotas DNS configuradas
cloudflared tunnel route dns

# Limpar credenciais (re-authenticate)
rm ~/.cloudflared/cert.pem
cloudflared tunnel login

# Atualizar cloudflared
wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
chmod +x /usr/local/bin/cloudflared
sudo systemctl restart cloudflared
```

### Ollama

```bash
# Listar modelos instalados
ollama list

# Baixar modelo
ollama pull llama3.2:1b

# Rodar modelo interativo
ollama run llama3.2:1b

# Testar API
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2:1b",
  "prompt": "Why is the sky blue?",
  "stream": false
}'

# Verificar uso de recursos
htop
```

### Docker

```bash
# Listar containers
docker ps -a

# Ver logs de container
docker logs <container-id>

# Executar container de teste
docker run -d -p 8080:80 nginx

# Docker compose
docker-compose up -d
```

## Referências

- [OCI Terraform Provider Documentation](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [OCI Always Free Resources](https://www.oracle.com/cloud/free/)
- [OCI Documentation](https://docs.oracle.com/en-us/iaas/Content/home.htm)
- [OpenVPN Documentation](https://openvpn.net/community-resources/)
- [Easy-RSA Documentation](https://easy-rsa.readthedocs.io/)