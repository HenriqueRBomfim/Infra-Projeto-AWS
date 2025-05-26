#!/bin/bash
# Log de execução do user_data
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_frontend.sh para Next.js"

# Variáveis como frontend_repo_url e NEXTJS_PORT serão injetadas
# pelo template_file do Terraform diretamente onde ${frontend_repo_url} e ${NEXTJS_PORT}
# são usados no script.

# A linha 'NEXTJS_PORT=3000' foi REMOVIDA daqui.
# O valor para ${NEXTJS_PORT} virá do bloco 'vars' no main.tf.

echo ">>> Atualizando pacotes e instalando dependências base (git, curl, nginx)"
sudo apt update -y
sudo apt install -y git curl nginx

echo ">>> Instalando Node.js LTS (ex: Node 20.x)"
# Remove versões antigas se existirem para evitar conflitos
sudo apt-get remove nodejs npm -y
# Instala Node.js 20.x usando NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verificar versões
echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"

echo ">>> Instalando pm2 (gerenciador de processos para Node.js)"
sudo npm install pm2 -g

# Definir diretório da aplicação
APP_DIR="/srv/frontend-app"

echo ">>> Clonando o repositório frontend: ${frontend_repo_url}" # Esta variável é injetada pelo Terraform
sudo git clone "${frontend_repo_url}" "$APP_DIR"
cd "$APP_DIR"

echo ">>> Instalando dependências do projeto Next.js"
sudo npm install

echo ">>> Fazendo o build de produção do Next.js"
# Algumas aplicações Next.js podem precisar de variáveis de ambiente específicas durante o build.
# Se for o caso, exporte-as aqui antes do comando build.
# Ex: export NEXT_PUBLIC_API_URL="http://seu-backend-dns-ou-ip"
sudo npm run build

echo ">>> Configurando Nginx como proxy reverso para a aplicação Next.js na porta ${NEXTJS_PORT}" # Esta variável é injetada pelo Terraform
sudo tee /etc/nginx/sites-available/nextjs_frontend > /dev/null <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _; # Escuta em todos os hostnames

    location / {
        proxy_pass http://localhost:${NEXTJS_PORT}; # Encaminha para a aplicação Next.js, ${NEXTJS_PORT} será substituído pelo Terraform
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade; # \$http_upgrade é uma variável do Nginx, o $ precisa ser escapado para o 'tee'
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host; # \$host é uma variável do Nginx
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr; # \$remote_addr é uma variável do Nginx
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; # \$proxy_add_x_forwarded_for é do Nginx
        proxy_set_header X-Forwarded-Proto \$scheme; # \$scheme é uma variável do Nginx
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

echo ">>> Iniciando a aplicação Next.js com pm2 na porta ${NEXTJS_PORT}" # Esta variável é injetada pelo Terraform
cd "$APP_DIR"
# O comando 'npm run start' usa 'next start'. O argumento '-p' é passado para 'next start'.
sudo pm2 start npm --name "nextjs-frontend" -- run start -- -p ${NEXTJS_PORT}

echo ">>> Configurando pm2 para iniciar na inicialização do sistema"
sudo pm2 startup
sudo pm2 save

echo ">>> Script user_data_frontend.sh concluído"