provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "k8s_vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id
  tags = {
    Name = "k8s_igw"
  }
}

# Public Subnet
resource "aws_subnet" "k8s_public_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "192.168.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "k8s_public_subnet"
  }
}

# Private Subnet
resource "aws_subnet" "k8s_private_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "192.168.80.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "us-east-1a"

  tags = {
    Name = "k8s_private_subnet"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "k8s_nat_eip" {
  domain = "vpc"

  tags = {
    Name = "k8s_nat_eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "k8s_nat_gw" {
  allocation_id = aws_eip.k8s_nat_eip.id
  subnet_id     = aws_subnet.k8s_public_subnet.id

  tags = {
    Name = "k8s_nat_gw"
  }

  depends_on = [aws_eip.k8s_nat_eip]

}

# Route Table for Public Subnet
resource "aws_route_table" "k8s_public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = {
    Name = "k8s_public_rt"
  }

  depends_on = [aws_nat_gateway.k8s_nat_gw]

}


# Associate Public Subnet with Public Route Table
resource "aws_route_table_association" "k8s_public_rta" {
  subnet_id      = aws_subnet.k8s_public_subnet.id
  route_table_id = aws_route_table.k8s_public_rt.id
}

# Private Route Table
resource "aws_route_table" "k8s_private_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.k8s_nat_gw.id
  }

  tags = {
    Name = "k8s_private_rt"
  }

  depends_on = [aws_internet_gateway.k8s_igw]

}

# Associate Private Subnet with Private Route Table
resource "aws_route_table_association" "k8s_private_rta" {
  subnet_id      = aws_subnet.k8s_private_subnet.id
  route_table_id = aws_route_table.k8s_private_rt.id
}


# Security Group for Public Instance
resource "aws_security_group" "public_sg" {
  vpc_id = aws_vpc.k8s_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all protocols
    cidr_blocks = ["0.0.0.0/0"] # Open to the world; consider restricting for production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "public_sg"
  }
}

# Security Group
resource "aws_security_group" "k8s_sg" {
  vpc_id = aws_vpc.k8s_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all protocols
    cidr_blocks = ["0.0.0.0/0"] # Open to the world; consider restricting for production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s_sg"
  }
}


# Key Pair
resource "aws_key_pair" "k8s_key_pair" {
  key_name   = "my_k8s_key"
  public_key = tls_private_key.k8s_key_pair.public_key_openssh
}

# Generate a TLS private key
resource "tls_private_key" "k8s_key_pair" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Output the private key to save it locally
output "k8s_private_key" {
  value     = tls_private_key.k8s_key_pair.private_key_pem
  sensitive = true
}

resource "null_resource" "save_private_key" {
  provisioner "local-exec" {
    command = "echo '${tls_private_key.k8s_key_pair.private_key_pem}' > my_k8s_key.pem && chmod 600 my_k8s_key.pem"
  }

  depends_on = [tls_private_key.k8s_key_pair]
}

# IAM Role for EC2 instances to access S3 and other resources
resource "aws_iam_role" "k8s_instance_role" {
  name = "k8s_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.k8s_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "k8s_instance_profile" {
  name = "k8s_instance_profile"
  role = aws_iam_role.k8s_instance_role.name
}

# User Data for Kubernetes setup on the Control Plane
data "template_file" "controlplane_user_data" {
  template = <<-EOF
    #!/bin/bash
    # Set hostname for the control plane node
    hostnamectl set-hostname ${var.controlplane_hostname}

    # Download and execute the setup script
    curl -O https://raw.githubusercontent.com/sorianfr/kubeadm_multinode_cluster_vagrant/master/setup_k8s_ec2.sh
    chmod +x /setup_k8s_ec2.sh
    /setup_k8s_ec2.sh
  EOF
}

# Worker1 User Data
data "template_file" "worker1_user_data" {
  template = <<-EOF
    #!/bin/bash
    # Set hostname for worker1
    hostnamectl set-hostname ${var.worker1_hostname}

    # Download and execute the setup script
    curl -O https://raw.githubusercontent.com/sorianfr/kubeadm_multinode_cluster_vagrant/master/setup_k8s_ec2.sh
    chmod +x /setup_k8s_ec2.sh
    /setup_k8s_ec2.sh
  EOF
}

# Worker2 User Data
data "template_file" "worker2_user_data" {
  template = <<-EOF
    #!/bin/bash
    # Set hostname for worker2
    hostnamectl set-hostname ${var.worker2_hostname}

    # Download and execute the setup script
    curl -O https://raw.githubusercontent.com/sorianfr/kubeadm_multinode_cluster_vagrant/master/setup_k8s_ec2.sh
    chmod +x /setup_k8s_ec2.sh
    /setup_k8s_ec2.sh
  EOF
}

# Control Plane Instance
resource "aws_instance" "controlplane" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.k8s_private_subnet.id
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.k8s_instance_profile.name
  key_name                    = aws_key_pair.k8s_key_pair.key_name
  private_ip                  = "192.168.80.58"  # Specify your desired private IP here

  user_data                   = data.template_file.controlplane_user_data.rendered

  source_dest_check           = false  # Disable Source/Destination Check

  tags = {
    Name = "controlplane"
  }

  depends_on = [aws_nat_gateway.k8s_nat_gw]

}

# Worker Node Instances
resource "aws_instance" "worker1" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.k8s_private_subnet.id
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.k8s_instance_profile.name
  key_name                    = aws_key_pair.k8s_key_pair.key_name
  private_ip                  = "192.168.80.59"  # Specify your desired private IP here
  user_data                   = data.template_file.worker1_user_data.rendered

  source_dest_check           = false  # Disable Source/Destination Check

  tags = {
    Name = "worker1"
  }

  depends_on = [aws_nat_gateway.k8s_nat_gw]

}

resource "aws_instance" "worker2" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.k8s_private_subnet.id
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.k8s_instance_profile.name
  key_name                    = aws_key_pair.k8s_key_pair.key_name
  private_ip                  = "192.168.80.60"  # Specify your desired private IP here
  user_data                   = data.template_file.worker2_user_data.rendered

  source_dest_check           = false  # Disable Source/Destination Check

  tags = {
    Name = "worker2"
  }

  depends_on = [aws_nat_gateway.k8s_nat_gw]

}

# Public Instance
resource "aws_instance" "bastion" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.k8s_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.public_sg.id] # Correct parameter
  key_name = aws_key_pair.k8s_key_pair.key_name

  tags = {
    Name = "bastion"
  }
}

resource "null_resource" "copy_key_to_bastion" {
  provisioner "local-exec" {
    command = <<-EOT
      sleep 60
      scp -i "my_k8s_key.pem" -o StrictHostKeyChecking=no "my_k8s_key.pem" ubuntu@${aws_instance.bastion.public_dns}:~/
    EOT
  }

  depends_on = [aws_instance.bastion, null_resource.save_private_key]
}

resource "null_resource" "wait_for_worker2_setup" {
  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /home/ubuntu/setup_completed.txt ]; do echo 'Waiting for setup to complete...'; sleep 10; done"
    ]

    connection {
      type        = "ssh"
      host        = aws_instance.worker2.private_ip
      user        = "ubuntu"
      private_key = tls_private_key.k8s_key_pair.private_key_pem

      bastion_host = aws_instance.bastion.public_dns
      bastion_user = "ubuntu"
      bastion_private_key = tls_private_key.k8s_key_pair.private_key_pem
    }
  }

  provisioner "local-exec" {
    command = "echo 'Worker2 setup complete' > ./setup_completed_worker2.txt"
  }

  depends_on = [null_resource.copy_key_to_bastion, aws_instance.worker2, null_resource.save_private_key]
}



# Define the local-exec provisioner for each instance to update /etc/hosts
resource "null_resource" "update_hosts" {
  depends_on = [null_resource.copy_key_to_bastion, aws_instance.bastion, aws_instance.controlplane, aws_instance.worker1, aws_instance.worker2, null_resource.wait_for_worker2_setup]

  provisioner "local-exec" {
    command = <<-EOT
      for ip in ${aws_instance.controlplane.private_ip} ${aws_instance.worker1.private_ip} ${aws_instance.worker2.private_ip}; do
        ssh -i "my_k8s_key.pem" -o StrictHostKeyChecking=no -o ProxyCommand="ssh -i my_k8s_key.pem -W %h:%p ubuntu@${aws_instance.bastion.public_dns}" ubuntu@$ip \
        "echo '${aws_instance.controlplane.private_ip} controlplane' | sudo tee -a /etc/hosts && \
         echo '${aws_instance.worker1.private_ip} worker1' | sudo tee -a /etc/hosts && \
         echo '${aws_instance.worker2.private_ip} worker2' | sudo tee -a /etc/hosts"
      done
    EOT
  }
}
