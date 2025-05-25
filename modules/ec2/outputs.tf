# Local: modules/ec2/outputs.tf

output "instance_id" {
  description = "The ID of the EC2 instance created"
  value       = aws_instance.app_instance.id # Corrigido de my_instance para app_instance
}

output "public_ip" {
  description = "The public IP address of the EC2 instance (if applicable)"
  value       = aws_instance.app_instance.public_ip # Corrigido
}

output "private_ip" {
  description = "The private IP address of the EC2 instance"
  value       = aws_instance.app_instance.private_ip
}

# Se você fosse criar múltiplas instâncias com 'count' neste módulo,
# você poderia querer retornar uma lista de IDs ou IPs.
# Mas para o seu caso (1 FE, 1 BE), chamaremos o módulo duas vezes.