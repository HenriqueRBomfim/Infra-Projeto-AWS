# Local: modules/security/outputs.tf

output "frontend_sg_id" {
  description = "The ID of the frontend security group"
  value       = aws_security_group.frontend_sg.id
}

output "backend_sg_id" {
  description = "The ID of the backend security group"
  value       = aws_security_group.backend_sg.id
}

output "wazuh_server_sg_id" {
  description = "The ID of the Wazuh server security group"
  value       = aws_security_group.wazuh_server_sg.id
}

output "alb_sg_id" {
  description = "The ID of the Application Load Balancer security group for frontend"
  value       = aws_security_group.alb_sg.id
}