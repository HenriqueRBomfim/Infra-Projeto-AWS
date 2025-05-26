#!/bin/bash
# Log de execução do user_data
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_backend.sh para API FastAPI com PostgreSQL RDS e Deploy Key SSH"

# Variáveis injetadas pelo Terraform
REPO_URL_SSH="${TF_BACKEND_REPO_URL}"
APP_PORT="${TF_APP_PORT}"
AWS_REGION_FOR_CLI="${TF_AWS_REGION}"
DB_CREDENTIALS_SECRET_NAME="${TF_DB_CREDENTIALS_SECRET_NAME}"
BACKEND_REPO_BRANCH="${TF_BACKEND_REPO_BRANCH}"
GITHUB_SSH_KEY_SECRET_NAME="${TF_GITHUB_SSH_KEY_SECRET_NAME}"
WAZUH_SERVER_IP_FROM_TF="${WAZUH_SERVER_IP}"
ZABBIX_SERVER_IP_FROM_TF="${ZABBIX_SERVER_IP}"
INSTANCE_HOSTNAME_PREFIX_FROM_TF="${INSTANCE_HOSTNAME_PREFIX}"


APP_DIR="/srv/backend-app"
VENV_DIR="$APP_DIR/venv"
SSH_DIR="/root/.ssh"
PRIVATE_KEY_FILE="$SSH_DIR/id_rsa_github_deploy"
SSH_CONFIG_FILE="$SSH_DIR/config"

echo ">>> Atualizando pacotes e instalando dependências base"
sudo apt update -y
sudo apt install -y git python3 python3-pip python3-venv jq openssh-client

# ... (Seção de configuração da chave SSH e git clone como antes) ...
echo ">>> Configurando chave SSH para clone do GitHub via Deploy Key"
sudo mkdir -p "$SSH_DIR"
sudo chmod 700 "$SSH_DIR"

if [ -n "$GITHUB_SSH_KEY_SECRET_NAME" ]; then
  echo ">>> Buscando chave privada SSH do GitHub Deploy Key do Secrets Manager: $GITHUB_SSH_KEY_SECRET_NAME em $AWS_REGION_FOR_CLI"
  GITHUB_PRIVATE_KEY=$(aws secretsmanager get-secret-value --secret-id "$GITHUB_SSH_KEY_SECRET_NAME" --query SecretString --output text --region "$AWS_REGION_FOR_CLI")

  if [ $? -eq 0 ] && [ -n "$GITHUB_PRIVATE_KEY" ]; then
    echo "$GITHUB_PRIVATE_KEY" | sudo tee "$PRIVATE_KEY_FILE" > /dev/null
    sudo chmod 600 "$PRIVATE_KEY_FILE" 
    echo "Chave privada SSH salva em $PRIVATE_KEY_FILE"
    
    sudo tee "$SSH_CONFIG_FILE" > /dev/null <<EOL
Host github.com
  HostName github.com
  User git
  IdentityFile $PRIVATE_KEY_FILE
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOL
    sudo chmod 600 "$SSH_CONFIG_FILE"
    echo "Configuração SSH criada em $SSH_CONFIG_FILE"
  else
    echo "ERRO CRÍTICO: Falha ao buscar chave privada SSH do GitHub Deploy Key do Secrets Manager."
    exit 1
  fi
else
  echo "ERRO CRÍTICO: Nome do segredo da chave privada SSH do GitHub não fornecido para o script."
  exit 1
fi

echo ">>> Clonando o repositório backend ($REPO_URL_SSH) da branch ($BACKEND_REPO_BRANCH) usando SSH Deploy Key"
if [ -n "$BACKEND_REPO_BRANCH" ]; then
  sudo git clone --branch "$BACKEND_REPO_BRANCH" "$REPO_URL_SSH" "$APP_DIR"
else
  sudo git clone "$REPO_URL_SSH" "$APP_DIR"
fi

if [ ! -d "$APP_DIR/.git" ]; then
    echo "ERRO CRÍTICO: Falha ao clonar o repositório backend via SSH."
    exit 1
fi
cd "$APP_DIR"

# ... (Seção de configuração do venv, instalação de dependências Python como antes) ...
echo ">>> Configurando ambiente virtual Python"
sudo python3 -m venv "$VENV_DIR"

echo ">>> Instalando dependências Python"
sudo "$VENV_DIR/bin/pip" install --upgrade pip
sudo "$VENV_DIR/bin/pip" install -r requirements.txt 
sudo "$VENV_DIR/bin/pip" install gunicorn uvicorn

# ... (Seção de configuração do DB_ENV_FILE e DATABASE_URL como antes, usando $$ para variáveis de shell) ...
echo ">>> Configurando variáveis de ambiente (DATABASE_URL, PORT) via Secrets Manager"
DB_ENV_FILE="$APP_DIR/.env"

if [ -n "$DB_CREDENTIALS_SECRET_NAME" ]; then
  echo ">>> Buscando credenciais do BD do AWS Secrets Manager: $DB_CREDENTIALS_SECRET_NAME em $AWS_REGION_FOR_CLI"
  SECRET_JSON_STRING=$(aws secretsmanager get-secret-value --secret-id "$DB_CREDENTIALS_SECRET_NAME" --query SecretString --output text --region "$AWS_REGION_FOR_CLI")

  if [ $? -eq 0 ] && [ -n "$SECRET_JSON_STRING" ]; then
    echo "Segredo JSON obtido do Secrets Manager."
    DB_USER=$(echo "$SECRET_JSON_STRING" | jq -r .username)
    DB_PASSWORD=$(echo "$SECRET_JSON_STRING" | jq -r .password)
    DB_HOST=$(echo "$SECRET_JSON_STRING" | jq -r .host)
    DB_PORT_FROM_SECRET=$(echo "$SECRET_JSON_STRING" | jq -r .port) 
    DB_NAME=$(echo "$SECRET_JSON_STRING" | jq -r .dbname)

    DB_CONN_STRING_PREFIX="postgresql+psycopg2://"
    DB_CONN_STRING_USER_PASS="$${DB_USER}:$${DB_PASSWORD}" 
    DB_CONN_STRING_HOST_PORT_DB="@$${DB_HOST}:$${DB_PORT_FROM_SECRET}/$${DB_NAME}" 

    export DATABASE_URL="$${DB_CONN_STRING_PREFIX}$${DB_CONN_STRING_USER_PASS}$${DB_CONN_STRING_HOST_PORT_DB}" 

    echo "DATABASE_URL configurada para PostgreSQL via Secrets Manager."
    echo "DATABASE_URL='$${DATABASE_URL}'" | sudo tee "$DB_ENV_FILE" > /dev/null 
    echo "PORT='${APP_PORT}'" | sudo tee -a "$DB_ENV_FILE" > /dev/null
    echo "Variáveis de ambiente salvas em $DB_ENV_FILE"
  else
    echo "ERRO CRÍTICO: Falha ao buscar credenciais do BD PostgreSQL do Secrets Manager."
    exit 1
  fi
else
  echo "ERRO CRÍTICO: Nome do segredo do BD não fornecido para o script."
  exit 1
fi

# --- INÍCIO: Instalação do Agente Wazuh ---
if [ -n "$WAZUH_SERVER_IP_FROM_TF" ]; then
  echo ">>> Instalando e configurando Agente Wazuh para conectar em $WAZUH_SERVER_IP_FROM_TF"
  # Comandos para Ubuntu (VERIFIQUE A DOCUMENTAÇÃO OFICIAL DO WAZUH)
  curl -sO https://packages.wazuh.com/4.x/apt/wazuh-agent_4.7.4-1_amd64.deb # Substitua pela versão desejada
  sudo WAZUH_MANAGER="$WAZUH_SERVER_IP_FROM_TF" apt-get install -y ./wazuh-agent*.deb

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
  # Comandos para Ubuntu (VERIFIQUE A DOCUMENTAÇÃO OFICIAL DO ZABBIX)
  sudo wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-4%2Bubuntu22.04_all.deb
  sudo dpkg -i zabbix-release_6.0-4+ubuntu22.04_all.deb
  sudo apt update
  sudo apt install -y zabbix-agent

  ZABBIX_AGENT_CONF="/etc/zabbix/zabbix_agentd.conf"
  INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
  ZABBIX_HOSTNAME="${INSTANCE_HOSTNAME_PREFIX_FROM_TF}-${INSTANCE_ID}"

  sudo sed -i "s/^Server=127.0.0.1/Server=$ZABBIX_SERVER_IP_FROM_TF/" "$ZABBIX_AGENT_CONF"
  sudo sed -i "s/^ServerActive=127.0.0.1/ServerActive=$ZABBIX_SERVER_IP_FROM_TF/" "$ZABBIX_AGENT_CONF"
  sudo sed -i "s/^Hostname=Zabbix server/Hostname=$ZABBIX_HOSTNAME/" "$ZABBIX_AGENT_CONF"
  
  sudo systemctl restart zabbix-agent
  sudo systemctl enable zabbix-agent
  echo ">>> Configuração do Agente Zabbix concluída. Hostname: $ZABBIX_HOSTNAME"
else
  echo "AVISO: ZABBIX_SERVER_IP não fornecido. Agente Zabbix não será instalado/configurado."
fi
# --- FIM: Instalação do Agente Zabbix ---

# ... (Seção de Alembic e Systemd/Gunicorn como antes) ...
echo ">>> Executando migrações do Alembic"
if [ -f "$DB_ENV_FILE" ]; then
  export $(grep -v '^#' "$DB_ENV_FILE" | xargs -d '\n')
fi
sudo "$VENV_DIR/bin/alembic" -c "$APP_DIR/alembic.ini" upgrade head

echo ">>> Iniciando aplicação FastAPI com Gunicorn/Uvicorn na porta $APP_PORT" 
cd "$APP_DIR"

sudo tee /etc/systemd/system/backend-api.service > /dev/null <<EOL
[Unit]
Description=Gunicorn instance to serve FastAPI Backend API (PostgreSQL)
After=network.target

[Service]
User=ubuntu 
Group=www-data 
WorkingDirectory=$APP_DIR
EnvironmentFile=$DB_ENV_FILE 
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:\$PORT app.main:app 
Restart=always
StandardOutput=append:/var/log/backend-api-stdout.log
StandardError=append:/var/log/backend-api-stderr.log

[Install]
WantedBy=multi-user.target
EOL

echo ">>> Recarregando systemd, habilitando e iniciando o serviço backend-api"
sudo systemctl daemon-reload
sudo systemctl enable backend-api.service
sudo systemctl start backend-api.service

echo ">>> Script user_data_backend.sh (PostgreSQL com Deploy Key SSH) concluído"