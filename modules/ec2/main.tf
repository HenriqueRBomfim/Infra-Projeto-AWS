resource "aws_instance" "app_instance" {
  ami                         = var.ami
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids # Usa os SGs passados como variável
  user_data                   = var.user_data          
  iam_instance_profile        = var.iam_instance_profile_name # Para a IAM Role
  associate_public_ip_address = var.associate_public_ip_address

  tags = merge(
    {
      Name = var.instance_name # O nome principal da instância
    },
    var.tags # Permite adicionar tags customizadas passadas pelo módulo raiz
  )
}