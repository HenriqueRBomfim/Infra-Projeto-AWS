#!/bin/bash
# user_data_wazuh_server.sh
exec > >(tee /var/log/user-data-wazuh.log|logger -t user-data -s 2>/dev/console) 2>&1

echo ">>> Iniciando user_data_wazuh_server.sh para instalação do Wazuh Server (all-in-one) - Versão Atual"

# Comandos baseados no guia de instalação oficial do Wazuh (Quickstart/Installation Assistant)
# Fonte: https://documentation.wazuh.com/current/quickstart.html
# Que geralmente leva a: https://documentation.wazuh.com/current/installation-guide/wazuh-server/installation-assistant.html

echo ">>> Baixando o script de instalação do Wazuh (wazuh-install.sh)..."
# Este é o comando padrão do guia de instalação para baixar o script da versão atual
curl -sO https://packages.wazuh.com/wazuh-install.sh

# Verifica se o download foi bem-sucedido
if [ -f ./wazuh-install.sh ]; then
  echo ">>> Script de instalação 'wazuh-install.sh' baixado com sucesso."
  echo ">>> Executando o script de instalação do Wazuh (all-in-one)..."
  # O parâmetro '-a' ou '--all-in-one' é usado para a instalação completa em um único nó.
  # O script pode gerar senhas e informações importantes, que serão logadas em /var/log/user-data-wazuh.log
  # e também geralmente são exibidas pelo próprio script de instalação do Wazuh.
  sudo bash ./wazuh-install.sh -a  # O '-a' executa a instalação all-in-one
  
  echo ">>> Instalação do Wazuh Server (all-in-one) iniciada/concluída pelo script."
  echo ">>> Verifique /var/log/user-data-wazuh.log e os logs específicos do Wazuh para detalhes e credenciais."
  # O script de instalação do Wazuh pode levar um tempo considerável.
  # Ele geralmente exibe as credenciais de administrador no final de sua execução.
else
  echo "ERRO CRÍTICO: Falha ao baixar o script 'wazuh-install.sh' de packages.wazuh.com."
  echo "Verifique a URL e a conectividade da instância."
  exit 1
fi

# O script wazuh-install.sh -a geralmente cuida de iniciar e habilitar os serviços.
# Se necessário, você pode adicionar comandos para garantir que os serviços estejam ativos:
# echo ">>> Verificando status dos serviços Wazuh (exemplo)..."
# sudo systemctl status wazuh-indexer
# sudo systemctl status wazuh-manager
# sudo systemctl status wazuh-dashboard

echo ">>> Script user_data_wazuh_server.sh concluído."