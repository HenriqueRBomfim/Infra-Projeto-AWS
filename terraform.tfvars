region                 = "us-east-2"
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs   = ["10.0.101.0/24", "10.0.102.0/24"]
availability_zones     = ["us-east-2a", "us-east-2b"]
environment            = "dev"
ami_id                 = "ami-0b05d988257befbbe" # Seu AMI Ubuntu
key_name               = "infra-keys"            # Seu key pair
instance_type_frontend = "t2.micro"
instance_type_backend  = "t2.micro"

frontend_repo_url      = "https://github.com/HenriqueRBomfim/henriquerochabomfim.git"
backend_repo_url       = "https://github.com/HenriqueRBomfim/unity-score-api.git"
backend_app_port       = 8000 # Ou a porta escolhida