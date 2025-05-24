#!/bin/bash
# Log de execução do user_data
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_backend.sh para API FastAPI"

# Variáveis (serão injetadas pelo template_file do Terraform)
REPO_URL="${backend_repo_url}"
APP_PORT="${backend_app_port}" # Porta em que o Gunicorn/Uvicorn vai escutar
AWS_REGION_FOR_CLI="${aws_region}" # Região para AWS CLI, se usada para Secrets Manager
# DB_CONNECTION_SECRET_NAME="${db_connection_secret_name}" # Descomente se for buscar do Secrets Manager

APP_DIR="/srv/backend-app"
VENV_DIR="$APP_DIR/venv"

echo ">>> Atualizando pacotes e instalando dependências base"
sudo apt update -y
sudo apt install -y git python3 python3-pip python3-venv # Nginx não é estritamente necessário para o backend API se Gunicorn escutar em 0.0.0.0

echo ">>> Clonando o repositório backend"
sudo git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

echo ">>> Configurando ambiente virtual Python"
sudo python3 -m venv "$VENV_DIR"
# source "$VENV_DIR/bin/activate" # Ativa o venv para este script - cuidado com sudo depois disso

echo ">>> Instalando dependências Python"
sudo "$VENV_DIR/bin/pip" install --upgrade pip
sudo "$VENV_DIR/bin/pip" install -r requirements.txt # Garanta que uvicorn e gunicorn estejam no requirements.txt
                                                 # ou instale-os explicitamente aqui:
                                                 # sudo "$VENV_DIR/bin/pip" install uvicorn gunicorn

# --- Configuração do Banco de Dados (USAR AWS SECRETS MANAGER) ---
echo ">>> Configurando variáveis de ambiente (ex: DATABASE_URL, PORT)"
# Crie um arquivo .env ou exporte as variáveis diretamente.
# É AQUI QUE VOCÊ DEVE BUSCAR O SEGREDO DO BANCO DE DADOS DO AWS SECRETS MANAGER
# E EXPORTAR COMO DATABASE_URL.
#
# Exemplo de como buscar e exportar (requer IAM role com permissão e aws_cli instalado):
#
# if [ -n "$DB_CONNECTION_SECRET_NAME" ]; then
#   echo ">>> Buscando DATABASE_URL do AWS Secrets Manager: $DB_CONNECTION_SECRET_NAME em $AWS_REGION_FOR_CLI"
#   DB_SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$DB_CONNECTION_SECRET_NAME" --query SecretString --output text --region "$AWS_REGION_FOR_CLI")
#   if [ $? -eq 0 ] && [ -n "$DB_SECRET_VALUE" ]; then
#     # Se o segredo for um JSON contendo a URL (ex: {"DATABASE_URL":"..."}), você precisará parsear com jq
#     # Se o segredo FOR a própria string da URL, então:
#     export DATABASE_URL="$DB_SECRET_VALUE"
#     echo "DATABASE_URL configurada via Secrets Manager."
#     # Pode ser necessário escrever para um arquivo .env que será lido pelo Gunicorn/Systemd
#     echo "DATABASE_URL='$DATABASE_URL'" | sudo tee "$APP_DIR/.env" > /dev/null
#     echo "PORT='$APP_PORT'" | sudo tee -a "$APP_DIR/.env" > /dev/null
#   else
#     echo "ERRO: Falha ao buscar DATABASE_URL do Secrets Manager."
#     # Decida se quer sair com erro ou continuar com uma config padrão (não recomendado para DB)
#   fi
# else
#   echo "AVISO: DB_CONNECTION_SECRET_NAME não fornecido. DATABASE_URL não será configurada via Secrets Manager."
#   echo "PORT='$APP_PORT'" | sudo tee "$APP_DIR/.env" > /dev/null # Ainda configura a porta
# fi
#
# A aplicação FastAPI deve ser configurada para ler DATABASE_URL do ambiente ou de um arquivo .env
# Verifique seu config.py ou similar.

# Temporário para teste (SUBSTITUA PELA LÓGICA DO SECRETS MANAGER):
echo "DATABASE_URL='sqlite:///./test.db'" | sudo tee "$APP_DIR/.env" > /dev/null # Exemplo com SQLite, apenas para estrutura. REMOVA E USE SECRETS MANAGER.
echo "PORT='$APP_PORT'" | sudo tee -a "$APP_DIR/.env" > /dev/null


echo ">>> Executando migrações do Alembic"
# O Alembic precisa que as variáveis de ambiente (como DATABASE_URL) estejam setadas
# ou que seu env.py do alembic consiga carregar a configuração da aplicação.
# Se você exportou DATABASE_URL, o alembic deve pegá-la.
# Se você escreveu em .env, o Gunicorn/Systemd pode carregar, mas o alembic aqui pode não ver.
# Uma forma é carregar o .env antes de rodar o alembic se necessário:
# if [ -f "$APP_DIR/.env" ]; then
#  export $(echo $(cat "$APP_DIR/.env" | sed 's/#.*//g'| xargs) | envsubst)
# fi
sudo "$VENV_DIR/bin/alembic" -c "$APP_DIR/alembic.ini" upgrade head


echo ">>> Iniciando aplicação FastAPI com Gunicorn/Uvicorn na porta $APP_PORT"
# Comando para Gunicorn com Uvicorn workers.
# Ajuste o número de workers (-w) conforme necessário.
# O módulo é app.main e o objeto da aplicação é app (app.main:app)
cd "$APP_DIR" # Garante que está no diretório raiz do projeto da API

# Criar um arquivo de serviço systemd é a melhor abordagem para produção:
sudo tee /etc/systemd/system/backend-api.service > /dev/null <<EOL
[Unit]
Description=Gunicorn instance to serve FastAPI Backend API
After=network.target

[Service]
User=ubuntu # Ou o usuário apropriado que tem acesso ao venv e código
Group=www-data # Opcional, ou o mesmo grupo do usuário
WorkingDirectory=$APP_DIR
# Se você estiver usando um arquivo .env para carregar variáveis de ambiente:
EnvironmentFile=$APP_DIR/.env
# Se não, as variáveis de ambiente precisam ser setadas de outra forma (ex: via próprio systemd Environment=)
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
# Para verificar o status: sudo systemctl status backend-api.service
# Logs também em /var/log/backend-api-stdout.log e /var/log/backend-api-stderr.log

echo ">>> Script user_data_backend.sh concluído"