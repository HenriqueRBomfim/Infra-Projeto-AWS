region                            = "us-east-2"
vpc_cidr                          = "10.0.0.0/16"
public_subnet_cidrs               = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs              = ["10.0.101.0/24", "10.0.102.0/24"]
availability_zones                = ["us-east-2a", "us-east-2b"]
environment                       = "prod"
ami_id                            = "ami-0b05d988257befbbe"
key_name                          = "infra-key"
instance_type_frontend            = "t2.micro"
instance_type_backend             = "t2.micro"

frontend_repo_url                 = "https://github.com/HenriqueRBomfim/henriquerochabomfim.git"
backend_repo_url                  = "git@github.com:HenriqueRBomfim/unity-score-api.git"
backend_app_port                  = 8000
backend_repo_branch               = "aws-deploy" 

db_name_postgres                  = "minhaapidb_pg"
db_username_postgres              = "dbadminpg"
db_instance_class_postgres        = "db.t3.micro"
db_engine_version_postgres        = "16.9" 
db_allocated_storage_postgres     = 20
db_credentials_secret_name_postgres = "dev/rds/postgres/credentials"

github_ssh_key_secret_name        = "dev/github/backend_deploy_key_private"

nextjs_port                       = 3000 # Porta interna do Next.js que o Nginx fará proxy.
                                         # Se o default 3000 em variables.tf já é o desejado, esta linha é opcional.

wazuh_server_instance_type = "t3.large" # Ou "t3.large", dependendo da carga esperada.
                                         # Verifique a documentação do Wazuh para recomendações.

my_home_ip_cidr            = ["186.232.61.64/32"]                                      