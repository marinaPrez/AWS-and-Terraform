terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
#  profile = "IT"
  region  = "us-west-2"
}

variable "ingressrules" {
  type    = list(number)
  default = [80, 443, 22]
}

resource "aws_security_group" "web_traffic" {
  name        = "Allow web traffic"
  description = "Allow ssh and standard http/https ports inbound and everything outbound"

  dynamic "ingress" {
    iterator = port
    for_each = var.ingressrules
    content {
      from_port   = port.value
      to_port     = port.value
      protocol    = "TCP"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
    tags = {
    "Terraform" = "true"
  }
}




resource "tls_private_key" "demo_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
resource "aws_key_pair" "demo_key" {
  key_name   = "demo"
  public_key = tls_private_key.demo_key.public_key_openssh
}
# Save generated key pair locally
  resource "local_file" "server_key" {
  sensitive_content  = tls_private_key.demo_key.private_key_pem
  filename           = "private.pem"
}

resource "aws_instance" "web-server" {
  count             = 2
  ami               = "ami-0b28dfc7adc325ef4"
  instance_type     = "t3.micro"
  security_groups = [aws_security_group.web_traffic.name]
  key_name               = "${aws_key_pair.demo_key.key_name}"
  tags = {
    Name = "Web_Server_${count.index}"
    Purpose    = "ML server"
    Owner      = "Marina"
  }

 ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = 10
    volume_type           = "gp2"
    encrypted             = true
  }
user_data = <<EOF
#!bin/bash
sudo yum install nginx -y
sudo systemctl start nginx
echo "Welcome to Grandpa's Whiskey" | sudo tee /usr/share/nginx/html/index.html
EOF

}

