# Documentação do Projeto: Infraestrutura AWS com Terraform

## 1. Introdução e Objetivo do Projeto

Este documento descreve o processo de criação e configuração de uma infraestrutura na Amazon Web Services (AWS) utilizando Terraform. O objetivo é hospedar uma aplicação web composta por um frontend (Next.js) e um backend (API FastAPI com PostgreSQL), seguindo as melhores práticas de segurança, modularização e infraestrutura como código. Esta documentação serve como um registro do desenvolvimento até o ponto de implantação via `terraform apply`.

## 2. Configuração Inicial do Ambiente AWS

### 2.1. Criação de Usuário IAM Admin
O primeiro passo foi a criação de um usuário IAM (Identity and Access Management) na conta AWS com permissões administrativas. Esta abordagem evita o uso da conta root para operações do dia a dia, seguindo as melhores práticas de segurança da AWS.

**Ações Realizadas:**
* Criação de um novo usuário IAM.
* Atribuição da política `AdministratorAccess` a este usuário.
* Geração de chaves de acesso (Access Key ID e Secret Access Key) para este usuário, para permitir o acesso programático.

### 2.2. Configuração de Credenciais AWS (AWS CLI)
As chaves de acesso geradas para o usuário IAM Admin foram configuradas localmente no ambiente de desenvolvimento utilizando o AWS Command Line Interface (AWS CLI).

**Ações Realizadas:**
* Instalação do AWS CLI.
* Execução do comando `aws configure`.
* Inserção do Access Key ID, Secret Access Key, região padrão (ex: `us-east-2`) e formato de saída padrão (ex: `json`). Isso criou um perfil de credenciais (geralmente o perfil `default`) que o Terraform utilizará para autenticar com a AWS.

## 3. Configuração do Ambiente de Desenvolvimento Local

### 3.1. Instalação do Terraform
O Terraform foi instalado no ambiente de desenvolvimento local para permitir a criação e gerenciamento da infraestrutura como código.

**Ações Realizadas:**
* Download do binário do Terraform do site oficial.
* Configuração do PATH do sistema para incluir o executável do Terraform, permitindo que ele seja chamado de qualquer diretório no terminal.

## 4. Estrutura do Projeto Terraform (`INFRA-PROJETO-AWS`)

O projeto Terraform foi organizado de forma modular para promover a reutilização e a clareza.

### 4.1. Visão Geral
A estrutura do projeto consiste em um módulo raiz que orquestra módulos locais para diferentes componentes da infraestrutura.


INFRA-PROJETO-AWS/
├── modules/
│   ├── ec2/       # Módulo para instâncias EC2
│   ├── security/  # Módulo para Security Groups
│   └── vpc/       # Módulo para VPC e rede
├── main.tf        # Configuração principal do módulo raiz
├── variables.tf   # Declaração de variáveis de entrada do projeto
├── terraform.tfvars # Valores para as variáveis de entrada
├── outputs.tf     # Saídas do projeto
├── provider.tf    # Configuração do provedor AWS
├── database_postgres.tf # Configuração do RDS e Secrets Manager
├── user_data_frontend.sh # Script de inicialização do frontend
└── user_data_backend.sh  # Script de inicialização do backend


### 4.2. Módulo Raiz
Localizado na pasta `INFRA-PROJETO-AWS/`, o módulo raiz contém:
* **`main.tf`**: Define os recursos globais (como a configuração IAM para EC2, o perfil da instância, e os data sources para os scripts de user data) e chama os módulos locais (VPC, Security, EC2).
* **`variables.tf`**: Declara todas as variáveis de entrada do projeto (ex: região, CIDRs, URLs de repositórios, configurações de banco de dados).
* **`terraform.tfvars`**: Fornece os valores específicos para as variáveis de entrada para este ambiente de implantação.
* **`outputs.tf`**: Define quais informações serão exibidas após a aplicação do Terraform (ex: IP público do frontend, endpoint do RDS).
* **`provider.tf`**: Configura o provedor AWS, especificando a região e o perfil de credenciais.
* **`database_postgres.tf`**: Define os recursos para o banco de dados RDS PostgreSQL e o armazenamento seguro de suas credenciais no AWS Secrets Manager.

### 4.3. Módulos Locais
* **Módulo VPC (`modules/vpc/`)**: Responsável pela criação da Virtual Private Cloud (VPC), subnets públicas e privadas em múltiplas Zonas de Disponibilidade, Internet Gateway (IGW), NAT Gateway (com Elastic IP) e as tabelas de rotas associadas para garantir a conectividade correta.
* **Módulo Security (`modules/security/`)**: Gerencia os Security Groups. Cria um grupo para o frontend (permitindo tráfego HTTP/S público) e um para o backend (permitindo tráfego na porta da API apenas a partir do security group do frontend). O acesso SSH foi planejado para ser via AWS Systems Manager Session Manager, removendo a necessidade de expor a porta 22.
* **Módulo EC2 (`modules/ec2/`)**: Define um módulo genérico para criar instâncias EC2. É chamado duas vezes pelo módulo raiz: uma para a instância do frontend e outra para a instância do backend, cada uma com suas configurações específicas (AMI, tipo de instância, subnet, security groups, user data, IAM profile).

## 5. Componentes da Infraestrutura e Decisões de Design

### 5.1. Rede (VPC)
Uma VPC customizada (`10.0.0.0/16`) foi projetada com:
* **Subnets Públicas**: Para recursos que precisam de acesso direto à internet, como a instância EC2 do frontend. Estas subnets têm rotas para o Internet Gateway.
* **Subnets Privadas**: Para recursos que não devem ser diretamente acessíveis pela internet, como a instância EC2 do backend e o banco de dados RDS. Estas subnets têm rotas para um NAT Gateway (localizado em uma subnet pública) para permitir acesso de saída à internet (ex: para baixar pacotes ou conectar-se a serviços externos, se necessário).
* **Zonas de Disponibilidade (AZs)**: As subnets foram distribuídas em múltiplas AZs (`us-east-2a`, `us-east-2b`) para aumentar a resiliência.

### 5.2. Segurança
* **Security Groups**:
    * **Frontend SG**: Permite tráfego de entrada nas portas 80 (HTTP) e 443 (HTTPS) de qualquer origem (`0.0.0.0/0`).
    * **Backend SG**: Permite tráfego de entrada na porta da aplicação backend (ex: `8000`) somente a partir do Security Group do frontend. Isso isola o backend da internet direta.
    * **RDS SG**: Permite tráfego de entrada na porta do PostgreSQL (5432) somente a partir do Security Group do backend.
    * **Acesso SSH**: As regras de SSH (porta 22) foram removidas dos Security Groups das instâncias EC2 em favor do uso do AWS Systems Manager Session Manager para acesso seguro.
* **IAM (Identity and Access Management)**:
    * Uma IAM Role (`ec2_role`) foi criada para as instâncias EC2.
    * Políticas anexadas a esta role incluem:
        * `AmazonSSMManagedInstanceCore`: Para permitir o uso do Session Manager.
        * Permissão para ler o segredo das credenciais do banco de dados do AWS Secrets Manager.
        * (Opcional) `AmazonS3ReadOnlyAccess`.
    * Um IAM Instance Profile (`ec2_profile`) foi criado para associar a role às instâncias.

### 5.3. Instâncias de Cômputo (EC2)
Duas instâncias EC2 (`t2.micro` ou `t3.micro`, usando AMI Ubuntu) são provisionadas:
* **Instância Frontend**:
    * Localizada em uma subnet pública.
    * Associada ao `frontend_sg`.
    * Executa a aplicação Next.js (com React e Tailwind CSS) utilizando um script `user_data`.
* **Instância Backend**:
    * Localizada em uma subnet privada.
    * Associada ao `backend_sg`.
    * Executa a API FastAPI (Python) com PostgreSQL utilizando um script `user_data`.

### 5.4. Banco de Dados (RDS PostgreSQL)
* Uma instância RDS PostgreSQL (`db.t3.micro`, versão `16.2`) é provisionada.
* Localizada nas subnets privadas utilizando um `aws_db_subnet_group`.
* Protegida por um Security Group (`rds_postgres_sg`) que permite acesso apenas da instância backend.
* Configurada para não ser publicamente acessível e com armazenamento criptografado.

### 5.5. Gerenciamento de Segredos (AWS Secrets Manager)
* As credenciais (usuário master e senha gerada aleatoriamente) para o banco de dados RDS PostgreSQL são armazenadas de forma segura no AWS Secrets Manager.
* A instância EC2 do backend utiliza sua IAM Role para buscar essas credenciais em tempo de execução.

### 5.6. Acesso às Instâncias (AWS Systems Manager Session Manager)
Para acesso seguro às instâncias EC2 (tanto frontend quanto backend) sem expor a porta SSH (22), o AWS Systems Manager Session Manager foi configurado. Isso é habilitado pela IAM Role com a política `AmazonSSMManagedInstanceCore` e pelo SSM Agent pré-instalado na AMI Ubuntu.

## 6. Scripts de User Data

Scripts de inicialização (`user_data`) são usados para configurar as instâncias EC2 no primeiro boot:
* **`user_data_frontend.sh`**:
    * Instala Node.js, Git, Nginx.
    * Clona o repositório frontend do GitHub.
    * Instala dependências (`npm install`).
    * Realiza o build da aplicação Next.js (`npm run build`).
    * Configura o Nginx como um proxy reverso para a aplicação Next.js.
    * Inicia a aplicação Next.js usando `pm2` para gerenciamento de processos.
* **`user_data_backend.sh`**:
    * Instala Python, pip, venv, Git, `jq`.
    * Clona o repositório backend da API (branch `aws-deploy`) do GitHub.
    * Cria um ambiente virtual Python e instala as dependências do `requirements.txt` (incluindo FastAPI, Uvicorn, Gunicorn, psycopg2-binary, Alembic).
    * Busca as credenciais do banco de dados do AWS Secrets Manager e as configura como variáveis de ambiente (ou em um arquivo `.env`).
    * Executa as migrações do Alembic (`alembic upgrade head`).
    * Cria e inicia um serviço `systemd` para rodar a aplicação FastAPI com Gunicorn e Uvicorn workers.

## 7. Versionamento e Modularização

* **Modularização**: O código Terraform foi dividido em módulos locais (VPC, Security, EC2) para melhor organização, reutilização e manutenibilidade.
* **Versionamento**: O projeto de infraestrutura é gerenciado usando Git. Foi criada uma branch `aws-deploy` no repositório da API para conter as configurações específicas da AWS (como o `env.py` e `alembic.ini` modificados para ler a `DATABASE_URL` do ambiente). O Terraform também especifica as versões requeridas do provedor AWS.

## 8. Próximos Passos: Deploy com Terraform

Com toda a configuração revisada e considerada correta, os próximos passos são executar os comandos Terraform para provisionar a infraestrutura na AWS:
1.  **`terraform init -upgrade`**: Para inicializar o diretório de trabalho, baixar os provedores e módulos.
2.  **`terraform validate`**: Para verificar a sintaxe e consistência da configuração.
3.  **`terraform plan`**: Para revisar as ações que o Terraform executará.
4.  **`terraform apply`**: Para aplicar as configurações e criar os recursos na AWS.

Após o `apply`, serão realizados testes para verificar a funcionalidade do frontend, do backend e a comunicação entre eles, bem como o acesso ao banco de dados e o acesso às instâncias via Session Manager.
