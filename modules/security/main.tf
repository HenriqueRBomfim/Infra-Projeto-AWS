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

resource "aws_security_group" "wazuh_server_sg" {
  name        = "${var.environment}-wazuh-server-sg"
  description = "Permite acesso ao Wazuh Dashboard e comunicação dos agentes"
  vpc_id      = var.vpc_id

  ingress {
    description = "Wazuh Dashboard HTTPS do IP pessoal"
    from_port   = 443 # Porta padrão do Wazuh Dashboard
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.my_home_ip_cidr
  }

  ingress {
    description = "Registro de Agentes Wazuh (API/Enrollment - TCP)"
    from_port   = 1514
    to_port     = 1514
    protocol    = "tcp"
    security_groups = [aws_security_group.frontend_sg.id, aws_security_group.backend_sg.id]
  }

  ingress {
    description = "Coleta de Eventos dos Agentes Wazuh (Remoted - TCP)"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    security_groups = [aws_security_group.frontend_sg.id, aws_security_group.backend_sg.id]
  }
  
  # Se precisar de acesso SSH direto ao servidor Wazuh (use Session Manager como primeira opção):
  # Lembre-se que as regras de SSH nos SGs frontend_sg e backend_sg estão comentadas.
  # Se você também não quer SSH direto para o Wazuh server, este bloco pode ser removido ou permanecer comentado.
  # Se quiser SSH direto para o Wazuh server, descomente e use a variável correta para seu IP.
  # ingress {
  #   description = "SSH do IP pessoal para Wazuh Server"
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = var.my_home_ip_cidr # <<< Usaria my_home_ip_cidr aqui também
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Permite toda comunicação de saída
  }

  tags = {
    Name        = "${var.environment}-wazuh-server-sg"
    Environment = var.environment
  }
}