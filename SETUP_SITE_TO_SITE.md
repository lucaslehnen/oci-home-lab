# Configuração Site-to-Site VPN: K3s Local ↔ OCI

Este guia explica como configurar a VPN site-to-site entre seu cluster K3s local (Raspberry Pi) e a instância OCI.

## Arquitetura

```
Rede Local (192.168.0.0/24)
    │
    ├─ Raspberry Pi K3s (192.168.0.34)
    │  └─ Cliente OpenVPN
    │      └─ Túnel VPN (192.168.100.x)
    │          │
    │          └─ Internet
    │              │
    │              └─ OCI Instance (Public IP)
    │                  ├─ Servidor OpenVPN (192.168.100.1)
    │                  ├─ VCN OCI (172.16.0.0/12)
    │                  ├─ Ollama (172.16.1.x:11434)
    │                  └─ Docker
```

## Passo 1: Gerar Certificado para o K3s Cluster

Na instância OCI:

```bash
ssh opc@<PUBLIC_IP>

# Gerar certificado para o cluster K3s
sudo /root/generate-client-config.sh k3s-cluster

# Configurar roteamento site-to-site
sudo /root/setup-site-to-site.sh k3s-cluster 192.168.0.0/24
```

## Passo 2: Baixar Configuração VPN

Do seu computador local:

```bash
# Baixar arquivo de configuração
scp opc@<PUBLIC_IP>:/root/client-configs/k3s-cluster.ovpn ~/k3s-cluster.ovpn
```

## Passo 3: Configurar Raspberry Pi como Gateway VPN

### 3.1. Instalar OpenVPN na Raspberry Pi

```bash
# SSH na Raspberry Pi
ssh pi@192.168.0.34

# Instalar OpenVPN
sudo apt update
sudo apt install openvpn

# Copiar arquivo de configuração
# (transfira o k3s-cluster.ovpn para a Raspberry Pi)
sudo cp k3s-cluster.ovpn /etc/openvpn/client/k3s-cluster.conf
```

### 3.2. Habilitar IP Forwarding

```bash
# Habilitar permanentemente
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 3.3. Configurar Roteamento

```bash
# Adicionar rota para a rede OCI via túnel VPN
# Adicione ao /etc/network/interfaces ou crie script de inicialização
cat << 'EOF' | sudo tee /etc/openvpn/client/route-up.sh
#!/bin/bash
# Adiciona rota para a VCN OCI
ip route add 172.16.0.0/12 via 192.168.100.1 dev tun0
EOF

sudo chmod +x /etc/openvpn/client/route-up.sh

# Modificar arquivo de configuração do OpenVPN
echo "script-security 2" | sudo tee -a /etc/openvpn/client/k3s-cluster.conf
echo "route-up /etc/openvpn/client/route-up.sh" | sudo tee -a /etc/openvpn/client/k3s-cluster.conf
```

### 3.4. Iniciar OpenVPN

```bash
# Iniciar cliente OpenVPN
sudo systemctl enable openvpn-client@k3s-cluster
sudo systemctl start openvpn-client@k3s-cluster

# Verificar status
sudo systemctl status openvpn-client@k3s-cluster

# Verificar túnel
ip addr show tun0
ping 10.8.0.1
```

## Passo 4: Testar Conectividade

### 4.1. Da Raspberry Pi para OCI

```bash
# Ping para o servidor OpenVPN
ping 192.168.100.1

# Ping para a instância OCI (IP privado)
ping 172.16.1.x  # Substitua pelo IP privado da instância

# Testar Ollama
curl http://172.16.1.x:11434/api/version
```

### 4.2. Da OCI para Rede Local (opcional)

Na instância OCI:

```bash
# Ping para a Raspberry Pi através da VPN
ping 192.168.0.34

# Acessar outros dispositivos na rede local
ping 192.168.0.1  # Gateway local
```

## Passo 5: Configurar K3s para Usar Ollama

### 5.1. Criar Deployment de Teste

```yaml
# test-ollama.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-ollama
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command:
      - sleep
      - "3600"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ollama-config
data:
  OLLAMA_HOST: "http://172.16.1.x:11434"  # IP privado da instância OCI
```

### 5.2. Testar do Pod

```bash
kubectl apply -f test-ollama.yaml
kubectl exec -it test-ollama -- curl http://172.16.1.x:11434/api/version
```

## Configurações Adicionais

### NAT para Outros Dispositivos na LAN

Se você quiser que outros dispositivos na sua rede local acessem a OCI através da VPN:

```bash
# Na Raspberry Pi, configure NAT
sudo iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
sudo iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
sudo iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Salvar regras
sudo apt install iptables-persistent
sudo netfilter-persistent save
```

### Adicionar Rotas nos Outros Dispositivos

Em outros dispositivos da LAN que precisam acessar OCI:

```bash
# Adicionar rota usando a Raspberry Pi como gateway
ip route add 172.16.0.0/12 via 192.168.0.34

# Para tornar permanente, adicione ao script de inicialização de rede
```

## Troubleshooting

### VPN não conecta

```bash
# Verificar logs
sudo journalctl -u openvpn-client@k3s-cluster -f

# Verificar configuração
sudo openvpn --config /etc/openvpn/client/k3s-cluster.conf
```

### Não consigo fazer ping na rede OCI

```bash
# Verificar se o túnel está ativo
ip addr show tun0

# Verificar rotas
ip route | grep 172.16

# Verificar IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # Deve retornar 1

# Testar do servidor OCI
ssh opc@<PUBLIC_IP>
cat /var/log/openvpn/openvpn-status.log
```

### Ollama não responde

```bash
# Na instância OCI, verificar status
ssh opc@<PUBLIC_IP>
sudo systemctl status ollama
sudo journalctl -u ollama -f

# Verificar se está escutando
sudo netstat -tlnp | grep 11434

# Testar localmente na OCI
curl http://localhost:11434/api/version

# Verificar firewall
sudo firewall-cmd --list-all
```

## Modelos Recomendados para ARM (24GB RAM)

```bash
# SSH na instância OCI
ssh opc@<PUBLIC_IP>

# Modelos pequenos (para testes)
ollama pull llama3.2:1b        # 1.3GB - Rápido, bom para testes
ollama pull gemma2:2b          # 1.6GB - Eficiente
ollama pull phi3:mini          # 2.3GB - Boa qualidade

# Modelos médios (produção)
ollama pull llama3.2:3b        # 2GB - Balanceado
ollama pull mistral:7b         # 4GB - Alta qualidade
ollama pull llama3.1:8b        # 4.7GB - Muito bom

# Testar modelo
ollama run llama3.2:1b "Hello, how are you?"
```

## Próximos Passos

1. **Monitoramento**: Configure Prometheus/Grafana para monitorar uso de Ollama
2. **Load Balancer**: Se necessário, configure múltiplas instâncias
3. **Backup**: Configure backup automático dos modelos baixados
4. **Segurança**: Restrinja acesso ao Ollama apenas via VPN (remova regra 0.0.0.0/0)

## Referências

- [OpenVPN Site-to-Site](https://community.openvpn.net/openvpn/wiki/BridgingAndRouting)
- [K3s Documentation](https://docs.k3s.io/)
- [Ollama API Documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)