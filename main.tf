module "vpc" {
  source               = "./modules/vpc"
  vpc_cidr             = var.vpc_cidr             # Ex: "10.0.0.0/16"
  public_subnet_cidrs  = var.public_subnet_cidrs  # Ex: ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = var.private_subnet_cidrs # Ex: ["10.0.101.0/24", "10.0.102.0/24"]
  availability_zones   = var.availability_zones   # Ex: ["us-east-2a", "us-east-2b"]
  environment          = var.environment
}

module "security" {
  source           = "./modules/security"
  vpc_id           = module.vpc.vpc_id
  environment      = var.environment
  backend_app_port = var.backend_app_port
}

# Data source para obter o ID da conta AWS atual (necessário para construir ARNs de segredos)
data "aws_caller_identity" "current" {}

# 1. Política de Confiança para o EC2 assumir a Role
data "aws_iam_policy_document" "ec2_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# 2. IAM Role para as instâncias EC2
resource "aws_iam_role" "ec2_role" {
  name               = "${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role_policy.json

  tags = {
    Name        = "${var.environment}-ec2-role"
    Environment = var.environment
  }
}

# 3. Anexar Política Gerenciada para o SSM Session Manager (acesso seguro)
resource "aws_iam_role_policy_attachment" "ssm_core_policy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 4. (Opcional) Anexar Política para acesso S3 de leitura
resource "aws_iam_role_policy_attachment" "s3_read_only_policy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# 5. Anexar política para ler o segredo das credenciais do BD PostgreSQL
data "aws_iam_policy_document" "read_db_postgres_secret_policy_doc" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    # Assume que aws_secretsmanager_secret.db_credentials_postgres é definido em database_postgres.tf
    resources = [aws_secretsmanager_secret.db_credentials_postgres.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_policy" "read_db_postgres_secret_policy" {
  name        = "${var.environment}-read-db-postgres-secret-policy"
  description = "Permite ler o segredo das credenciais do BD PostgreSQL do Secrets Manager"
  policy      = data.aws_iam_policy_document.read_db_postgres_secret_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "read_db_postgres_secret_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.read_db_postgres_secret_policy.arn
}

# Anexar política para ler o segredo da Chave SSH do GitHub (para Deploy Keys)
data "aws_iam_policy_document" "read_github_ssh_key_secret_policy_doc" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    # O ARN do segredo é construído usando o nome fornecido em var.github_ssh_key_secret_name
    resources = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.github_ssh_key_secret_name}-*"]
  }
}

resource "aws_iam_policy" "read_github_ssh_key_secret_policy" {
  name        = "${var.environment}-read-github-ssh-key-policy"
  description = "Permite ler o segredo da chave SSH do GitHub do Secrets Manager"
  policy      = data.aws_iam_policy_document.read_github_ssh_key_secret_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "read_github_ssh_key_secret_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.read_github_ssh_key_secret_policy.arn
}

# 6. Perfil da Instância IAM para vincular a Role às instâncias EC2
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.environment}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# -----------------------------------------------------------------------------
# User Data Scripts para Frontend e Backend
# -----------------------------------------------------------------------------

data "template_file" "frontend_user_data" {
  template = file("${path.module}/user_data_frontend.sh")
  vars = {
    frontend_repo_url = var.frontend_repo_url
    NEXTJS_PORT       = var.nextjs_port # Passa a porta para o script do frontend
  }
}

data "template_file" "backend_user_data" {
  template = file("${path.module}/user_data_backend.sh")
  vars = {
    backend_repo_url                  = var.backend_repo_url # Deve ser a URL SSH se usar Deploy Keys
    APP_PORT                          = var.backend_app_port # Chave usada no script para a porta da API
    aws_region                        = var.region
    backend_repo_branch               = var.backend_repo_branch
    db_credentials_secret_name_postgres = var.db_credentials_secret_name_postgres
    github_ssh_key_secret_name        = var.github_ssh_key_secret_name # Para Deploy Keys SSH
  }
}

# -----------------------------------------------------------------------------
# Instância EC2 para o Frontend
# -----------------------------------------------------------------------------
module "ec2_frontend" {
  source = "./modules/ec2"

  instance_name               = "${var.environment}-frontend"
  ami                         = var.ami_id
  instance_type               = var.instance_type_frontend
  key_name                    = var.key_name
  subnet_id                   = module.vpc.public_subnet_ids[0] # Primeira subnet pública
  security_group_ids          = [module.security.frontend_sg_id]
  user_data                   = data.template_file.frontend_user_data.rendered
  iam_instance_profile_name   = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  tags = {
    Tier        = "Frontend"
    Project     = "MeuProjetoWebApp" # Exemplo de tag
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Instância EC2 para o Backend
# -----------------------------------------------------------------------------
module "ec2_backend" {
  source = "./modules/ec2"

  instance_name               = "${var.environment}-backend"
  ami                         = var.ami_id
  instance_type               = var.instance_type_backend
  key_name                    = var.key_name
  subnet_id                   = module.vpc.private_subnet_ids[0] # Primeira subnet privada
  security_group_ids          = [module.security.backend_sg_id]
  user_data                   = data.template_file.backend_user_data.rendered
  iam_instance_profile_name   = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false

  tags = {
    Tier        = "Backend"
    Project     = "MeuProjetoWebApp" # Exemplo de tag
    Environment = var.environment
  }
}