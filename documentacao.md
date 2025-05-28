### Nome: Henrique Rocha Bomfim          TecHacker       7º Sem EngComp

# Documentação Completa do Projeto: Infraestrutura AWS com Terraform

## 1. Introdução e Objetivo do Projeto

Este documento detalha a concepção, implementação e configuração de uma infraestrutura robusta e segura na Amazon Web Services (AWS) utilizando Terraform. O objetivo principal é hospedar uma aplicação web moderna, composta por um frontend (Next.js) e um backend (API FastAPI com PostgreSQL), em múltiplos ambientes (ex: Desenvolvimento, Produção). A infraestrutura foi projetada com foco em segurança, alta disponibilidade, monitoramento e automação, incorporando ferramentas como Wazuh para detecção de intrusão (IDS/HIDS), um Application Load Balancer (ALB) para distribuição de tráfego e acesso via DNS, e um pipeline de CI/CD utilizando GitHub Actions para automação de deploy. Esta documentação serve como um registro completo do desenvolvimento e da arquitetura final implantada.

## 2. Configuração Inicial do Ambiente AWS e Desenvolvimento

### 2.1. Criação de Usuário IAM Admin e Configuração de Credenciais
Conforme as melhores práticas da AWS, um usuário IAM com permissões administrativas foi criado para gerenciar os recursos, evitando o uso da conta root. As credenciais de acesso programático (Access Key ID e Secret Access Key) deste usuário foram configuradas localmente utilizando o AWS Command Line Interface (AWS CLI) com `aws configure`, estabelecendo o perfil `default` que o Terraform utiliza para autenticação.

### 2.2. Instalação do Terraform
O Terraform foi instalado no ambiente de desenvolvimento local para permitir a definição e o provisionamento da infraestrutura como código. O PATH do sistema foi configurado para incluir o executável do Terraform.

## 3. Estrutura do Projeto Terraform (`INFRA-PROJETO-AWS`)

O projeto Terraform foi organizado de forma modular para promover a reutilização e a clareza, e preparado para gerenciar múltiplos ambientes.

### 3.1. Visão Geral da Estrutura de Arquivos

INFRA-PROJETO-AWS/
├── modules/
│   ├── ec2/                   # Módulo para instâncias EC2
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── security/              # Módulo para Security Groups
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   └── vpc/                   # Módulo para VPC e componentes de rede
│       ├── main.tf
│       ├── outputs.tf
│       └── variables.tf
├── main.tf                    # Configuração principal do módulo raiz (orquestração)
├── variables.tf               # Declaração de variáveis de entrada globais do projeto
├── terraform.tfvars           # Valores padrão ou para o workspace 'default'
├── dev.tfvars                 # Valores específicos para o ambiente de Desenvolvimento
├── prod.tfvars                # Valores específicos para o ambiente de Produção (exemplo)
├── outputs.tf                 # Saídas globais do projeto (ex: DNS do ALB, IPs)
├── provider.tf                # Configuração do provedor AWS
├── database_app.tf            # Configuração do RDS para a aplicação e Secrets Manager
├── load_balancer.tf           # Configuração do Application Load Balancer
├── user_data_frontend.sh      # Script de inicialização para instâncias frontend
├── user_data_backend.sh       # Script de inicialização para instâncias backend
└── user_data_wazuh_server.sh # Script de inicialização para o servidor Wazuh


### 4. Componentes da Infraestrutura e Decisões de Design

#### 4.1. Rede (VPC - Virtual Private Cloud)
* **Definição:** Uma VPC customizada (`10.0.0.0/16`) foi criada para isolar os recursos da aplicação.
* **Subnets:**
    * **Públicas:** Duas subnets públicas distribuídas em diferentes Zonas de Disponibilidade (AZs, ex: `us-east-2a`, `us-east-2b`) para alta disponibilidade. Hospedam recursos que precisam de acesso direto à internet, como o Application Load Balancer, e opcionalmente os servidores Wazuh e Zabbix (para acesso aos dashboards, com Security Groups restritos).
    * **Privadas:** Duas subnets privadas, também em AZs distintas, para recursos que não devem ser diretamente acessíveis pela internet, como as instâncias EC2 do backend e os bancos de dados RDS.
* **Conectividade:**
    * **Internet Gateway (IGW):** Anexado à VPC para permitir comunicação entre recursos nas subnets públicas e a internet.
    * **NAT Gateway:** Um NAT Gateway (com um Elastic IP associado) foi provisionado em uma das subnets públicas para permitir que instâncias nas subnets privadas iniciem conexões de saída para a internet (ex: para atualizações de pacotes, download de dependências, ou acesso a APIs externas), sem permitir conexões de entrada da internet.
    * **Tabelas de Rotas:** Configurações específicas para subnets públicas (rota padrão para o IGW) e privadas (rota padrão para o NAT Gateway).

#### 4.2. Segurança
* **Security Groups (SGs):**
    * **ALB SG:** Permite tráfego de entrada da internet nas portas 80 (HTTP) e 443 (HTTPS). Permite tráfego de saída para o `Frontend SG` na porta da aplicação (ex: 80).
    * **Frontend SG:** Permite tráfego de entrada na porta da aplicação (ex: 80, onde o Nginx escuta) **somente** a partir do `ALB SG`.
    * **Backend SG:** Permite tráfego de entrada na porta da API backend (ex: 8000) **somente** a partir do `Frontend SG`.
    * **RDS App SG:** Permite tráfego de entrada na porta do PostgreSQL (5432) **somente** a partir do `Backend SG`.
    * **Wazuh Server SG:** Permite tráfego de entrada na porta 443 (HTTPS para o dashboard) de um IP específico (`my_home_ip_cidr`), e nas portas 1514/TCP (registro) e 1515/TCP (eventos) a partir dos SGs do frontend e backend.
    * **Zabbix Server SG:** Permite tráfego de entrada na porta 80/443 (Web UI) de `my_home_ip_cidr`, e na porta 10051/TCP (agentes passivos) a partir dos SGs das instâncias monitoradas.
    * **RDS Zabbix SG:** Permite tráfego de entrada na porta do banco de dados (ex: 5432 para PostgreSQL) **somente** a partir do `Zabbix Server SG`.
    * **Acesso SSH:** As regras de SSH (porta 22) foram removidas de todos os SGs das instâncias EC2 em favor do uso exclusivo do **AWS Systems Manager Session Manager** para acesso seguro.
* **IAM (Identity and Access Management):**
    * Uma IAM Role (`ec2_role`) foi criada para todas as instâncias EC2.
    * Políticas anexadas: `AmazonSSMManagedInstanceCore` (para Session Manager), permissões para ler segredos específicos do AWS Secrets Manager (credenciais dos bancos de dados da aplicação e Zabbix, chave SSH do GitHub para deploy do backend).
    * Um IAM Instance Profile (`ec2_profile`) associa a role às instâncias.
* **AWS Secrets Manager:**
    * Credenciais dos bancos de dados RDS (aplicação e Zabbix) são geradas aleatoriamente (senha) e armazenadas de forma segura.
    * A chave SSH privada (Deploy Key) para clonar o repositório backend privado também é armazenada aqui.
    * As instâncias EC2 (backend, Zabbix server) usam sua IAM Role para buscar essas credenciais em tempo de execução.

#### 4.3. Cômputo (EC2 - Elastic Compute Cloud)
* **Instância Frontend:**
    * Tipo: `t2.micro` (ou `t3.micro`), AMI Ubuntu.
    * Localização: Subnet pública.
    * Configuração: Via `user_data_frontend.sh` (Node.js, Next.js, PM2, Nginx, agente Wazuh, agente Zabbix).
    * Acessada via Application Load Balancer.
* **Instância Backend:**
    * Tipo: `t2.micro` (ou `t3.micro`), AMI Ubuntu.
    * Localização: Subnet privada.
    * Configuração: Via `user_data_backend.sh` (Python, FastAPI, Gunicorn, Alembic, agente Wazuh, agente Zabbix), com acesso seguro ao repositório GitHub via Deploy Key SSH.
* **Instância Wazuh Server:**
    * Tipo: `t3.medium` (ou superior), AMI Ubuntu.
    * Localização: Subnet pública (para acesso ao dashboard, com SG restrito).
    * Configuração: Via `user_data_wazuh_server.sh` (instalação "all-in-one" do Wazuh, agente Zabbix).
* **Instância Zabbix Server:**
    * Tipo: `t3.medium` (ou superior), AMI Ubuntu.
    * Localização: Subnet pública (para acesso ao UI, com SG restrito).
    * Configuração: Via `user_data_zabbix_server.sh` (instalação do Zabbix server, frontend, agente Zabbix local, configuração para usar o RDS Zabbix).

#### 4.4. Bancos de Dados (RDS - Relational Database Service)
* **RDS para Aplicação:**
    * Motor: PostgreSQL (ex: versão `16.x`).
    * Classe: `db.t3.micro`.
    * Localização: Subnets privadas, usando um `aws_db_subnet_group`.
    * Segurança: Protegido pelo `RDS App SG`, não publicamente acessível, armazenamento criptografado.
* **RDS para Zabbix:**
    * Motor: PostgreSQL (ou MySQL, ex: versão `16.x` para PostgreSQL).
    * Classe: `db.t3.micro` (ou superior).
    * Localização: Subnets privadas, usando um `aws_db_subnet_group`.
    * Segurança: Protegido pelo `RDS Zabbix SG`, não publicamente acessível, armazenamento criptografado.

#### 4.5. Balanceamento de Carga (Application Load Balancer - ALB)
* Um ALB público foi configurado para o frontend.
* **Listeners:** HTTP na porta 80 (com potencial redirecionamento para HTTPS se configurado). HTTPS na porta 443 (se um certificado ACM for provisionado).
* **Target Group:** Aponta para as instâncias do frontend (Nginx na porta 80 ou diretamente para a aplicação Next.js).
* **Health Checks:** Configurados para monitorar a saúde das instâncias frontend.
* **DNS:** O acesso ao frontend é feito através do nome DNS estável fornecido pelo ALB.

#### 4.6. Monitoramento de Segurança e Detecção de Intrusão (Wazuh - IDS/HIDS)
* **Wazuh Server:** Uma instância EC2 dedicada (`dev-wazuh-server`) hospeda a instalação "all-in-one" do Wazuh (Manager, Indexer, Dashboard).
* **Agentes Wazuh:** Instalados e configurados em todas as instâncias EC2 (frontend, backend, Zabbix server e no próprio Wazuh server) através de seus scripts `user_data`. Os agentes reportam ao IP privado do servidor Wazuh.
* **Funcionalidade:** Coleta de logs, detecção de anomalias, verificação de integridade de arquivos, avaliação de vulnerabilidades e resposta a incidentes.

#### 4.7. Monitoramento de Performance e Disponibilidade (Zabbix)
* **Zabbix Server:** Uma instância EC2 dedicada (`dev-zabbix-server`) hospeda o Zabbix server e o frontend web.
* **Banco de Dados Zabbix:** Utiliza uma instância RDS PostgreSQL dedicada.
* **Agentes Zabbix:** Instalados e configurados em todas as instâncias EC2 (frontend, backend, Wazuh server e no próprio Zabbix server) através de seus scripts `user_data`. Os agentes reportam ao IP privado do servidor Zabbix.
* **Funcionalidade:** Coleta de métricas de sistema (CPU, memória, disco, rede), monitoramento de serviços, disponibilidade de aplicações, e alertas.

## 7. Scripts de User Data

Scripts de inicialização (`user_data`) automatizam a configuração das instâncias EC2:
* **`user_data_frontend.sh`**: Instala Node.js, Git, Nginx. Clona o repositório frontend, instala dependências, builda o Next.js, configura Nginx como proxy reverso, inicia a aplicação com `pm2`. Instala e configura os agentes Wazuh e Zabbix.
* **`user_data_backend.sh`**: Instala Python, Git, jq, openssh-client. Configura chave SSH para clonar o repositório backend privado. Cria ambiente virtual, instala dependências (FastAPI, Gunicorn, etc.). Busca credenciais do BD da aplicação do Secrets Manager. Executa migrações Alembic. Inicia a API com `systemd` e Gunicorn. Instala e configura os agentes Wazuh e Zabbix.
* **`user_data_wazuh_server.sh`**: Baixa e executa o script de instalação "all-in-one" do Wazuh. Instala e configura o agente Zabbix.
* **`user_data_zabbix_server.sh`**: Instala o Zabbix server, frontend e agente. Configura a conexão com o banco de dados RDS Zabbix (buscando credenciais do Secrets Manager) e importa o schema inicial. Configura o servidor web para o frontend Zabbix. Instala e configura o agente Wazuh.

## 8. Versionamento e Modularização

* **Modularização**: O código Terraform foi dividido em módulos locais (VPC, Security, EC2) para organização e reutilização.
* **Versionamento**: O projeto de infraestrutura é gerenciado usando Git, com branches para desenvolvimento de features. O Terraform especifica as versões requeridas dos provedores. A branch `aws-deploy` no repositório da API backend contém configurações específicas para a AWS.

## 9. CI/CD (Integração e Entrega/Deploy Contínuos)

Para automatizar o processo de build, testes e deploy da infraestrutura, um pipeline de CI/CD será implementado utilizando **GitHub Actions**.

### 9.1. Fluxo do Pipeline Proposto
1.  **Trigger:** O pipeline é acionado por um push para a branch `main` (para deploy em dev/staging) ou por um merge para uma branch de produção (ex: `release`), ou na criação/atualização de Pull Requests para a branch `main`.
2.  **Fase de Integração Contínua (CI) - Em Pull Requests e Pushes para `main`:**
    * **Checkout do Código:** Obtém a última versão do código do repositório.
    * **Setup do Terraform:** Instala a versão especificada do Terraform.
    * **Formatação (`terraform fmt -check`):** Verifica se o código está formatado corretamente.
    * **Linting (`tflint`):** Analisa o código em busca de erros, melhores práticas e possíveis problemas.
    * **Validação (`terraform validate`):** Garante que a sintaxe da configuração é válida.
    * **Análise Estática de Segurança (`tfsec` ou `Checkov`):** Escaneia o código em busca de más configurações de segurança.
    * **Geração do Plano (`terraform plan`):**
        * Para Pull Requests: Gera um plano e posta um resumo como comentário no PR para revisão.
        * Para pushes para `main`: Gera um plano e o armazena como um artefato.
    * **(Opcional) Estimativa de Custo (`Infracost`):** Mostra o impacto financeiro das mudanças.
3.  **Fase de Deploy Contínuo (CD) - Somente para a branch `main` (ou `release`):**
    * **Aprovação Manual (para Produção):** Para deploys em ambientes de produção, uma etapa de aprovação manual é crucial após a revisão do plano. Para ambientes de desenvolvimento/staging, o apply pode ser automático se o plano for bem-sucedido.
    * **Download do Plano (se armazenado):** Obtém o arquivo de plano gerado na fase de CI.
    * **Aplicação (`terraform apply "plan.tfplan"`):** Aplica as mudanças de infraestrutura na AWS.
    * **(Opcional) Testes de Integração/Smoke Tests:** Após o `apply`, executa testes básicos para verificar se os principais componentes da infraestrutura e da aplicação estão funcionando.

### 9.2. Configuração do GitHub Actions
* Um arquivo de workflow YAML (ex: `.github/workflows/terraform.yml`) será criado no repositório de infraestrutura.
* Este workflow definirá os jobs e steps para cada fase (CI e CD).
* Credenciais da AWS serão armazenadas de forma segura como "Secrets" no GitHub e usadas pelo workflow para autenticar com a AWS.

## 10. Conclusão e Próximos Passos Pós-Deploy

Após a execução bem-sucedida do `terraform apply` para toda a infraestrutura descrita:
* Verificar a funcionalidade completa do frontend (acessado via DNS do ALB) e do backend.
* Confirmar a conectividade com os bancos de dados RDS.
* Acessar os dashboards do Wazuh e Zabbix, verificar se os servidores estão operacionais e se todos os agentes (frontend, backend, Wazuh server, Zabbix server) estão reportando corretamente.
* Realizar testes de segurança e monitoramento para validar a eficácia das ferramentas implementadas.
* Continuar o desenvolvimento do pipeline de CI/CD.

Esta infraestrutura estabelece uma base sólida, segura e monitorada para a aplicação web, utilizando práticas modernas de IaC e DevOps.
