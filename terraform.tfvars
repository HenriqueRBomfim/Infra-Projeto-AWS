# Values for input variables
region = "us-east-1"
vpc_cidr = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"
instance_type = "t2.micro"
ami_id = "ami-0c55b159cbfafe1f0"  # Example AMI ID, replace with a valid one
key_name = "my-key-pair"  # Replace with your key pair name
desired_capacity = 2  # Number of EC2 instances to launch
tags = {
  Name = "MyEC2Instance"
  Environment = "Development"
}