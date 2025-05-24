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

# 4. (Opcional) Anexar a Política para acesso S3 de leitura (se sua app precisar)
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