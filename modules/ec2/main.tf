resource "aws_instance" "app_instance" {
  ami                         = var.ami
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  user_data                   = var.user_data
  iam_instance_profile        = var.iam_instance_profile_name
  associate_public_ip_address = var.associate_public_ip_address

  root_block_device {
    volume_size = var.root_volume_size

    volume_type = "gp3"

    delete_on_termination = true
  }

  tags = merge(
    {
      Name = var.instance_name
    },
    var.tags
  )
}