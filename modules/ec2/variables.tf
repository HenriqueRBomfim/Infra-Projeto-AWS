variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
}

variable "ami" {
  description = "AMI ID for the EC2 instance"
  type        = string
  # No default, deve ser fornecido
}

variable "instance_type" {
  description = "Type of EC2 instance"
  type        = string
  # Default pode ser removido se você sempre especificar no root module
  # default     = "t2.micro"
}

variable "key_name" {
  description = "Key pair name for SSH access"
  type        = string
  # No default, deve ser fornecido
}

variable "subnet_id" {
  description = "Subnet ID where the EC2 instance will be launched"
  type        = string
  # No default, deve ser fornecido
}

variable "security_group_ids" {
  description = "List of security group IDs to associate with the EC2 instance"
  type        = list(string)
  # No default, deve ser fornecido pelo módulo 'security' via root module
}

variable "user_data" {
  description = "User data script to run on instance launch. Should be pre-rendered if using templatefile."
  type        = string
  default     = null # Alterado de "" para null, para ser mais explícito se não for fornecido
}

variable "iam_instance_profile_name" {
  description = "Name of the IAM instance profile to associate with the EC2 instance"
  type        = string
  default     = null # Ou remova o default se for sempre obrigatório
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IP address with the instance"
  type        = bool
  default     = false # Um default seguro; o root module definirá true para o frontend
}

variable "tags" {
  description = "A map of additional tags to assign to the EC2 instance"
  type        = map(string)
  default     = {}
}