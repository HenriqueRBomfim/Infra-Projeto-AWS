variable "region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" { // Já existe, mas garanta que esteja ok
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" { // Usado na chamada do módulo vpc
  description = "A list of CIDR blocks for the public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" { // Usado na chamada do módulo vpc
  description = "A list of CIDR blocks for the private subnets"
  type        = list(string)
}

variable "availability_zones" { // Usado na chamada do módulo vpc
  description = "A list of availability zones for the subnets"
  type        = list(string)
}

variable "environment" { // Usado nas chamadas dos módulos
  description = "The deployment environment (e.g., dev, prod)"
  type        = string
}

variable "ami_id" { // Para as instâncias EC2
  description = "The AMI ID to use for the EC2 instance"
  type        = string
}

variable "key_name" { // Para as instâncias EC2
  description = "The name of the key pair to use for SSH access"
  type        = string
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
}

variable "backend_repo_url" { // Mesmo que não vá implementar o backend agora, declare
  description = "URL of the backend Git repository"
  type        = string
  default     = "" # Ou um repo placeholder
}

variable "backend_app_port" {
  description = "Port the backend application listens on (for Security Group)"
  type        = number
  default     = 3000 # Ou a porta padrão do seu backend
}