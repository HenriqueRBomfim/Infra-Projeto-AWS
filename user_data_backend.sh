#!/bin/bash
# Log de execução do user_data
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_backend.sh para API FastAPI com PostgreSQL RDS"

# Variáveis (serão injetadas pelo template_file do Terraform)
REPO_URL="${backend_repo_url}"
APP_PORT="${backend_app_port}"
AWS_REGION_FOR_CLI="${aws_region}"
DB_CREDENTIALS_SECRET_NAME="${db_credentials_secret_name_postgres}"
BACKEND_REPO_BRANCH="${backend_repo_branch}"

APP_DIR="/srv/backend-app"
VENV_DIR="$APP_DIR/venv"

echo ">>> Atualizando pacotes e instalando dependências base"
sudo apt update -y
# jq é útil para parsear o JSON do Secrets Manager
sudo apt install -y git python3 python3-pip python3-venv jq 

echo ">>> Clonando o repositório backend ($REPO_URL) da branch ($BACKEND_REPO_BRANCH)"
if [ -n "$BACKEND_REPO_BRANCH" ]; then
  sudo git clone --branch "$BACKEND_REPO_BRANCH" "$REPO_URL" "$APP_DIR"
else
  # Fallback para clonar a branch default se BACKEND_REPO_BRANCH não for fornecida
  echo "AVISO: Nome da branch não fornecido, clonando a branch padrão."
  sudo git clone "$REPO_URL" "$APP_DIR"
fi
# Verifica se o clone foi bem-sucedido
if [ ! -d "$APP_DIR/.git" ]; then
    echo "ERRO CRÍTICO: Falha ao clonar o repositório backend. Verifique URL e nome da branch."
    exit 1
fi
cd "$APP_DIR"

echo ">>> Configurando ambiente virtual Python"
sudo python3 -m venv "$VENV_DIR"

echo ">>> Instalando dependências Python (incluindo psycopg2-binary para PostgreSQL)"
sudo "$VENV_DIR/bin/pip" install --upgrade pip
# Certifique-se que 'psycopg2-binary' (ou 'psycopg2') está no seu requirements.txt
# ou instale aqui: sudo "$VENV_DIR/bin/pip" install psycopg2-binary
sudo "$VENV_DIR/bin/pip" install -r requirements.txt 
sudo "$VENV_DIR/bin/pip" install gunicorn uvicorn # Garante que estão no venv

echo ">>> Configurando variáveis de ambiente (DATABASE_URL, PORT) via Secrets Manager"
DB_ENV_FILE="$APP_DIR/.env" # Arquivo para armazenar as variáveis de ambiente

if [ -n "$DB_CREDENTIALS_SECRET_NAME" ]; then
  echo ">>> Buscando credenciais do BD do AWS Secrets Manager: $DB_CREDENTIALS_SECRET_NAME em $AWS_REGION_FOR_CLI"
  # O IAM Role da instância EC2 deve ter permissão para GetSecretValue neste segredo
  SECRET_JSON_STRING=$(aws secretsmanager get-secret-value --secret-id "$DB_CREDENTIALS_SECRET_NAME" --query SecretString --output text --region "$AWS_REGION_FOR_CLI")

  if [ $? -eq 0 ] && [ -n "$SECRET_JSON_STRING" ]; then
    echo "Segredo JSON obtido do Secrets Manager."
    DB_USER=$(echo "$SECRET_JSON_STRING" | jq -r .username)
    DB_PASSWORD=$(echo "$SECRET_JSON_STRING" | jq -r .password)
    DB_HOST=$(echo "$SECRET_JSON_STRING" | jq -r .host)
    DB_PORT=$(echo "$SECRET_JSON_STRING" | jq -r .port)
    DB_NAME=$(echo "$SECRET_JSON_STRING" | jq -r .dbname)
    # DB_ENGINE=$(echo "$SECRET_JSON_STRING" | jq -r .engine) # engine = "postgres"

    # Construir DATABASE_URL para PostgreSQL
    export DATABASE_URL="postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    # Nota: SQLAlchemy pode preferir 'postgresql+psycopg2://...' ou apenas 'postgresql://...'
    # Verifique a documentação da sua versão do SQLAlchemy ou o que funciona para sua app.
    # 'psycopg2' é o nome do driver.

    echo "DATABASE_URL configurada para PostgreSQL via Secrets Manager."
    echo "DATABASE_URL='$DATABASE_URL'" | sudo tee "$DB_ENV_FILE" > /dev/null
    echo "PORT='$APP_PORT'" | sudo tee -a "$DB_ENV_FILE" > /dev/null
    echo "Variáveis de ambiente salvas em $DB_ENV_FILE"
  else
    echo "ERRO CRÍTICO: Falha ao buscar credenciais do BD PostgreSQL do Secrets Manager. Verifique permissões IAM e nome do segredo."
    exit 1 # Sair se não conseguir as credenciais do BD
  fi
else
  echo "ERRO CRÍTICO: Nome do segredo do BD (DB_CREDENTIALS_SECRET_NAME) não fornecido para o script."
  exit 1
fi

echo ">>> Executando migrações do Alembic"
# Alembic usará a DATABASE_URL definida no ambiente (se seu env.py estiver configurado para isso)
# ou lida do .env se sua aplicação (e alembic/env.py) souber carregar de .env.
# Para garantir que as variáveis do .env estejam disponíveis para o comando alembic:
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
EnvironmentFile=$DB_ENV_FILE # Carrega DATABASE_URL e PORT do arquivo .env
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

echo ">>> Script user_data_backend.sh (PostgreSQL) concluído"