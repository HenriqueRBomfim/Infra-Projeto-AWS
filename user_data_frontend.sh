#!/bin/bash
# Log de execução do user_data
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_frontend.sh para Next.js"

# Variáveis (frontend_repo_url será injetada pelo template_file do Terraform)
# NEXTJS_PORT é a porta em que sua aplicação Next.js (npm run start) vai escutar internamente.
# Nginx escutará na porta 80 e fará proxy para esta porta.
NEXTJS_PORT=3000

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

echo ">>> Clonando o repositório frontend: ${frontend_repo_url}"
sudo git clone "${frontend_repo_url}" "$APP_DIR"
cd "$APP_DIR"

echo ">>> Instalando dependências do projeto Next.js"
# Pode ser necessário executar como o usuário que tem permissão de escrita no diretório, ou usar sudo
sudo npm install

echo ">>> Fazendo o build de produção do Next.js"
# Algumas aplicações Next.js podem precisar de variáveis de ambiente específicas durante o build.
# Se for o caso, exporte-as aqui antes do comando build.
# Ex: export NEXT_PUBLIC_API_URL="http://seu-backend-dns-ou-ip"
sudo npm run build

echo ">>> Configurando Nginx como proxy reverso para a aplicação Next.js na porta $NEXTJS_PORT"
sudo tee /etc/nginx/sites-available/nextjs_frontend > /dev/null <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _; # Escuta em todos os hostnames

    location / {
        proxy_pass http://localhost:${NEXTJS_PORT}; # Encaminha para a aplicação Next.js
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
# Remove a configuração padrão do Nginx se ela existir e puder causar conflito
if [ -f /etc/nginx/sites-enabled/default ]; then
    sudo rm /etc/nginx/sites-enabled/default
fi

echo ">>> Testando configuração do Nginx e reiniciando o Nginx"
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

echo ">>> Iniciando a aplicação Next.js com pm2 na porta $NEXTJS_PORT"
# Navega para o diretório da aplicação para que o 'npm start' funcione corretamente
cd "$APP_DIR"
# O comando 'npm run start' (ou 'next start') é geralmente usado para produção após o build.
# O -p $NEXTJS_PORT pode ser necessário se o seu 'start' script não usar a porta 3000 por padrão ou se você quiser sobrescrevê-la.
# Verifique o package.json -> scripts -> start.
# Se o seu script de start já define a porta ou usa a variável de ambiente PORT, você pode ajustar.
sudo pm2 start npm --name "nextjs-frontend" -- run start -- -p $NEXTJS_PORT
# Nota: 'npm run start -- -p $NEXTJS_PORT' passa o argumento '-p $NEXTJS_PORT' para o comando 'next start'.

echo ">>> Configurando pm2 para iniciar na inicialização do sistema"
# O comando abaixo pode gerar um comando para você executar. Em ambientes automatizados,
# pode ser necessário capturar esse comando e executá-lo.
# A opção --hp /home/ubuntu (ou o home do usuário que vai rodar) pode ser necessária em algumas AMIs.
# Vamos tentar de forma genérica primeiro.
# sudo pm2 startup systemd -u ubuntu --hp /home/ubuntu # Exemplo para usuário ubuntu
# Se o comando acima não for totalmente automático, ele imprimirá um comando para ser executado com sudo.
# Para um ambiente totalmente automatizado, você pode precisar de uma abordagem mais robusta para o 'pm2 startup'.
# Uma forma mais simples para muitos casos é apenas 'pm2 startup' e 'pm2 save'.
sudo pm2 startup
sudo pm2 save # Salva a lista de processos atual para ser restaurada na inicialização

echo ">>> Script user_data_frontend.sh concluído"