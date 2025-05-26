#!/bin/bash
# Log de execução do user_data
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_frontend.sh para Next.js"

# Variáveis injetadas pelo Terraform
NEXTJS_PORT_FROM_TF="${NEXTJS_PORT}" # Nome da chave no vars do template_file
FRONTEND_REPO_URL="${frontend_repo_url}"
AWS_REGION_FOR_CLI="${aws_region}" # Se necessário para algo no frontend user_data
WAZUH_SERVER_IP_FROM_TF="${WAZUH_SERVER_IP}"
ZABBIX_SERVER_IP_FROM_TF="${ZABBIX_SERVER_IP}"
INSTANCE_HOSTNAME_PREFIX_FROM_TF="${INSTANCE_HOSTNAME_PREFIX}"

# Diretório base do clone e subpasta da aplicação
CLONE_DIR="/srv/frontend-app"
APP_SUBFOLDER="henriquerochabomfim"
APP_PATH="$CLONE_DIR/$APP_SUBFOLDER"

echo ">>> Atualizando pacotes e instalando dependências base (git, curl, nginx)"
sudo apt update -y
sudo apt install -y git curl nginx jq # Adicionado jq caso precise para algo

echo ">>> Instalando Node.js LTS (ex: Node 20.x)"
sudo apt-get remove nodejs npm -y
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"

echo ">>> Instalando pm2 (gerenciador de processos para Node.js)"
sudo npm install pm2 -g

echo ">>> Clonando o repositório frontend: $FRONTEND_REPO_URL para $CLONE_DIR"
sudo git clone "$FRONTEND_REPO_URL" "$CLONE_DIR"
if [ ! -d "$CLONE_DIR/.git" ]; then
    echo "ERRO CRÍTICO: Falha ao clonar o repositório frontend. Verifique URL."
    exit 1
fi
if [ ! -d "$APP_PATH" ]; then
    echo "ERRO CRÍTICO: Subpasta da aplicação '$APP_SUBFOLDER' não encontrada em '$CLONE_DIR'."
    exit 1
fi
echo ">>> Navegando para o diretório da aplicação: $APP_PATH"
cd "$APP_PATH"

echo ">>> Instalando dependências do projeto Next.js (a partir de $APP_PATH)"
sudo npm install

echo ">>> Fazendo o build de produção do Next.js (a partir de $APP_PATH)"
sudo npm run build

# --- INÍCIO: Instalação do Agente Wazuh ---
if [ -n "$WAZUH_SERVER_IP_FROM_TF" ]; then
  echo ">>> Instalando e configurando Agente Wazuh para conectar em $WAZUH_SERVER_IP_FROM_TF"
  # Comandos para Ubuntu (VERIFIQUE A DOCUMENTAÇÃO OFICIAL DO WAZUH PARA OS COMANDOS MAIS RECENTES E CORRETOS)
  curl -sO https://packages.wazuh.com/4.x/apt/wazuh-agent_4.7.4-1_amd64.deb # Substitua 4.x e 4.7.4-1 pela versão desejada
  sudo WAZUH_MANAGER="$WAZUH_SERVER_IP_FROM_TF" apt-get install -y ./wazuh-agent*.deb # Tenta instalar usando variável de ambiente

  # Alternativamente, ou se o acima não funcionar, edite o ossec.conf:
  # sudo sed -i "s/<address>MANAGER_IP<\/address>/<address>$WAZUH_SERVER_IP_FROM_TF<\/address>/" /var/ossec/etc/ossec.conf
  
  sudo systemctl daemon-reload
  sudo systemctl enable wazuh-agent
  sudo systemctl start wazuh-agent
  echo ">>> Configuração do Agente Wazuh concluída."
else
  echo "AVISO: WAZUH_SERVER_IP não fornecido. Agente Wazuh não será instalado/configurado."
fi
# --- FIM: Instalação do Agente Wazuh ---

# --- INÍCIO: Instalação do Agente Zabbix ---
if [ -n "$ZABBIX_SERVER_IP_FROM_TF" ]; then
  echo ">>> Instalando e configurando Agente Zabbix para conectar em $ZABBIX_SERVER_IP_FROM_TF"
  # Comandos para Ubuntu (VERIFIQUE A DOCUMENTAÇÃO OFICIAL DO ZABBIX PARA OS COMANDOS MAIS RECENTES E CORRETOS PARA SUA VERSÃO)
  # Exemplo para Zabbix 6.0 LTS (pode variar)
  sudo wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-4%2Bubuntu22.04_all.deb
  sudo dpkg -i zabbix-release_6.0-4+ubuntu22.04_all.deb
  sudo apt update
  sudo apt install -y zabbix-agent # Ou zabbix-agent2 se preferir

  # Configurar o agente Zabbix
  ZABBIX_AGENT_CONF="/etc/zabbix/zabbix_agentd.conf"
  INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  ZABBIX_HOSTNAME="${INSTANCE_HOSTNAME_PREFIX_FROM_TF}-${INSTANCE_ID}"

  sudo sed -i "s/^Server=127.0.0.1/Server=$ZABBIX_SERVER_IP_FROM_TF/" "$ZABBIX_AGENT_CONF"
  sudo sed -i "s/^ServerActive=127.0.0.1/ServerActive=$ZABBIX_SERVER_IP_FROM_TF/" "$ZABBIX_AGENT_CONF" # Se usar checks ativos
  sudo sed -i "s/^Hostname=Zabbix server/Hostname=$ZABBIX_HOSTNAME/" "$ZABBIX_AGENT_CONF"
  
  sudo systemctl restart zabbix-agent
  sudo systemctl enable zabbix-agent
  echo ">>> Configuração do Agente Zabbix concluída. Hostname: $ZABBIX_HOSTNAME"
else
  echo "AVISO: ZABBIX_SERVER_IP não fornecido. Agente Zabbix não será instalado/configurado."
fi
# --- FIM: Instalação do Agente Zabbix ---

echo ">>> Configurando Nginx como proxy reverso para a aplicação Next.js na porta ${NEXTJS_PORT_FROM_TF}"
# ... (resto da configuração do Nginx e PM2 como antes) ...
# Lembre-se de usar ${NEXTJS_PORT_FROM_TF} onde a porta é referenciada.

sudo tee /etc/nginx/sites-available/nextjs_frontend > /dev/null <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    location / {
        proxy_pass http://localhost:${NEXTJS_PORT_FROM_TF}; # Usando a variável do TF
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

echo ">>> Habilitando a configuração do Nginx para o frontend"
sudo ln -sf /etc/nginx/sites-available/nextjs_frontend /etc/nginx/sites-enabled/
if [ -f /etc/nginx/sites-enabled/default ]; then
    sudo rm /etc/nginx/sites-enabled/default
fi

echo ">>> Testando configuração do Nginx e reiniciando o Nginx"
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo ">>> Iniciando a aplicação Next.js com pm2 na porta ${NEXTJS_PORT_FROM_TF}"
cd "$APP_PATH" 
sudo pm2 start npm --name "nextjs-frontend" --cwd "$APP_PATH" -- run start -- -p ${NEXTJS_PORT_FROM_TF}

echo ">>> Configurando pm2 para iniciar na inicialização do sistema"
sudo pm2 startup
sudo pm2 save

echo ">>> Script user_data_frontend.sh concluído"