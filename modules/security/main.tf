# Local: modules/security/main.tf

resource "aws_security_group" "frontend_sg" {
  name        = "${var.environment}-frontend-sg"
  description = "Regras para instancias frontend: HTTP/S publico" // Descrição atualizada
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP do publico"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS do publico"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # REMOVA O BLOCO INGRESS PARA SSH (PORTA 22) DAQUI
  # ingress {
  #   description = "SSH (idealmente via Session Manager ou IP restrito)"
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = var.ssh_access_cidr
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-frontend-sg"
    Environment = var.environment
    Tier        = "Frontend"
  }
}

resource "aws_security_group" "backend_sg" {
  name        = "${var.environment}-backend-sg"
  description = "Regras para instancias backend: Acesso da API pelo Frontend SG" // Descrição atualizada
  vpc_id      = var.vpc_id

  ingress {
    description     = "Trafego da API vindo SOMENTE do Frontend SG"
    from_port       = var.backend_app_port
    to_port         = var.backend_app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_sg.id]
  }

  # REMOVA O BLOCO INGRESS PARA SSH (PORTA 22) DAQUI
  # ingress {
  #   description = "SSH (idealmente via Session Manager ou IP restrito)"
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = var.ssh_access_cidr
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-backend-sg"
    Environment = var.environment
    Tier        = "Backend"
  }
}