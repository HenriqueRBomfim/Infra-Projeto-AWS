# Local: INFRA-PROJETO-AWS/outputs.tf

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "The IDs of the public subnets"
  value       = module.vpc.public_subnet_ids # Corrigido: usa a saída correta do módulo vpc
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets"
  value       = module.vpc.private_subnet_ids # Corrigido: usa a saída correta do módulo vpc
}

output "frontend_instance_id" {
  description = "The ID of the Frontend EC2 instance"
  value       = module.ec2_frontend.instance_id # Corrigido: refere-se ao módulo ec2_frontend
}

output "frontend_public_ip" {
  description = "The public IP address of the Frontend EC2 instance"
  value       = module.ec2_frontend.public_ip # Corrigido: refere-se ao módulo ec2_frontend
}

output "backend_instance_id" {
  description = "The ID of the Backend EC2 instance"
  value       = module.ec2_backend.instance_id # Corrigido: refere-se ao módulo ec2_backend
}

output "backend_private_ip" {
  description = "The private IP address of the Backend EC2 instance"
  value       = module.ec2_backend.private_ip # Corrigido: refere-se ao módulo ec2_backend
}

# Saídas relacionadas ao RDS PostgreSQL (do seu arquivo database_postgres.tf)
output "rds_postgres_instance_endpoint" {
  description = "The endpoint of the RDS PostgreSQL instance"
  value       = aws_db_instance.postgres_default.address
}

output "rds_postgres_instance_port" {
  description = "The port of the RDS PostgreSQL instance"
  value       = aws_db_instance.postgres_default.port
}

output "db_credentials_postgres_secret_arn" {
  description = "The ARN of the Secrets Manager secret for PostgreSQL DB credentials"
  value       = aws_secretsmanager_secret.db_credentials_postgres.arn
}