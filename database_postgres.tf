# Local: INFRA-PROJETO-AWS/database_postgres.tf

# Gerar senha aleatória para o BD PostgreSQL
resource "random_password" "db_password_postgres" {
  length           = 20 # Aumentado para maior segurança
  special          = true
  override_special = "_%#@" # Caracteres especiais permitidos pelo PostgreSQL
}

# Grupo de Subnets para o RDS PostgreSQL (usando subnets privadas)
resource "aws_db_subnet_group" "postgres_default" {
  name       = "${var.environment}-pg-db-subnet-group"
  subnet_ids = module.vpc.private_subnet_ids # Do seu módulo VPC

  tags = {
    Name        = "${var.environment}-pg-db-subnet-group"
    Environment = var.environment
  }
}

# Security Group para o RDS PostgreSQL
resource "aws_security_group" "rds_postgres_sg" {
  name        = "${var.environment}-rds-postgres-sg"
  description = "Permite acesso ao RDS PostgreSQL a partir do backend EC2 SG"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Acesso PostgreSQL a partir das instancias Backend"
    from_port       = 5432 # Porta padrão do PostgreSQL
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.security.backend_sg_id] # ID do SG do seu backend
  }

  tags = {
    Name        = "${var.environment}-rds-postgres-sg"
    Environment = var.environment
  }
}

# Instância de Banco de Dados RDS PostgreSQL
resource "aws_db_instance" "postgres_default" {
  identifier             = "${var.environment}-postgresdb"
  allocated_storage      = var.db_allocated_storage_postgres
  engine                 = "postgres"
  engine_version         = var.db_engine_version_postgres
  instance_class         = var.db_instance_class_postgres
  db_name                = var.db_name_postgres
  username               = var.db_username_postgres
  password               = random_password.db_password_postgres.result
  db_subnet_group_name   = aws_db_subnet_group.postgres_default.name
  vpc_security_group_ids = [aws_security_group.rds_postgres_sg.id]
  parameter_group_name   = "default.postgres${split(".", var.db_engine_version_postgres)[0]}"

  skip_final_snapshot    = true  # Para dev/test. Em produção, defina como false.
  publicly_accessible    = false # Importante para segurança
  storage_encrypted      = true  # Recomendado
  # backup_retention_period = 0  # Considere para Free Tier se necessário.

  tags = {
    Name        = "${var.environment}-rds-postgres-instance"
    Environment = var.environment
  }
}

# Armazenar credenciais do BD PostgreSQL no AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials_postgres" {
  name        = var.db_credentials_secret_name_postgres # Usando a variável para o nome do segredo
  description = "Credenciais do banco de dados PostgreSQL RDS para ${var.environment}"
  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials_postgres_version" {
  secret_id     = aws_secretsmanager_secret.db_credentials_postgres.id
  secret_string = jsonencode({
    username             = aws_db_instance.postgres_default.username
    password             = aws_db_instance.postgres_default.password # Referenciar a senha da instância é ok, pois ela obtém do random_password.
    engine               = aws_db_instance.postgres_default.engine
    host                 = aws_db_instance.postgres_default.address # Endpoint do RDS
    port                 = aws_db_instance.postgres_default.port
    dbname               = aws_db_instance.postgres_default.db_name
    dbInstanceIdentifier = aws_db_instance.postgres_default.identifier
    secret_arn           = aws_secretsmanager_secret.db_credentials_postgres.arn
  })
}