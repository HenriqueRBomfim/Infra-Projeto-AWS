# -----------------------------------------------------------------------------
# Launch Template para o Frontend
# Define como as instâncias do frontend serão configuradas pelo ASG
# -----------------------------------------------------------------------------
resource "aws_launch_template" "frontend_lt" {
  name_prefix   = "${var.environment}-frontend-"
  description   = "Launch template para as instâncias do frontend ASG"
  image_id      = var.ami_id
  instance_type = var.instance_type_frontend
  key_name      = var.key_name

  vpc_security_group_ids = [module.security.frontend_sg_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name # Mesmo IAM profile que você já usa
  }

  # User data precisa ser codificado em base64 para o Launch Template
  user_data = base64encode(data.template_file.frontend_user_data.rendered)

  # Configuração de rede - importante para instâncias em subnets públicas
  network_interfaces {
    associate_public_ip_address = true # Mantendo como estava no seu módulo EC2 para frontend
    # delete_on_termination     = true # Padrão é true
  }

  # Tags que serão aplicadas às instâncias lançadas por este template
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.environment}-frontend-asg-instance"
      Tier        = "Frontend"
      Project     = "MeuProjetoWebApp" # Mantenha suas tags consistentes
      Environment = var.environment
    }
  }

  # Tags para o próprio Launch Template
  tags = {
    Name        = "${var.environment}-frontend-launch-template"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group para o Frontend
# Gerencia as instâncias de frontend, garantindo o número desejado e saúde
# -----------------------------------------------------------------------------
resource "aws_autoscaling_group" "frontend_asg" {
  name                = "${var.environment}-frontend-asg"
  desired_capacity    = 2 # Comece com 2 instâncias para HA
  min_size            = 2
  max_size            = 4 # Permite escalar até 4 instâncias, por exemplo
  health_check_type   = "ELB" # Usa o health check do Load Balancer
  health_check_grace_period = 300 # Segundos para a instância iniciar e passar no health check

  # Subnets onde o ASG pode lançar instâncias.
  # IMPORTANTE: Use a lista completa de subnets públicas para abranger múltiplas AZs.
  vpc_zone_identifier = module.vpc.public_subnet_ids

  launch_template {
    id      = aws_launch_template.frontend_lt.id
    version = "$Latest" # Sempre usa a versão mais recente do Launch Template
  }

  # ASSOCIAÇÃO COM O TARGET GROUP DO SEU ALB DO FRONTEND
  # Substitua pelo ARN real do seu Target Group do frontend ALB
  # Exemplo: target_group_arns = [aws_lb_target_group.frontend_target_group.arn]
  # Se você já tem o 'dev-frontend-alb', você precisa referenciar o ARN do Target Group dele aqui.
  # Se o seu Target Group é criado em outro lugar no seu Terraform, use a referência correta.
  # Se você não tem o ARN do Target Group do seu ALB de frontend definido no Terraform ainda,
  # você precisará adicioná-lo ou buscá-lo. Por agora, vou deixar um placeholder.
  # target_group_arns = ["ARN_DO_SEU_TARGET_GROUP_FRONTEND_ALB"] # <<< PREENCHA OU REFERENCIE CORRETAMENTE

  # Política de terminação (como o ASG escolhe qual instância terminar ao reduzir)
  termination_policies = ["OldestInstance", "Default"] # Exemplo

  # Tags para o próprio ASG
  tag {
    key                 = "Name"
    value               = "${var.environment}-frontend-asg"
    propagate_at_launch = false # Esta tag é para o ASG, não para as instâncias
  }
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = false
  }
  # As tags para as instâncias são definidas no Launch Template

  lifecycle {
    create_before_destroy = true
  }
}


# -----------------------------------------------------------------------------
# Launch Template para o Backend
# Define como as instâncias do backend serão configuradas pelo ASG
# -----------------------------------------------------------------------------
resource "aws_launch_template" "backend_lt" {
  name_prefix   = "${var.environment}-backend-"
  description   = "Launch template para as instâncias do backend ASG"
  image_id      = var.ami_id
  instance_type = var.instance_type_backend
  key_name      = var.key_name

  vpc_security_group_ids = [module.security.backend_sg_id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name # Mesmo IAM profile
  }

  user_data = base64encode(data.template_file.backend_user_data.rendered)

  # Configuração de rede - backend em subnets privadas não deve ter IP público
  network_interfaces {
    associate_public_ip_address = false # Como estava no seu módulo EC2 para backend
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.environment}-backend-asg-instance"
      Tier        = "Backend"
      Project     = "MeuProjetoWebApp"
      Environment = var.environment
    }
  }

  tags = {
    Name        = "${var.environment}-backend-launch-template"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group para o Backend
# Gerencia as instâncias de backend
# -----------------------------------------------------------------------------
resource "aws_autoscaling_group" "backend_asg" {
  name                = "${var.environment}-backend-asg"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 4
  health_check_type   = "EC2" # Mude para "ELB" se você adicionar um Load Balancer para o backend
  health_check_grace_period = 300

  # IMPORTANTE: Use a lista completa de subnets privadas para abranger múltiplas AZs.
  vpc_zone_identifier = module.vpc.private_subnet_ids

  launch_template {
    id      = aws_launch_template.backend_lt.id
    version = "$Latest"
  }

  # ASSOCIAÇÃO COM O TARGET GROUP DE UM LOAD BALANCER DO BACKEND (OPCIONAL INICIALMENTE)
  # Se você for criar um Load Balancer (interno, por exemplo) para o backend,
  # você adicionaria o ARN do Target Group dele aqui.
  # Exemplo: target_group_arns = [aws_lb_target_group.backend_target_group.arn]
  # Por agora, vou deixar comentado. Se não houver LB, o ASG ainda provê HA para as instâncias.
  # target_group_arns = ["ARN_DO_SEU_TARGET_GROUP_BACKEND_LB"] # <<< DESCOMENTE E PREENCHA SE NECESSÁRIO

  termination_policies = ["OldestInstance", "Default"]

  tag {
    key                 = "Name"
    value               = "${var.environment}-backend-asg"
    propagate_at_launch = false
  }
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = false
  }

  lifecycle {
    create_before_destroy = true
  }
}