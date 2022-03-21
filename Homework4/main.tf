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
  profile = "IT"
  region  = "us-west-2"
}

resource "aws_vpc" "wiskey_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
#  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "Main VPC"
  }
}
####################################
#privet subnets
###################################

resource "aws_subnet" "privet" {
  vpc_id     = aws_vpc.wiskey_vpc.id
  cidr_block = "10.0.2.0/24"
  tags = {
    Name = "Privet Subnet"
  }
}
#######################################
#public subnets
#####################################


resource "aws_subnet" "public" {
  count      = 2
  vpc_id     = aws_vpc.wiskey_vpc.id
  cidr_block = var.public_subnet[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "Public Subnet"
  }
}




#https://hands-on.cloud/terraform-managing-aws-vpc-creating-private-subnets/
###################
#internet gateway
###################

resource "aws_internet_gateway" "ing" {
   vpc_id     = aws_vpc.wiskey_vpc.id
   tags = {
    Name = "Public Subnet"
  }
}
##########################
#Elastic IP for NAT Gateway
##########################
resource "aws_eip" "nat_eip" {
   vpc = true
   depends_on = [aws_internet_gateway.ing]
   tags = {
    Name = "NAT gateway EIP"
    }
}
###################################
#create NAT gateway
###################################

resource "aws_nat_gateway" "nat_gw" {
  count = 1
  allocation_id = aws_eip.nat_eip.*.id[count.index]
  subnet_id     = aws_subnet.public.*.id[count.index]
  tags = {
    Name = "gw NAT"
  }
  depends_on = [aws_internet_gateway.ing]
}

#####################################
#create routing attributes
#####################################

resource "aws_route_table" "public" {
  count = 1
  vpc_id = aws_vpc.wiskey_vpc.id
  route {
     cidr_block = "0.0.0.0/0" 
     gateway_id = aws_internet_gateway.ing.*.id[count.index]
     }
  tags = {
    "Name" = "Public route table"
  }
}
resource "aws_route_table_association" "public" {
  count = 1
  subnet_id      = aws_subnet.public.*.id[count.index]
  route_table_id = aws_route_table.public.*.id[count.index]
}


resource "aws_route_table" "privat" {
  count = 1
  vpc_id = aws_vpc.wiskey_vpc.id
  route {
     cidr_block = "0.0.0.0/0"
     gateway_id = aws_nat_gateway.nat_gw.*.id[count.index]
     }
  tags = {
    "Name" = "private route table"
  }
}
resource "aws_route_table_association" "private" {
  count = 1
  subnet_id      = aws_subnet.privet.*.id[count.index]
  route_table_id = aws_route_table.privat.*.id[count.index]
}




#####################
# create security group 
#####################


resource "aws_security_group" "web_sg" {
  name        = "web sg"
  vpc_id      = aws_vpc.wiskey_vpc.id
  description = "Allow ssh and standard http/https ports inbound and everything outbound"
  tags = {
    "Terraform" = "true"
    }

}


resource "aws_security_group_rule" "ingress_80" {
    type             = "ingress"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    security_group_id = "${aws_security_group.web_sg.id}"


}


resource "aws_security_group_rule" "ingress_22" {
    type             = "ingress"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    security_group_id = "${aws_security_group.web_sg.id}"

}




resource "aws_security_group_rule" "egress" {
    type =      "egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = "${aws_security_group.web_sg.id}"
}


##################################
# create ssh keys
#################################

resource "tls_private_key" "cloud_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
resource "aws_key_pair" "cloud_key" {
  key_name   = "cloud_key"
  public_key = tls_private_key.cloud_key.public_key_openssh
}
# Save generated key pair locally
  resource "local_file" "server_key" {
  sensitive_content  = tls_private_key.cloud_key.private_key_pem
  filename           = "private.pem"
}

#######################################
#create instance profile
#####################################

resource "aws_iam_instance_profile" "web_profile_cloud" {
  name = "web_profile_cloud"
  role = "EC2_admin"
  #role  = "s3_read_role"
}





####################################
# create web servers
###################################
resource "aws_instance" "web-server" {
  count                    = 2
  ami                      = "ami-0341aeea105412b57"
  instance_type            = "t3.micro"
  vpc_security_group_ids   = ["${aws_security_group.web_sg.id}"]
  subnet_id                = aws_subnet.public.*.id[count.index]
  key_name                = "${aws_key_pair.cloud_key.key_name}"
  associate_public_ip_address = true
  iam_instance_profile = "${aws_iam_instance_profile.web_profile_cloud.name}"
  tags = {
    Name       = "Web_Server_${count.index}"
    Purpose    = "web server"
    Owner      = "Marina"
  }

   # root disk
  root_block_device {
    volume_size           = 10
    volume_type           = "gp2"
    encrypted             = false
    }

   # data disk
  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = 10
    volume_type           = "gp2"
    encrypted             = true
  }

user_data = <<EOF
#!bin/bash
sudo amazon-linux-extras install nginx1 -y
sudo systemctl start nginx
echo "Welcome to Grandpa's Whiskey at  $HOSTNAME " | sudo tee /usr/share/nginx/html/index.html
sudo sh -c 'echo -e "#!/bin/bash \nsudo aws s3 cp /var/log/nginx/access.log  s3://terraform-bucket-maya/logs" > /etc/cron.hourly/upload_to_s3.sh'
sudo chmod +x /etc/cron.hourly/upload_to_s3.sh
EOF

}

output "ec2_global_ips" {
  value = ["${aws_instance.web-server.*.public_ip}"]
}


#############################
#create load balancer
############################

resource "aws_lb" "web-servers" {
  name                       = "webServersLB-cloud"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = aws_subnet.public.*.id
  security_groups            = [aws_security_group.web_sg.id]

  tags = {
    "Name" = "appLoadBalancer"
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web-servers.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
     }
}



resource "aws_lb_target_group" "web" {
  name     = "web-target-group-cloud"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wiskey_vpc.id

  health_check {
    enabled = true
    path    = "/"
      }   
  stickiness {    
    type            = "lb_cookie"    
    cookie_duration = 60    
    enabled         = true 
       }    
  
  tags = {
    "Name" = "web-target-group"
         }
}

resource "aws_lb_target_group_attachment" "web_server" {
  count            = 2
  target_group_arn = aws_lb_target_group.web.id
  target_id        = aws_instance.web-server.*.id[count.index]
  port             = 80
}


######################
#create 2 DB servers 
#####################
resource "aws_instance" "db-server" {
  count                    = 2
  ami                      = "ami-0b28dfc7adc325ef4"
  instance_type            = "t3.micro"
  vpc_security_group_ids   = ["${aws_security_group.db_sg.id}"]
  subnet_id                = aws_subnet.privet.id
  associate_public_ip_address = false
  tags = {
    Name       = "DB_Server_${count.index}"
    Purpose    = "DB server"
    Owner      = "Marina"
  }
}


resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wiskey_vpc.id
  name   = "DB-sg"

  tags = {
    "Name" = "DB-sg"
  }
}

resource "aws_security_group_rule" "DB_ssh" {
  description       = "allow ssh access from anywhere"
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.db_sg.id
  to_port           = 22
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "DB_outbound_anywhere" {
  description       = "allow outbound traffic to anywhere"
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.db_sg.id
  to_port           = 0
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}
