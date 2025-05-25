# Local: modules/security/variables.tf

variable "vpc_id" {
  description = "The ID of the VPC where the security groups will be created"
  type        = string
  # No default, as it must be provided by the root module
}

variable "environment" {
  description = "The deployment environment (e.g., dev, prod)"
  type        = string
  # No default, as it's typically passed from the root module
}

variable "backend_app_port" {
  description = "The port the backend application listens on, to be allowed by its security group"
  type        = number
  # No default, as it's specific to the backend application
}

variable "ssh_access_cidr" {
  description = "CIDR block list allowed for SSH access if SSH rules are enabled. Be restrictive!"
  type        = list(string)
  default     = [] # Default para uma lista vazia é mais seguro que 0.0.0.0/0.
                   # Se as regras SSH estiverem ativas e isso estiver vazio, ninguém acessa via SSH direto.
                   # O valor real virá do terraform.tfvars se as regras SSH forem usadas.
}