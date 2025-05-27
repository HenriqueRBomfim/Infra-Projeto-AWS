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


### 3.2. Módulo Raiz
Localizado na pasta `INFRA-PROJETO-AWS/`, o módulo raiz contém:
* `main.tf`: Define os recursos globais (como a configuração IAM para EC2, o perfil da instância, os data sources para os scripts de user data, e os recursos para o servidor Wazuh) e chama os módulos locais (VPC, Security, EC2).
* `variables.tf`: Declara todas as variáveis de entrada do projeto (ex: região, CIDRs, URLs de repositórios, configurações de banco de dados, tipos de instância).
* `terraform.tfvars` e arquivos específicos por ambiente (ex: `dev.tfvars`, `prod.tfvars`): Fornecem os valores para as variáveis de entrada, permitindo customização por ambiente.
* `outputs.tf`: Define quais informações serão exibidas após a aplicação do Terraform (ex: IP público do frontend, endpoint do RDS, DNS do ALB).
* `provider.tf`: Configura o provedor AWS, especificando a região e o perfil de credenciais.
* `database_app.tf`: Define os recursos para o banco de dados RDS PostgreSQL da aplicação e o armazenamento seguro de suas credenciais no AWS Secrets Manager.
* `load_balancer.tf`: Define os recursos para o Application Load Balancer do frontend.

### 3.3. Módulos Locais
* **Módulo VPC (`modules/vpc/`)**: Responsável pela criação da Virtual Private Cloud (VPC), subnets públicas e privadas em múltiplas Zonas de Disponibilidade, Internet Gateway (IGW), NAT Gateway (com Elastic IP) e as tabelas de rotas associadas.
* **Módulo Security (`modules/security/`)**: Gerencia os Security Groups. Cria grupos para o ALB, frontend, backend, banco de dados RDS e para o servidor Wazuh, com regras específicas para cada um.
* **Módulo EC2 (`modules/ec2/`)**: Define um módulo genérico para criar instâncias EC2, chamado múltiplas vezes para as instâncias do frontend, backend e servidor Wazuh.

## 4. Componentes da Infraestrutura e Decisões de Design

#### 4.1. Rede (VPC - Virtual Private Cloud)
* **Definição:** Uma VPC customizada (ex: `10.0.0.0/16`) é criada para cada ambiente (dev, prod) para isolar os recursos.
* **Subnets:**
    * **Públicas:** Múltiplas subnets públicas distribuídas em diferentes AZs para alta disponibilidade, hospedando o ALB e o servidor Wazuh (com acesso restrito).
    * **Privadas:** Múltiplas subnets privadas em AZs distintas para as instâncias EC2 do backend e o banco de dados RDS.
* **Conectividade:** IGW para subnets públicas e NAT Gateway para acesso de saída das subnets privadas. Tabelas de rotas específicas.

#### 4.2. Segurança
* **Security Groups (SGs):**
    * **ALB SG:** Permite tráfego HTTP/S da internet.
    * **Frontend SG:** Permite tráfego na porta da aplicação (ex: 80) somente do `ALB SG`.
    * **Backend SG:** Permite tráfego na porta da API (ex: 8000) somente do `Frontend SG`.
    * **RDS App SG:** Permite tráfego na porta do PostgreSQL (5432) somente do `Backend SG`.
    * **Wazuh Server SG:** Permite tráfego HTTPS (443) para o dashboard de IPs específicos (`my_home_ip_cidr`) e tráfego dos agentes (1514/1515) dos SGs do frontend e backend.
    * **Acesso SSH:** O acesso via porta 22 é desabilitado em favor do AWS Systems Manager Session Manager.
* **IAM (Identity and Access Management):**
    * Uma IAM Role (`ec2_role`) é criada para as instâncias EC2 com políticas para Session Manager, leitura de segredos do Secrets Manager (credenciais do BD, chave SSH do GitHub). Um IAM Instance Profile (`ec2_profile`) associa a role às instâncias.
* **AWS Secrets Manager:**
    * Credenciais do banco de dados RDS da aplicação e a chave SSH privada para deploy do backend são armazenadas de forma segura.

#### 4.3. Cômputo (EC2 - Elastic Compute Cloud)
* **Instância Frontend:** Em subnet pública, associada ao `frontend_sg`, executa Next.js via `user_data_frontend.sh`. Acessada via ALB.
* **Instância Backend:** Em subnet privada, associada ao `backend_sg`, executa API FastAPI via `user_data_backend.sh` com acesso seguro ao GitHub.
* **Instância Wazuh Server:** Em subnet pública (dashboard com SG restrito), executa Wazuh "all-in-one" via `user_data_wazuh_server.sh`.

#### 4.4. Banco de Dados (RDS PostgreSQL)
* Uma instância RDS PostgreSQL (ex: `db.t3.micro`) para a aplicação.
* Localizada em subnets privadas, protegida por SG, não publicamente acessível, armazenamento criptografado.

#### 4.5. Balanceamento de Carga (Application Load Balancer - ALB)
* Um ALB público para o frontend, com listeners HTTP (e opcionalmente HTTPS).
* Target Group apontando para as instâncias do frontend, com health checks.
* Acesso via nome DNS estável do ALB.

#### 4.6. Monitoramento de Segurança e Detecção de Intrusão (Wazuh - IDS/HIDS)
* **Wazuh Server:** Instância EC2 dedicada para a instalação "all-in-one".
* **Agentes Wazuh:** Instalados nas instâncias frontend e backend, reportando ao servidor Wazuh.
* **Funcionalidade:** Coleta de logs, detecção de anomalias, verificação de integridade, etc.

## 5. Scripts de User Data

Scripts de inicialização (`user_data`) automatizam a configuração das instâncias:
* **`user_data_frontend.sh`**: Instala Node.js, Git, Nginx. Clona o repositório frontend, instala dependências, builda o Next.js, configura Nginx como proxy reverso, inicia a aplicação com `pm2`, e instala/configura o agente Wazuh.
* **`user_data_backend.sh`**: Instala Python, Git, etc. Configura chave SSH para clonar o repositório backend privado (branch `aws-deploy`). Cria ambiente virtual, instala dependências. Busca credenciais do BD do Secrets Manager. Executa migrações Alembic. Inicia a API com `systemd` e Gunicorn. Instala e configura o agente Wazuh.
* **`user_data_wazuh_server.sh`**: Baixa e executa o script de instalação "all-in-one" do Wazuh.

## 6. Versionamento e Modularização

* **Modularização**: Código Terraform dividido em módulos locais (VPC, Security, EC2) para organização e reutilização.
* **Versionamento**: Projeto gerenciado usando Git. Branch `aws-deploy` na API para configurações AWS. Terraform especifica versões de provedores.

## 7. CI/CD (Integração e Entrega/Deploy Contínuos) com GitHub Actions

Para automatizar o ciclo de vida da infraestrutura, um pipeline de CI/CD é configurado utilizando GitHub Actions.
### 7.1. Workflow
* **Trigger:** Em push para branches principais (ex: `main` para dev, `production` para prod) ou em Pull Requests.
* **Jobs:**
    1.  **Validate & Plan (CI):**
        * `terraform init`
        * `terraform fmt -check`
        * `terraform validate`
        * `tflint` (linting adicional)
        * `tfsec` / `checkov` (análise de segurança)
        * `terraform plan -var-file="<ambiente>.tfvars" -out=tfplan` (plano específico do ambiente)
        * O plano é armazenado como artefato e/ou postado em PRs.
    2.  **Apply (CD):**
        * Disparado manualmente (para prod) ou automaticamente (para dev) após CI bem-sucedido.
        * `terraform apply tfplan`

### 7.2. Configuração
* Arquivo YAML em `.github/workflows/`.
* Uso de GitHub Secrets para credenciais AWS.

## 8. Gerenciamento de Múltiplos Ambientes (dev, prod)

Para gerenciar ambientes distintos como desenvolvimento (`dev`) e produção (`prod`) com o mesmo código base Terraform, a estratégia adotada é o uso de **Terraform Workspaces** em conjunto com arquivos de variáveis específicos por ambiente.

### 8.1. Terraform Workspaces
* **Criação:**
  ```bash
  terraform workspace new dev
  terraform workspace new prod

Seleção:

terraform workspace select dev

Isolamento de Estado: Cada workspace mantém um arquivo de estado (terraform.tfstate) separado, geralmente em um backend remoto como S3, garantindo que as operações em um ambiente não afetem os outros.

8.2. Arquivos de Variáveis por Ambiente
Arquivos como dev.tfvars e prod.tfvars são criados na raiz do projeto.

Estes arquivos contêm os valores das variáveis que diferem entre os ambientes (ex: tipos de instância, contagem de instâncias, nomes de recursos prefixados pela variável environment, configurações de banco de dados, etc.).

Exemplo (prod.tfvars):

environment                 = "prod"
instance_type_frontend      = "t3.small"
instance_type_backend       = "t3.small"
db_instance_class_postgres  = "db.t3.small"
# ... outras configurações de produção ...

Execução:

terraform workspace select prod
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"

A variável environment (definida em cada <ambiente>.tfvars) é usada para nomear e marcar recursos, permitindo fácil identificação e prevenindo conflitos de nome.

Esta abordagem permite reutilizar a base de código modularizada para provisionar e gerenciar múltiplos ambientes de forma consistente e isolada.

9. Conclusão e Próximos Passos Pós-Deploy
Após a execução bem-sucedida do terraform apply para um ambiente específico:

Verificar a funcionalidade do frontend (via DNS do ALB) e do backend.

Confirmar conectividade com o banco de dados RDS.

Acessar o dashboard do Wazuh, verificar o servidor e o registro dos agentes.

Valid