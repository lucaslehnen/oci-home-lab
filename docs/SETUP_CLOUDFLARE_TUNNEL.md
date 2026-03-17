# Configuração do Cloudflare Tunnel (Zero Trust)

Este guia detalha como configurar o Cloudflare Tunnel para conectar seu cluster K3s aos serviços no OCI (Ollama, Docker, etc.) usando Zero Trust Network Access (ZTNA).

## Visão Geral da Arquitetura

```
K3s Pods → DNS → Cloudflare Edge → Cloudflare Tunnel (OCI) → Ollama/Docker
            ↓
    Zero Trust Policies
    (autenticação/autorização)
```

**Vantagens sobre OpenVPN:**
- ✅ Sem portas abertas na instância OCI
- ✅ Zero Trust nativo (autenticação por serviço)
- ✅ Sem certificados VPN para gerenciar
- ✅ Melhor integração com K3s (acesso via DNS)
- ✅ Logs e monitoramento via dashboard Cloudflare
- ✅ Gratuito (plano Free: até 50 usuários)

## Pré-requisitos

- Conta Cloudflare (gratuita)
- Domínio configurado no Cloudflare
- Instância OCI provisionada via Terraform
- Cluster K3s local (Raspberry Pi)

## Parte 1: Configurar Tunnel no OCI

### 1.1. Conectar à Instância OCI

```bash
ssh opc@<PUBLIC_IP>
```

### 1.2. Verificar Instalação do cloudflared

```bash
cloudflared --version
```

O cloudflared foi instalado automaticamente via cloud-init.

### 1.3. Autenticar com Cloudflare

```bash
cloudflared tunnel login
```

Esse comando:
1. Abrirá uma URL no terminal
2. Acesse a URL em um navegador
3. Faça login na Cloudflare
4. Autorize o cloudflared
5. Um certificado será salvo em `~/.cloudflared/cert.pem`

### 1.4. Criar o Tunnel

```bash
cloudflared tunnel create oci-tunnel
```

Output esperado:
```
Tunnel credentials written to /root/.cloudflared/<TUNNEL_ID>.json
Created tunnel oci-tunnel with id <TUNNEL_ID>
```

**Importante:** Anote o `TUNNEL_ID`.

### 1.5. Configurar o Tunnel

Copie o arquivo de exemplo:

```bash
cp /root/cloudflared-config-example.yml ~/.cloudflared/config.yml
```

Edite o arquivo:

```bash
vim ~/.cloudflared/config.yml
```

Configure com seus valores:

```yaml
tunnel: <TUNNEL_ID>  # Substitua pelo seu tunnel ID
credentials-file: /root/.cloudflared/<TUNNEL_ID>.json

ingress:
  # Ollama API
  - hostname: ollama.seudominio.com
    service: http://localhost:11434

  # SSH (opcional, para acesso emergencial)
  - hostname: ssh.seudominio.com
    service: ssh://localhost:22

  # Serviços Docker (adicione conforme necessário)
  # - hostname: app.seudominio.com
  #   service: http://localhost:8080

  # Regra catch-all (obrigatória)
  - service: http_status:404
```

### 1.6. Configurar DNS

Para cada hostname configurado, crie um registro DNS:

```bash
cloudflared tunnel route dns oci-tunnel ollama.seudominio.com
cloudflared tunnel route dns oci-tunnel ssh.seudominio.com
```

Isso cria automaticamente registros CNAME no Cloudflare apontando para o tunnel.

### 1.7. Testar o Tunnel

Execute manualmente:

```bash
cloudflared tunnel run oci-tunnel
```

Verifique os logs. Deve aparecer:
```
INF Connection registered connIndex=0
INF Connection registered connIndex=1
```

Teste o acesso (de outro terminal/máquina):

```bash
curl https://ollama.seudominio.com/api/version
```

### 1.8. Instalar como Serviço Systemd

Se o teste funcionou, instale como serviço:

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
sudo systemctl status cloudflared
```

O tunnel agora inicia automaticamente no boot.

## Parte 2: Configurar Zero Trust (Opcional mas Recomendado)

### 2.1. Acessar Dashboard Zero Trust

1. Acesse https://one.dash.cloudflare.com/
2. Vá em **Access** → **Applications**
3. Clique em **Add an application**

### 2.2. Criar Aplicação para Ollama

**Configuração:**
- **Application type:** Self-hosted
- **Application name:** Ollama API
- **Session Duration:** 24 hours (ou o que preferir)
- **Application domain:** `ollama.seudominio.com`

**Policy:**
- **Policy name:** Allow K3s Access
- **Action:** Allow
- **Configure rules:**
  - **Include:** Emails ending in: `@seudominio.com` (ou IPs, grupos, etc.)

Ou, para ambiente homelab sem autenticação extra:
- **Include:** Everyone

Salve a aplicação.

### 2.3. Configurar Service Auth Token (para K3s)

Para permitir que pods K3s acessem sem autenticação interativa:

1. Vá em **Access** → **Service Auth** → **Create Service Token**
2. Nome: `k3s-cluster`
3. Copie o **Client ID** e **Client Secret**
4. Em **Access** → **Applications** → **Ollama API**:
   - Adicione nova regra: **Service Auth** → `k3s-cluster`

## Parte 3: Configurar K3s para Acessar o Tunnel

### 3.1. Criar Secret com Service Token

No seu cluster K3s:

```bash
kubectl create secret generic cloudflare-service-token \
  --from-literal=CF_CLIENT_ID='<CLIENT_ID>' \
  --from-literal=CF_CLIENT_SECRET='<CLIENT_SECRET>' \
  -n default
```

### 3.2. Exemplo de Pod Acessando Ollama

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ollama-test
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["sleep", "3600"]
    env:
    - name: CF_CLIENT_ID
      valueFrom:
        secretKeyRef:
          name: cloudflare-service-token
          key: CF_CLIENT_ID
    - name: CF_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: cloudflare-service-token
          key: CF_CLIENT_SECRET
```

Teste dentro do pod:

```bash
kubectl exec -it ollama-test -- sh

# Requisição com Service Token
curl -H "CF-Access-Client-Id: $CF_CLIENT_ID" \
     -H "CF-Access-Client-Secret: $CF_CLIENT_SECRET" \
     https://ollama.seudominio.com/api/version
```

### 3.3. Configurar Aplicação para Usar Ollama

Exemplo de Deployment usando Ollama:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llm-app
  template:
    metadata:
      labels:
        app: llm-app
    spec:
      containers:
      - name: app
        image: seu-app:latest
        env:
        - name: OLLAMA_API_URL
          value: "https://ollama.seudominio.com"
        - name: CF_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: cloudflare-service-token
              key: CF_CLIENT_ID
        - name: CF_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: cloudflare-service-token
              key: CF_CLIENT_SECRET
```

Sua aplicação deve incluir os headers `CF-Access-Client-Id` e `CF-Access-Client-Secret` nas requisições.

## Parte 4: Verificação e Troubleshooting

### 4.1. Verificar Status do Tunnel

**No OCI:**

```bash
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f
```

**No Dashboard Cloudflare:**

1. Acesse https://one.dash.cloudflare.com/
2. Vá em **Networks** → **Tunnels**
3. Verifique status "Healthy" e conexões ativas

### 4.2. Testar Conectividade

**Sem autenticação (se configurado como "Everyone"):**

```bash
curl https://ollama.seudominio.com/api/version
```

**Com Service Token:**

```bash
curl -H "CF-Access-Client-Id: <CLIENT_ID>" \
     -H "CF-Access-Client-Secret: <CLIENT_SECRET>" \
     https://ollama.seudominio.com/api/version
```

### 4.3. Problemas Comuns

**Tunnel não conecta:**
- Verifique se o tunnel ID e credentials file estão corretos no config.yml
- Confira se o cloudflared está rodando: `systemctl status cloudflared`
- Veja logs: `journalctl -u cloudflared -n 50`

**DNS não resolve:**
- Aguarde 1-2 minutos para propagação DNS
- Confirme que o CNAME foi criado: `dig ollama.seudominio.com`
- Verifique no Cloudflare DNS: https://dash.cloudflare.com/

**403 Forbidden (com Zero Trust):**
- Confirme que as políticas de acesso estão corretas
- Verifique se os Service Tokens estão ativos
- Teste sem autenticação primeiro para isolar o problema

**Ollama não responde:**
- Verifique se Ollama está rodando: `systemctl status ollama`
- Teste localmente: `curl http://localhost:11434/api/version`
- Confira se a porta está correta no config.yml

## Parte 5: Monitoramento e Logs

### 5.1. Dashboard Cloudflare

**Tráfego e Analytics:**
- **Access** → **Logs** → Veja todas as requisições autenticadas
- **Networks** → **Tunnels** → Métricas de conexão

### 5.2. Logs no OCI

```bash
# Logs do cloudflared
sudo journalctl -u cloudflared -f

# Logs do Ollama
sudo journalctl -u ollama -f

# Status dos serviços
sudo systemctl status cloudflared ollama docker
```

### 5.3. Monitoramento no K3s

```bash
# Logs de pods que acessam Ollama
kubectl logs -f deployment/llm-app

# Verificar conectividade
kubectl run test --rm -it --image=curlimages/curl -- \
  curl -H "CF-Access-Client-Id: $CF_CLIENT_ID" \
       -H "CF-Access-Client-Secret: $CF_CLIENT_SECRET" \
       https://ollama.seudominio.com/api/version
```

## Comparação: Cloudflare Tunnel vs OpenVPN

| Aspecto | Cloudflare Tunnel | OpenVPN |
|---------|-------------------|---------|
| **Configuração** | Simples (5 comandos) | Complexa (certificados, rotas) |
| **Segurança** | Zero Trust nativo | Necessita configuração manual |
| **Portas abertas** | Nenhuma | 1194 (UDP/TCP) |
| **Gerenciamento** | Dashboard web | Linha de comando |
| **K3s Integration** | DNS direto | Requer rotas e IP forwarding |
| **Custo** | Gratuito (Free tier) | Gratuito (self-hosted) |
| **Latência** | +20-50ms (via edge) | Menor (direto) |
| **Privacidade** | Tráfego via Cloudflare | 100% privado |
| **Escalabilidade** | Alta (edge global) | Limitada (sua infra) |

## Próximos Passos

- [ ] Adicionar mais serviços Docker ao tunnel
- [ ] Configurar políticas Zero Trust mais granulares
- [ ] Monitorar métricas e logs no dashboard
- [ ] Configurar alertas para tunnel offline
- [ ] Testar failover e redundância

## Recursos Adicionais

- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Zero Trust Dashboard](https://one.dash.cloudflare.com/)
- [Service Tokens Guide](https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/)