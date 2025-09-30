# OCI Base Infrastructure

Projeto Terraform para provisionar infraestrutura na Oracle Cloud Infrastructure (OCI) com:
- **VPN Site-to-Site** via OpenVPN para conectar seu cluster K3s local
- **Ollama** (LLM inference server) rodando em ARM
- **Docker** para containers adicionais

Ideal para conectar seu cluster Kubernetes local à nuvem OCI, permitindo que seus pods acessem Ollama e outros serviços rodando na OCI.

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
             │  • OpenVPN Client instalado                     │
             └──────────────────┬───────────────────────────────┘
                                │
                    ┌───────────▼────────────┐
                    │   Túnel VPN Criptografado
                    │   192.168.100.0/24
                    │   AES-256-GCM + SHA256
                    └───────────┬────────────┘
                                │
                       ═════════▼═════════
                         INTERNET
                       ═════════┬═════════
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
║  │  • IP Público: XXX.XXX.XXX.XXX                                 │    ║
║  │  • IP Privado: 172.16.1.x                                      │    ║
║  └────────────────────────────────────────────────────────────────┘    ║
║         │                        │                         │             ║
║  ┌──────▼──────┐          ┌──────▼──────┐         ┌───────▼────────┐   ║
║  │  OpenVPN    │          │   Ollama    │         │     Docker     │   ║
║  │   Server    │          │   :11434    │         │   Containers   │   ║
║  │             │          │             │         │                │   ║
║  │ 192.168.100.1│          │ LLM Models: │         │  • nginx       │   ║
║  │             │          │ • llama3.2  │         │  • postgres    │   ║
║  │ • Certs     │          │ • mistral   │         │  • redis       │   ║
║  │ • Routing   │          │ • phi3      │         │  • custom...   │   ║
║  └─────────────┘          └─────────────┘         └────────────────┘   ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────┐
│  FLUXO DE COMUNICAÇÃO                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. K3s Pod → VPN Tunnel → Ollama                                      │
│     curl http://172.16.1.x:11434/api/generate                          │
│                                                                         │
│  2. K3s Pod → VPN Tunnel → Docker Container                            │
│     http://172.16.1.x:8080                                             │
│                                                                         │
│  3. OCI Services → VPN Tunnel → K3s Services (opcional)                │
│     http://192.168.0.34:30000                                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  SEGMENTAÇÃO DE REDES                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  📍 Rede Local        192.168.0.0/24      Sua LAN                       │
│  🔐 Túnel VPN         192.168.100.0/24    OpenVPN (sem conflito K3s)   │
│  ☁️  VCN OCI          172.16.0.0/12       Classe B privada             │
│  🐳 K3s Pods          10.42.0.0/16        Kubernetes pods              │
│  ⚙️  K3s Services     10.43.0.0/16        Kubernetes services          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Recursos Criados

- **Virtual Cloud Network (VCN)** Classe B com CIDR 172.16.0.0/12 (IPv6 desabilitado)
- **Internet Gateway** para acesso à internet
- **Subnet pública** (172.16.1.0/24)
- **Security List** com regras para SSH, HTTP, HTTPS, OpenVPN e Ollama
- **Instância ARM A1.Flex** (4 OCPUs, 24GB RAM) com Oracle Linux 8 - Always Free
- **Servidor OpenVPN** configurado para site-to-site VPN
- **Ollama** rodando na porta 11434
- **Docker** e Docker Compose instalados

## Pré-requisitos

1. Conta na Oracle Cloud Infrastructure
2. Terraform >= 1.0 instalado
3. Credenciais OCI configuradas (API Key)
4. Par de chaves SSH para acesso à instância

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

### Configurar VPN Site-to-Site com K3s

**Para guia completo, veja [SETUP_SITE_TO_SITE.md](SETUP_SITE_TO_SITE.md)**

Resumo rápido:

```bash
# 1. SSH na instância OCI
ssh opc@<PUBLIC_IP>

# 2. Gerar certificado para o cluster K3s
sudo /root/generate-client-config.sh k3s-cluster

# 3. Configurar roteamento site-to-site (sua rede local)
sudo /root/setup-site-to-site.sh k3s-cluster 192.168.0.0/24

# 4. Baixar configuração (do seu computador local)
scp opc@<PUBLIC_IP>:/root/client-configs/k3s-cluster.ovpn .

# 5. Instalar na Raspberry Pi (gateway do K3s)
# Copie o arquivo para a Raspberry Pi e configure conforme SETUP_SITE_TO_SITE.md
```

Após configurar, seu cluster K3s poderá acessar:
- Ollama: `http://172.16.1.x:11434`
- Serviços Docker na OCI
- Toda a rede OCI (172.16.0.0/12)

### Verificar Serviços

```bash
# SSH na instância
ssh opc@<PUBLIC_IP>

# Verificar OpenVPN
sudo systemctl status openvpn-server@server
sudo cat /var/log/openvpn/openvpn-status.log

# Verificar Ollama
sudo systemctl status ollama
curl http://localhost:11434/api/version

# Verificar Docker
docker --version
docker ps

# Baixar e testar um modelo Ollama
ollama pull llama3.2:1b
ollama run llama3.2:1b "Hello!"
```

### Destruir Infraestrutura

```bash
terraform destroy
```

## Estrutura de Arquivos

```
.
├── provider.tf              # Configuração do provider OCI
├── variables.tf             # Declaração de variáveis
├── terraform.tfvars.example # Exemplo de valores de variáveis
├── network.tf               # Recursos de rede (VCN, subnet, etc)
├── compute.tf               # Instâncias de computação
├── cloud-init.yaml          # Script de inicialização (OpenVPN + Ollama + Docker)
├── outputs.tf               # Valores de saída
├── README.md                # Este arquivo (documentação principal)
├── CLAUDE.md                # Documentação para Claude Code
└── SETUP_SITE_TO_SITE.md    # Guia detalhado de configuração VPN
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

### Alterar Porta do OpenVPN

Edite em `terraform.tfvars`:

```hcl
openvpn_port = 443  # Usar porta HTTPS, útil em redes restritas
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

⚠️ **Atenção**: A configuração padrão permite SSH, HTTP, HTTPS e OpenVPN de qualquer origem (0.0.0.0/0). Para produção:
- Restrinja o acesso SSH apenas ao seu IP
- Restrinja o acesso OpenVPN aos IPs necessários
- Edite a Security List em `network.tf`

**Boas práticas para OpenVPN:**
- Gere certificados únicos para cada cliente
- Revogue certificados de clientes removidos
- Use senhas fortes para proteção adicional dos certificados
- Monitore logs em `/var/log/openvpn/`

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

### OpenVPN não inicia

```bash
# Verificar logs
sudo journalctl -u openvpn-server@server -f

# Verificar configuração
sudo openvpn --config /etc/openvpn/server/server.conf

# Reiniciar serviço
sudo systemctl restart openvpn-server@server
```

### Não consigo conectar à VPN

1. Verifique se o firewall está configurado:
   ```bash
   sudo firewall-cmd --list-all
   ```

2. Verifique se o IP forwarding está ativo:
   ```bash
   sudo sysctl net.ipv4.ip_forward
   ```

3. Verifique logs do cliente OpenVPN

4. Teste conectividade na porta:
   ```bash
   nc -zvu <PUBLIC_IP> 1194
   ```

## Comandos Úteis

### OpenVPN

```bash
# Gerar certificado para novo cliente
sudo /root/generate-client-config.sh client2

# Configurar site-to-site para nova rede
sudo /root/setup-site-to-site.sh client2 10.0.0.0/24

# Verificar clientes conectados
sudo cat /var/log/openvpn/openvpn-status.log

# Revogar certificado de cliente
cd /usr/share/easy-rsa/3
sudo ./easyrsa revoke client1
sudo ./easyrsa gen-crl
sudo cp pki/crl.pem /etc/openvpn/server/
sudo systemctl restart openvpn-server@server

# Verificar logs em tempo real
sudo tail -f /var/log/openvpn/openvpn.log
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