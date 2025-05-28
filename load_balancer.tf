# Local: INFRA-PROJETO-AWS/load_balancer.tf

# -----------------------------------------------------------------------------
# Application Load Balancer (ALB) para o Frontend
# -----------------------------------------------------------------------------
resource "aws_lb" "frontend_alb" {
  name               = "${var.environment}-frontend-alb"
  internal           = false # Voltado para a internet
  load_balancer_type = "application"
  # Este ID virá do output do seu módulo de segurança, após você adicionar o SG do ALB lá
  security_groups = [module.security.alb_sg_id]
  # O ALB deve ser implantado nas suas subnets PÚBLICAS
  subnets = module.vpc.public_subnet_ids

  enable_deletion_protection = false # Para desenvolvimento. Em produção, considere 'true'.

  tags = {
    Name        = "${var.environment}-frontend-alb"
    Environment = var.environment
    Project     = "MeuProjetoWebApp"
  }
}

# -----------------------------------------------------------------------------
# Target Group para as Instâncias do Frontend
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "frontend_tg" {
  name = "${var.environment}-frontend-tg"
  # Porta em que suas instâncias frontend (o Nginx nelas) estão escutando.
  # Se o Nginx na instância EC2 escuta na porta 80 (e faz proxy para o Next.js na porta 3000),
  # então use 80 aqui.
  port        = 80
  protocol    = "HTTP" # Protocolo entre o ALB e suas instâncias
  vpc_id      = module.vpc.vpc_id
  target_type = "instance" # Você está registrando instâncias EC2

  health_check {
    enabled             = true
    path                = "/" # Caminho que o ALB usará para verificar a saúde (ex: sua página inicial)
    protocol            = "HTTP"
    port                = "traffic-port" # Usa a porta definida acima no Target Group (80)
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200-299" # Espera códigos HTTP 200-299 para uma instância saudável
  }

  tags = {
    Name        = "${var.environment}-frontend-tg"
    Environment = var.environment
    Project     = "MeuProjetoWebApp"
  }
}

# -----------------------------------------------------------------------------
# Listener HTTP para o ALB
# Escuta na porta 80 e encaminha para o Target Group do frontend
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "frontend_http" {
  load_balancer_arn = aws_lb.frontend_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

# -----------------------------------------------------------------------------
# Anexar a Instância Frontend ao Target Group
# -----------------------------------------------------------------------------
# Isto assume que você tem uma única instância frontend gerenciada por module.ec2_frontend
resource "aws_lb_target_group_attachment" "frontend_instance_attach" {
  target_group_arn = aws_lb_target_group.frontend_tg.arn
  target_id        = module.ec2_frontend.instance_id # O ID da sua instância frontend
  # port             = 80 # Opcional, apenas se a porta de destino individual for diferente da do target group
}


# --- OPCIONAL: Listener HTTPS (Requer Certificado ACM) ---
# Se você tiver um certificado SSL/TLS no AWS Certificate Manager (ACM),
# descomente e configure o listener HTTPS.

/*
variable "acm_certificate_arn_frontend" {
  description = "ARN do certificado ACM para o frontend ALB"
  type        = string
  default     = "" # Defina no seu terraform.tfvars
}

resource "aws_lb_listener" "frontend_https" {
  count             = var.acm_certificate_arn_frontend != "" ? 1 : 0
  load_balancer_arn = aws_lb.frontend_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08" # Uma política de segurança SSL comum
  certificate_arn   = var.acm_certificate_arn_frontend

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

# (OPCIONAL) Redirecionar HTTP para HTTPS
# Se você configurar HTTPS, modifique a default_action do listener HTTP assim:
#
# resource "aws_lb_listener" "frontend_http_redirect_to_https" {
#   load_balancer_arn = aws_lb.frontend_alb.arn
#   port              = 80
#   protocol          = "HTTP"
#
#   default_action {
#     type = "redirect"
#     redirect {
#       port        = "443"
#       protocol    = "HTTPS"
#       status_code = "HTTP_301" # Redirecionamento permanente
#     }
#   }
# }
# Lembre-se de remover o recurso "aws_lb_listener" "frontend_http" original se usar este de redirecionamento.
*/