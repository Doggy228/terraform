terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-north-1"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_key_pair" "antonkey" {
  key_name   = "antonkey"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCpScX9olgul+XzUljwfmBDuHJK5fWh6bVDylD040cuO97MWJ/TzfD3zAF++KZQK/WUSMuu/SLaCjzpDIPr1uXhnHMo5yEgfiiXi/AKooQibU/F+bkRezLCKtYHmqVkE8vI9kJPmMwk8Q8I2TO53e+DuA4tFRsWpANwu+aFRsra6yVIa8cV2IUErUf9avYI5XxgeTpUwDz4T0QiH5ByTrv5pOubbUjCsEEFsu3oxhiEYs0bdLkzmmnMsyP3ax66sKbCPn8J2cvAbmnOhIebBVser2vgMRPB9ynbTeLEZuIUyfFcd6ZexyiTobJINSmc7cJqsEtZQ1wooxBqHHFVRwGT antonkey"
}

resource "aws_instance" "app_server" {
  ami                    = "ami-064087b8d355e9051" # data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.antonkey.key_name
  vpc_security_group_ids = [aws_security_group.main.id]
  user_data              = <<EOF
#!/bin/bash
sudo apt-get --yes --force-yes update
sudo apt-get --yes --force-yes install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get --yes --force-yes update
sudo apt-get --yes --force-yes install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run -d --name watchtower -v /var/run/docker.sock:/var/run/docker.sock   containrrr/watchtower
sudo docker run -d -p 80:80 -v /var/run/docker.sock:/var/run/docker.sock --name mzlab-app anton2204/mzlab-app
echo Done!
  EOF
  tags = {
    Name = "MZLabAppServerInstance"
  }
}

locals {
  ports_in = [
    22,
    80
  ]
  ports_out = [
    0
  ]
}

resource "aws_security_group" "main" {
  name        = "mzlab-sec-group"
  description = "Security group for SSH and HTTP"

  dynamic "ingress" {
    for_each = toset(local.ports_in)
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  dynamic "egress" {
    for_each = toset(local.ports_out)
    content {
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}

output "web-address" {
  value = aws_instance.app_server.public_dns
}


