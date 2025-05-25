module "vpc" {
  source                = "./modules/vpc"
  vpc_cidr              = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]
  availability_zones   = ["us-east-2a", "us-east-2b"]
  environment          = var.environment
}

module "security" {
  source           = "./modules/security"
  vpc_id           = module.vpc.vpc_id
  environment      = var.environment
  backend_app_port = var.backend_app_port
}

# 1. Definir a Política de Confiança para o EC2 assumir a Role
data "aws_iam_policy_document" "ec2_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# 2. Criar a IAM Role que as instâncias EC2 irão assumir
resource "aws_iam_role" "ec2_role" { # Este é o recurso, e "ec2_role" é o nome que damos a ele no Terraform
  name               = "${var.environment}-ec2-role" # O nome real da role na AWS, ex: "dev-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role_policy.json

  tags = {
    Name        = "${var.environment}-ec2-role"
    Environment = var.environment
  }
}

# 3. Anexar a Política Gerenciada para o SSM Session Manager (acesso SSH seguro)
resource "aws_iam_role_policy_attachment" "ssm_core_policy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 4. (Opcional) Anexar a Política para acesso S3 de leitura
resource "aws_iam_role_policy_attachment" "s3_read_only_policy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# 5. (Opcional, mas recomendado se você usou para o backend) Anexar política para ler segredos do Secrets Manager
# Lembre-se que esta política deve ser específica para o segredo que você criou.
# Verifique a resposta anterior para o código completo desta seção se precisar.
# Exemplo simplificado de anexo se você já criou a política "secrets_manager_db_policy":
#
# resource "aws_iam_role_policy_attachment" "secrets_manager_db_attach" {
#   count      = var.enable_secrets_manager_policy ? 1 : 0 # Controlar a criação com uma variável
#   role       = aws_iam_role.ec2_role.name
#   policy_arn = aws_iam_policy.secrets_manager_db_policy[0].arn # Se você criou a aws_iam_policy
# }
#
# Para usar o count acima, você precisaria de uma variável "enable_secrets_manager_policy" (bool)
# e o código para "aws_iam_policy" "secrets_manager_db_policy" (que também usaria count ou for_each).

# 6. Criar o Perfil da Instância IAM para vincular a Role às instâncias EC2
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.environment}-ec2-instance-profile" # O nome real do perfil na AWS
  role = aws_iam_role.ec2_role.name
}

# -----------------------------------------------------------------------------
# User Data Scripts para Frontend e Backend
# (Certifique-se que os arquivos .sh existem na raiz do seu projeto Terraform)
# -----------------------------------------------------------------------------

data "template_file" "frontend_user_data" {
  template = file("${path.module}/user_data_frontend.sh")
  vars = {
    frontend_repo_url = var.frontend_repo_url
    # Adicione outras variáveis que seu script frontend_user_data.sh possa precisar
  }
}

data "template_file" "backend_user_data" {
  template = file("${path.module}/user_data_backend.sh")
  vars = {
    # Chaves à esquerda são como o script user_data as referenciará (ex: ${backend_repo_url})
    # Valores à direita são as variáveis do Terraform
    backend_repo_url                  = var.backend_repo_url
    backend_app_port                  = var.backend_app_port
    aws_region                        = var.region
    backend_repo_branch               = var.backend_repo_branch # Passando a branch
    db_credentials_secret_name_postgres = var.db_credentials_secret_name_postgres # Passando o nome do segredo do PG
  }
}

data "aws_iam_policy_document" "read_db_postgres_secret_policy_doc" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_credentials_postgres.arn] # ARN do segredo PostgreSQL
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

# -----------------------------------------------------------------------------
# Instância EC2 para o Frontend
# -----------------------------------------------------------------------------
module "ec2_frontend" {
  source = "./modules/ec2" # Caminho para o seu módulo EC2

  instance_name               = "${var.environment}-frontend"
  ami                         = var.ami_id
  instance_type               = var.instance_type_frontend # Use a variável específica se declarada
  key_name                    = var.key_name
  # Coloca a instância na primeira subnet pública disponível
  subnet_id                   = module.vpc.public_subnet_ids[0]
  security_group_ids          = [module.security.frontend_sg_id] # ID do SG do frontend
  user_data                   = data.template_file.frontend_user_data.rendered
  iam_instance_profile_name   = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true # Frontend precisa de IP público

  tags = {
    Tier        = "Frontend"
    Project     = "MeuProjetoWebApp" # Exemplo de tag adicional
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Instância EC2 para o Backend
# -----------------------------------------------------------------------------
module "ec2_backend" {
  source = "./modules/ec2" # Caminho para o seu módulo EC2

  instance_name               = "${var.environment}-backend"
  ami                         = var.ami_id
  instance_type               = var.instance_type_backend # Use a variável específica se declarada
  key_name                    = var.key_name
  # Coloca a instância na primeira subnet privada disponível
  subnet_id                   = module.vpc.private_subnet_ids[0]
  security_group_ids          = [module.security.backend_sg_id] # ID do SG do backend
  user_data                   = data.template_file.backend_user_data.rendered
  iam_instance_profile_name   = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false # Backend não precisa de IP público direto

  tags = {
    Tier        = "Backend"
    Project     = "MeuProjetoWebApp" # Exemplo de tag adicional
    Environment = var.environment
  }
}

