#!/bin/bash
# user_data_wazuh_server.sh
exec > >(tee /tmp/user-data-wazuh.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_wazuh_server.sh para instalação do Wazuh Server (all-in-one) - Versão Atual"

echo ">>> Baixando o script de instalação do Wazuh (wazuh-install.sh)..."
curl -sO https://packages.wazuh.com/wazuh-install.sh # URL para a versão "current"

if [ -f ./wazuh-install.sh ]; then
  echo ">>> Script de instalação 'wazuh-install.sh' baixado com sucesso."
  echo ">>> Tornando o script executável..."
  sudo chmod +x ./wazuh-install.sh
  echo ">>> Executando o script de instalação do Wazuh (all-in-one)..."
  sudo bash ./wazuh-install.sh -a
  
  echo ">>> Instalação do Wazuh Server (all-in-one) iniciada/concluída pelo script."
  echo ">>> Verifique /tmp/user-data-wazuh.log e os logs específicos do Wazuh para detalhes e credenciais."
else
  echo "ERRO CRÍTICO: Falha ao baixar o script 'wazuh-install.sh'."
  exit 1
fi

echo ">>> Script user_data_wazuh_server.sh concluído."