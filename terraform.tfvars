region                 = "us-east-2"
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs   = ["10.0.101.0/24", "10.0.102.0/24"]
availability_zones     = ["us-east-2a", "us-east-2b"]
environment            = "dev"
ami_id                 = "ami-0b05d988257befbbe" 
key_name               = "infra-keys"            
instance_type_frontend = "t2.micro"
instance_type_backend  = "t2.micro"

frontend_repo_url      = "https://github.com/HenriqueRBomfim/henriquerochabomfim.git"
backend_repo_url       = "https://github.com/HenriqueRBomfim/unity-score-api.git"
backend_app_port       = 8000 
backend_repo_branch    = "aws-deploy"

db_name_postgres                  = "minhaapidb_pg"
db_username_postgres              = "dbadminpg"
db_instance_class_postgres        = "db.t3.micro"
db_engine_version_postgres        = "16.2"
db_allocated_storage_postgres     = 20
db_credentials_secret_name_postgres = "dev/rds/postgres/credentials" # Exemplo com o ambiente no nome
