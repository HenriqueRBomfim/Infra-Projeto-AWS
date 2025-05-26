variable "region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "A list of CIDR blocks for the public subnets"
  type        = list(string)
  # No default, pois depende das AZs e é crucial para o layout
}

variable "private_subnet_cidrs" {
  description = "A list of CIDR blocks for the private subnets"
  type        = list(string)
  # No default
}

variable "availability_zones" {
  description = "A list of availability zones for the subnets"
  type        = list(string)
  # No default
}

variable "environment" {
  description = "The deployment environment (e.g., dev, prod)"
  type        = string
  # No default, geralmente fornecido pelo tfvars
}

variable "ami_id" {
  description = "The AMI ID to use for the EC2 instance"
  type        = string
  # No default, específico da região/OS
}

variable "key_name" {
  description = "The name of the key pair to use for SSH access"
  type        = string
  # No default, específico da conta/usuário
}

variable "instance_type_frontend" {
  description = "The type of EC2 instance to launch for the frontend"
  type        = string
  default     = "t2.micro"
}

variable "instance_type_backend" {
  description = "The type of EC2 instance to launch for the backend"
  type        = string
  default     = "t2.micro"
}

variable "frontend_repo_url" {
  description = "URL of the frontend Git repository"
  type        = string
  # No default
}

variable "backend_repo_url" {
  description = "URL of the backend Git repository"
  type        = string
  # No default (ou default = "" se você quiser permitir opcionalmente não ter backend)
}

variable "backend_repo_branch" {
  description = "A branch do repositório backend a ser clonada na instância EC2"
  type        = string
  default     = "main" 
}

variable "backend_app_port" {
  description = "Port the backend application listens on (for Security Group)"
  type        = number
  default     = 8000 # Ajustado para o valor que você está usando no tfvars
}

variable "db_name_postgres" {
  description = "Nome inicial do banco de dados PostgreSQL a ser criado no RDS"
  type        = string
  default     = "minhaapidb_pg"
}

variable "db_username_postgres" {
  description = "Nome de usuário master para o banco de dados PostgreSQL RDS"
  type        = string
  default     = "dbadminpg"
}

variable "db_instance_class_postgres" {
  description = "Classe da instância para o RDS PostgreSQL (verificar Free Tier)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version_postgres" {
  description = "Versão do motor PostgreSQL para RDS"
  type        = string
  default     = "16.2"
}

variable "db_allocated_storage_postgres" {
  description = "Armazenamento alocado para o RDS PostgreSQL em GB (mínimo 20 para gp2/gp3)"
  type        = number
  default     = 20
}

variable "db_credentials_secret_name_postgres" {
  description = "Nome do segredo no AWS Secrets Manager para as credenciais do PostgreSQL RDS"
  type        = string
  default     = "app/rds/postgres/credentials"
}

variable "github_ssh_key_secret_name" {
  description = "O nome do segredo no AWS Secrets Manager que armazena a chave privada SSH para o deploy do backend GitHub"
  type        = string
  # Nenhum default, pois deve ser específico do seu setup do Secrets Manager
}

# E garanta que var.nextjs_port também está declarada (para o frontend_user_data)
variable "nextjs_port" {
  description = "A porta interna em que a aplicação Next.js vai rodar"
  type        = number
  default     = 3000
}