#!/bin/bash
# Log de execução do user_data
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_frontend.sh para Next.js"

# Variáveis injetadas pelo Terraform
# NEXTJS_PORT será ${NEXTJS_PORT}
# frontend_repo_url será ${frontend_repo_url}

# Diretório base do clone e subpasta da aplicação
CLONE_DIR="/srv/frontend-app"
APP_SUBFOLDER="henriquerochabomfim" # <<<<<<< NOME DA SUA SUBPASTA
APP_PATH="$CLONE_DIR/$APP_SUBFOLDER"

echo ">>> Atualizando pacotes e instalando dependências base (git, curl, nginx)"
sudo apt update -y
sudo apt install -y git curl nginx

echo ">>> Instalando Node.js LTS (ex: Node 20.x)"
sudo apt-get remove nodejs npm -y
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"

echo ">>> Instalando pm2 (gerenciador de processos para Node.js)"
sudo npm install pm2 -g

echo ">>> Clonando o repositório frontend: ${frontend_repo_url} para $CLONE_DIR"
sudo git clone "${frontend_repo_url}" "$CLONE_DIR"
# Verifica se o clone foi bem-sucedido
if [ ! -d "$CLONE_DIR/.git" ]; then # Verifica o .git na pasta de clone
    echo "ERRO CRÍTICO: Falha ao clonar o repositório frontend. Verifique URL."
    exit 1
fi

# Verifica se a subpasta da aplicação existe
if [ ! -d "$APP_PATH" ]; then
    echo "ERRO CRÍTICO: Subpasta da aplicação '$APP_SUBFOLDER' não encontrada em '$CLONE_DIR'."
    exit 1
fi

echo ">>> Navegando para o diretório da aplicação: $APP_PATH"
cd "$APP_PATH" # <<<<<<< ENTRANDO NA SUBPASTA CORRETA

echo ">>> Instalando dependências do projeto Next.js"
sudo npm install

echo ">>> Fazendo o build de produção do Next.js"
sudo npm run build

echo ">>> Configurando Nginx como proxy reverso para a aplicação Next.js na porta ${NEXTJS_PORT}"
sudo tee /etc/nginx/sites-available/nextjs_frontend > /dev/null <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    location / {
        proxy_pass http://localhost:${NEXTJS_PORT};
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

echo ">>> Iniciando a aplicação Next.js com pm2 na porta ${NEXTJS_PORT}"
# Garante que o pm2 start é executado a partir do diretório correto da aplicação (onde está o package.json)
cd "$APP_PATH" # <<<<<<< GARANTINDO QUE ESTAMOS NO DIRETÓRIO CORRETO PARA PM2
sudo pm2 start npm --name "nextjs-frontend" -- run start -- -p ${NEXTJS_PORT}

echo ">>> Configurando pm2 para iniciar na inicialização do sistema"
sudo pm2 startup
sudo pm2 save

echo ">>> Script user_data_frontend.sh concluído"