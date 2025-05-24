# Infra Projeto AWS

Este projeto é uma infraestrutura como código (IaC) utilizando Terraform para provisionar recursos na AWS. A estrutura do projeto é modular, permitindo a reutilização de componentes como VPC e EC2.

## Estrutura do Projeto

```
infra-projeto-aws/
├── README.md                 # Documentação do projeto
├── main.tf                   # Código principal (recursos AWS)
├── variables.tf              # Variáveis de entrada
├── outputs.tf                # Variáveis de saída
├── provider.tf               # Configuração da AWS
├── modules/                  # Módulos reutilizáveis (ex: VPC, EC2)
│   ├── vpc/                  # Módulo VPC
│   │   ├── main.tf           # Recursos da VPC
│   │   ├── variables.tf      # Variáveis do módulo VPC
│   │   └── outputs.tf        # Saídas do módulo VPC
│   └── ec2/                  # Módulo EC2
│       ├── main.tf           # Recursos EC2
│       ├── variables.tf      # Variáveis do módulo EC2
│       └── outputs.tf        # Saídas do módulo EC2
└── terraform.tfvars          # Valores específicos para suas variáveis
```

## Instruções de Configuração

1. **Pré-requisitos**:
   - Ter o Terraform instalado na sua máquina.
   - Ter uma conta na AWS com as permissões necessárias para criar os recursos.

2. **Configuração do Provider**:
   - Edite o arquivo `provider.tf` para incluir suas credenciais da AWS e a região desejada.

3. **Definição de Variáveis**:
   - Modifique o arquivo `terraform.tfvars` para definir os valores das variáveis de entrada conforme necessário.

4. **Inicialização do Terraform**:
   - Execute o comando `terraform init` para inicializar o diretório do Terraform.

5. **Planejamento da Infraestrutura**:
   - Execute `terraform plan` para visualizar as mudanças que serão aplicadas.

6. **Aplicação da Infraestrutura**:
   - Execute `terraform apply` para provisionar os recursos na AWS.

## Diretrizes de Uso

- Utilize os módulos disponíveis para criar e gerenciar diferentes componentes da infraestrutura.
- Consulte os arquivos `outputs.tf` para entender quais informações serão retornadas após a criação dos recursos.
- Para mais informações sobre cada módulo, consulte a documentação específica dentro das pastas `modules/vpc` e `modules/ec2`.