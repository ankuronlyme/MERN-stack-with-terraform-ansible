terraform {
  required_providers {

    local = {
      source  = "hashicorp/local"
      version = "2.0.0"  # You can adjust the version if needed
    }
    tls = {
      source  = "hashicorp/tls"
      version = "3.0.0"  # You can adjust the version if needed
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "ap-south-1"
}

resource "aws_vpc" "mern_app_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.mern_app_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.mern_app_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
}

# Create Internet gateway
resource "aws_internet_gateway" "mern_gw" {
  vpc_id = aws_vpc.mern_app_vpc.id

}

# Create EIP for NAT gateway
resource "aws_eip" "nat" {
  vpc = true
}
# Create NAT gateway
resource "aws_nat_gateway" "mern_nat" {
  depends_on = [ aws_eip.nat ]
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet.id
  }


# Create route table for public subnet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.mern_app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mern_gw.id
  }
}

# Create route table for private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.mern_app_vpc.id
  depends_on = [ aws_nat_gateway.mern_nat ]

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.mern_nat.id
  }
}

# Associate private subnet with publ;ic route table
resource "aws_route_table_association" "public_subnet_association" {
  depends_on = [ aws_subnet.public_subnet, aws_route_table.public_route_table ]
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}


# Associate private subnet with private route table
resource "aws_route_table_association" "private_subnet_assoc" {
  depends_on = [ aws_subnet.public_subnet, aws_route_table.public_route_table ]
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private.id
}


# Create security group for instances in the public subnet
resource "aws_security_group" "public_sg" {
  name        = "public_sg"
  description = "Allow inbound traffic to instances in the public subnet"
  vpc_id      = aws_vpc.mern_app_vpc.id
  depends_on = [ aws_vpc.mern_app_vpc ]

  # Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow 3001 for backend
  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow 3000 for frontend
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    self = false
    security_groups = []
    ipv6_cidr_blocks = []
    prefix_list_ids = []
    description = ""  
  }
}


# Define security groups private
resource "aws_security_group" "mern_db" {
  name        = "mern_db_sg"
  description = "Security group for database server"
  vpc_id      = aws_vpc.mern_app_vpc.id

  # Allow SSH from your IP only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Specify your IP
  }

  # Allow MongoDB port
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create IAM policy for EC2 instances
resource "aws_iam_policy" "ec2_policy" {
  name        = "EC2Policy"
  description = "Policy for EC2 instances"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ec2:AssociateAddress"
        Resource = "*"
      }
      # Add more permissions as needed
    ]
  })
}

# Create IAM role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name               = "EC2Role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Attach IAM policy to IAM role
resource "aws_iam_role_policy_attachment" "ec2_role_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

# EC2 for Webserver
resource "aws_instance" "app_server" {
  count                     = var.app_server_count
  ami                       = "ami-0f58b397bc5c1f2e8"
  instance_type             = "t2.micro"
  subnet_id                 = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  associate_public_ip_address = true
  key_name                    = var.aws_key_pair_name
  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg || { echo "Failed to import GPG key"; exit 1; }
    NODE_MAJOR=18
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt-get update
    sudo apt-get install -y nodejs
  EOF

  tags = {
    Name = "WebServer_${count.index + 1}"
    Environment = "Production"
    Owner       = "Ankur Chauhan"
    Project     = "Travel Memory"
  }
}

# EC2 for Database
resource "aws_instance" "database_server" {
  count         = var.database_server_count
  ami           = "ami-0f58b397bc5c1f2e8"
  instance_type = "t2.micro"
  subnet_id              = aws_subnet.private_subnet.id
  security_groups        = [aws_security_group.mern_db.id]
  associate_public_ip_address = false
  key_name               = var.aws_key_pair_name

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo chmod 600 /var/run/docker.sock
  EOF

  tags = {
    Name = "DatabaseInstance_${count.index + 1}"
  }
}

data "template_file" "ansible_inventory" {
  template = <<-EOT
[web_server]
%{ for i in range(var.app_server_count) ~}
tm_server_${i} ansible_host=${element(aws_instance.app_server[*].public_ip, i)}
%{ endfor ~}

[db_server]
%{ for i in range(var.database_server_count) ~}
db_server_${i} ansible_host=${element(aws_instance.database_server[*].private_ip, i)}
%{ endfor ~}

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/ansible_key
EOT
}

resource "local_file" "ansible_inventory_file" {
  filename = "../ansible/inventory.ini"
  content  = data.template_file.ansible_inventory.rendered
}
