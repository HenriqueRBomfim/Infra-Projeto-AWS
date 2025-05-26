#!/bin/bash
# Log de execução do user_data
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_backend.sh para API FastAPI com PostgreSQL RDS e Deploy Key SSH"

# Variáveis injetadas pelo Terraform (usar ${...} aqui)
REPO_URL_SSH="${backend_repo_url}" # Deve ser a URL SSH do repositório
APP_PORT_FROM_TF="${backend_app_port}" # Renomeado para clareza, valor vindo do Terraform
AWS_REGION_FOR_CLI="${aws_region}"
DB_CREDENTIALS_SECRET_NAME="${db_credentials_secret_name_postgres}"
BACKEND_REPO_BRANCH="${backend_repo_branch}"
GITHUB_SSH_KEY_SECRET_NAME="${github_ssh_key_secret_name}"

APP_DIR="/srv/backend-app"
VENV_DIR="$APP_DIR/venv"
# O script user_data roda como root, então o diretório .ssh do root é /root/.ssh
SSH_DIR="/root/.ssh"
PRIVATE_KEY_FILE="$SSH_DIR/id_rsa_github_deploy" # Nome do arquivo para a chave privada
SSH_CONFIG_FILE="$SSH_DIR/config"
KNOWN_HOSTS_FILE="$SSH_DIR/known_hosts" # Opcional se StrictHostKeyChecking=accept-new

echo ">>> Atualizando pacotes e instalando dependências base"
sudo apt update -y
# jq é útil para parsear o JSON do Secrets Manager, openssh-client para SSH/git
sudo apt install -y git python3 python3-pip python3-venv jq openssh-client

echo ">>> Configurando chave SSH para clone do GitHub via Deploy Key"
sudo mkdir -p "$SSH_DIR"
sudo chmod 700 "$SSH_DIR"

if [ -n "$GITHUB_SSH_KEY_SECRET_NAME" ]; then
  echo ">>> Buscando chave privada SSH do GitHub Deploy Key do Secrets Manager: $GITHUB_SSH_KEY_SECRET_NAME em $AWS_REGION_FOR_CLI"
  GITHUB_PRIVATE_KEY=$(aws secretsmanager get-secret-value --secret-id "$GITHUB_SSH_KEY_SECRET_NAME" --query SecretString --output text --region "$AWS_REGION_FOR_CLI")

  if [ $? -eq 0 ] && [ -n "$GITHUB_PRIVATE_KEY" ]; then
    echo "$GITHUB_PRIVATE_KEY" | sudo tee "$PRIVATE_KEY_FILE" > /dev/null
    sudo chmod 600 "$PRIVATE_KEY_FILE" # Permissões restritas para a chave privada
    echo "Chave privada SSH salva em $PRIVATE_KEY_FILE"

    # Configurar SSH para usar esta chave para github.com
    sudo tee "$SSH_CONFIG_FILE" > /dev/null <<EOL
Host github.com
  HostName github.com
  User git
  IdentityFile $PRIVATE_KEY_FILE
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new # Aceita a chave do host na primeira conexão e adiciona ao known_hosts
EOL
    sudo chmod 600 "$SSH_CONFIG_FILE"
    echo "Configuração SSH criada em $SSH_CONFIG_FILE"
  else
    echo "ERRO CRÍTICO: Falha ao buscar chave privada SSH do GitHub Deploy Key do Secrets Manager. Verifique permissões IAM e nome do segredo."
    exit 1
  fi
else
  echo "ERRO CRÍTICO: Nome do segredo da chave privada SSH do GitHub (GITHUB_SSH_KEY_SECRET_NAME) não fornecido para o script."
  exit 1
fi

echo ">>> Clonando o repositório backend ($REPO_URL_SSH) da branch ($BACKEND_REPO_BRANCH) usando SSH Deploy Key"
if [ -n "$BACKEND_REPO_BRANCH" ]; then
  sudo git clone --branch "$BACKEND_REPO_BRANCH" "$REPO_URL_SSH" "$APP_DIR"
else
  echo "AVISO: Nome da branch não fornecido, clonando a branch padrão."
  sudo git clone "$REPO_URL_SSH" "$APP_DIR"
fi

# Verifica se o clone foi bem-sucedido
if [ ! -d "$APP_DIR/.git" ]; then
    echo "ERRO CRÍTICO: Falha ao clonar o repositório backend via SSH. Verifique URL SSH, branch, Deploy Key e configuração SSH."
    exit 1
fi
cd "$APP_DIR"

echo ">>> Configurando ambiente virtual Python"
sudo python3 -m venv "$VENV_DIR"

echo ">>> Instalando dependências Python (incluindo psycopg2-binary para PostgreSQL)"
sudo "$VENV_DIR/bin/pip" install --upgrade pip
sudo "$VENV_DIR/bin/pip" install -r requirements.txt 
sudo "$VENV_DIR/bin/pip" install gunicorn uvicorn # Garante que estão no venv

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
    DB_PORT_FROM_SECRET=$(echo "$SECRET_JSON_STRING" | jq -r .port) # Renomeado para evitar conflito com APP_PORT_FROM_TF se usasse o mesmo nome
    DB_NAME=$(echo "$SECRET_JSON_STRING" | jq -r .dbname)

    DB_CONN_STRING_PREFIX="postgresql+psycopg2://"
    DB_CONN_STRING_USER_PASS="$${DB_USER}:$${DB_PASSWORD}" # Escapado com $$
    DB_CONN_STRING_HOST_PORT_DB="@$${DB_HOST}:$${DB_PORT_FROM_SECRET}/$${DB_NAME}" # Escapado com $$

    export DATABASE_URL="$${DB_CONN_STRING_PREFIX}$${DB_CONN_STRING_USER_PASS}$${DB_CONN_STRING_HOST_PORT_DB}" # Escapado com $$

    echo "DATABASE_URL configurada para PostgreSQL via Secrets Manager."
    echo "DATABASE_URL='$${DATABASE_URL}'" | sudo tee "$DB_ENV_FILE" > /dev/null # Escapado com $$
    echo "PORT='${APP_PORT_FROM_TF}'" | sudo tee -a "$DB_ENV_FILE" > /dev/null # APP_PORT_FROM_TF é do Terraform, NÃO escapar
    echo "Variáveis de ambiente salvas em $DB_ENV_FILE"
  else
    echo "ERRO CRÍTICO: Falha ao buscar credenciais do BD PostgreSQL do Secrets Manager. Verifique permissões IAM e nome do segredo."
    exit 1
  fi
else
  echo "ERRO CRÍTICO: Nome do segredo do BD (DB_CREDENTIALS_SECRET_NAME) não fornecido para o script."
  exit 1
fi

echo ">>> Executando migrações do Alembic"
if [ -f "$DB_ENV_FILE" ]; then
  export $(grep -v '^#' "$DB_ENV_FILE" | xargs -d '\n')
fi
sudo "$VENV_DIR/bin/alembic" -c "$APP_DIR/alembic.ini" upgrade head


echo ">>> Iniciando aplicação FastAPI com Gunicorn/Uvicorn na porta ${APP_PORT_FROM_TF}" # Usando a variável injetada pelo TF
cd "$APP_DIR"

sudo tee /etc/systemd/system/backend-api.service > /dev/null <<EOL
[Unit]
Description=Gunicorn instance to serve FastAPI Backend API (PostgreSQL)
After=network.target

[Service]
User=ubuntu 
Group=www-data 
WorkingDirectory=$APP_DIR
EnvironmentFile=$DB_ENV_FILE # Carrega DATABASE_URL e PORT do arquivo .env
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:\$PORT app.main:app # \$PORT será lido do .env pelo systemd
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