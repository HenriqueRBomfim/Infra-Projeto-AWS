#!/bin/bash
# Log de execução do user_data
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_frontend.sh para Next.js com Agente Wazuh"
set -x # Habilita o debug, mostrando cada comando que é executado

# Variáveis injetadas pelo Terraform
NEXTJS_PORT="${NEXTJS_PORT}"
FRONTEND_REPO_URL="${frontend_repo_url}"
WAZUH_SERVER_IP="${WAZUH_SERVER_IP}"

CLONE_DIR="/srv/frontend-app"
APP_SUBFOLDER="henriquerochabomfim"
APP_PATH="$CLONE_DIR/$APP_SUBFOLDER"

echo ">>> Configurando variáveis de ambiente para Git (tentativa de mitigar problemas não interativos)"
export GIT_TERMINAL_PROMPT=0 # Desabilita prompts interativos do Git

echo ">>> Verificando conectividade com github.com"
ping -c 4 github.com
echo "Status do ping: $?"
curl -Is https://github.com | head -n 1
echo "Status do curl: $?"

echo ">>> Atualizando pacotes e instalando dependências base (git, curl, nginx)"
apt-get update -y
apt-get install -y git curl nginx jq

echo ">>> Instalando Node.js LTS (ex: Node 20.x)"
apt-get remove -y nodejs npm
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"

echo ">>> Instalando pm2 (gerenciador de processos para Node.js)"
npm install pm2 -g

echo ">>> Verificando se /srv existe e permissões"
ls -ld /srv

echo ">>> Tentando criar o diretório de clone $CLONE_DIR manualmente"
mkdir -p "$CLONE_DIR"
if [ $? -ne 0 ]; then
    echo "ERRO: Falha ao criar $CLONE_DIR manualmente."
    # Decida se quer sair ou continuar
fi
ls -ld "$CLONE_DIR" # Verifica se foi criado e quais são as permissões

echo ">>> Clonando o repositório frontend: $FRONTEND_REPO_URL para $CLONE_DIR"
# Tentar o clone com output detalhado do git
GIT_TRACE=1 GIT_TRACE_PACKET=1 GIT_TRACE_PERFORMANCE=1 GIT_TRACE_SETUP=1 git clone "$FRONTEND_REPO_URL" "$CLONE_DIR"
CLONE_EXIT_CODE=$?
echo ">>> Código de saída do git clone: $CLONE_EXIT_CODE"

if [ $CLONE_EXIT_CODE -ne 0 ]; then
    echo "ERRO CRÍTICO: git clone FALHOU com código de saída $CLONE_EXIT_CODE."
    # Tentar listar o conteúdo de $CLONE_DIR mesmo se o clone falhou, para ver se algo foi criado
    ls -la "$CLONE_DIR"
    exit 1
fi

if [ ! -d "$CLONE_DIR/.git" ]; then
    echo "ERRO CRÍTICO: Falha ao clonar o repositório frontend (diretório .git não encontrado em $CLONE_DIR)."
    ls -la "$CLONE_DIR" # Lista o conteúdo para depuração
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERRO CRÍTICO: Subpasta da aplicação '$APP_SUBFOLDER' não encontrada em '$CLONE_DIR'."
    ls -la "$CLONE_DIR" # Lista o conteúdo para depuração
    exit 1
fi

echo ">>> Navegando para o diretório da aplicação: $APP_PATH"
cd "$APP_PATH"

echo ">>> Listando conteúdo de $APP_PATH:"
ls -la

echo ">>> Verificando a existência do package.json em $(pwd)"
if [ ! -f "./package.json" ]; then
    echo "ERRO CRÍTICO: package.json não encontrado em $(pwd)"
    exit 1
fi

echo ">>> Instalando dependências do projeto Next.js (a partir de $APP_PATH)"
npm install
if [ $? -ne 0 ]; then echo "ERRO: npm install falhou"; exit 1; fi

echo ">>> Fazendo o build de produção do Next.js (a partir de $APP_PATH)"
npm run build
if [ $? -ne 0 ]; then echo "ERRO: npm run build falhou"; exit 1; fi

# --- INÍCIO: Instalação do Agente Wazuh ---
# (Seu código do agente Wazuh aqui, usando $WAZUH_SERVER_IP)
if [ -n "$WAZUH_SERVER_IP" ]; then
  echo ">>> Instalando e configurando Agente Wazuh para conectar em $WAZUH_SERVER_IP"
  curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add -
  echo "deb https://packages.wazuh.com/4.x/apt/ stable main" | tee /etc/apt/sources.list.d/wazuh.list
  apt-get update
  WAZUH_MANAGER="$WAZUH_SERVER_IP" apt-get install -y wazuh-agent
  systemctl daemon-reload
  systemctl enable wazuh-agent
  systemctl start wazuh-agent
  echo ">>> Configuração do Agente Wazuh concluída."
else
  echo "AVISO: WAZUH_SERVER_IP não fornecido. Agente Wazuh não será instalado/configurado."
fi
# --- FIM: Instalação do Agente Wazuh ---

echo ">>> Configurando Nginx como proxy reverso para a aplicação Next.js na porta ${NEXTJS_PORT}"
tee /etc/nginx/sites-available/nextjs_frontend > /dev/null <<EOL
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
ln -sf /etc/nginx/sites-available/nextjs_frontend /etc/nginx/sites-enabled/
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
fi

echo ">>> Testando configuração do Nginx e reiniciando o Nginx"
nginx -t
systemctl restart nginx
systemctl enable nginx

echo ">>> Iniciando a aplicação Next.js com pm2 na porta ${NEXTJS_PORT}"
cd "$APP_PATH"
pm2 start npm --name "nextjs-frontend" --cwd "$APP_PATH" -- run start -- -p ${NEXTJS_PORT}
if [ $? -ne 0 ]; then echo "ERRO: pm2 start falhou"; exit 1; fi

echo ">>> Configurando pm2 para iniciar na inicialização do sistema"
pm2 startup systemd -u root --hp /root # Configura para o usuário root
pm2 save

echo ">>> Script user_data_frontend.sh concluído"