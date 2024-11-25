    provider "aws" {
      region = "us-east-1"
    }

    # VPC
    resource "aws_vpc" "k8s_vpc" {
      cidr_block           = var.vpc_cidr_block
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
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"] # Open to the world for SSH; consider restricting for production
      }

      egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
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
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        security_groups = [aws_security_group.public_sg.id] # Allow SSH from the bastion
      }

      ingress {
        from_port   = 6443
        to_port     = 6443
        protocol    = "tcp"
        cidr_blocks = [var.vpc_cidr_block] # Kubernetes API access within VPC
      }

      ingress {
        from_port   = 30000
        to_port     = 32767
        protocol    = "tcp"
        cidr_blocks = [var.vpc_cidr_block] # NodePort range within VPC
      }

      ingress {
        from_port   = 10250
        to_port     = 10250
        protocol    = "tcp"
        cidr_blocks = [var.vpc_cidr_block] # # Kubelet communication within VPC
      }
    
      ingress {
        from_port   = 5473
        to_port     = 5473
        protocol    = "tcp"
        cidr_blocks = [var.vpc_cidr_block] # Service communication within VPC
      }

      # BGP for Calico
      ingress {
        from_port   = 179
        to_port     = 179
        protocol    = "tcp"
        cidr_blocks = [var.vpc_cidr_block] # Ensure this matches the pod network CIDR
      }

      # Allow VXLAN for Calico (UDP 4789)
      ingress {
        from_port   = 4789
        to_port     = 4789
        protocol    = "udp"
        cidr_blocks = [var.pod_subnet] # Pod network CIDR
      }

      # Allow pod-to-pod communication within the cluster
      ingress {
        from_port   = 0
        to_port     = 65535
        protocol    = "tcp"
        cidr_blocks = [var.pod_subnet] # Pod network CIDR
      }

      # Allow IP-in-IP (used by Calico)
      ingress {
        from_port   = -1
        to_port     = -1
        protocol    = "4" # Protocol 4 is for IP-in-IP
        cidr_blocks = [var.pod_subnet] # Pod network CIDR
      }

      # etcd Communication (Control Plane Only)
      ingress {
        from_port   = 2379
        to_port     = 2380
        protocol    = "tcp"
        cidr_blocks = ["192.168.80.58/32"] # Restrict to control plane's private IP
      }

      egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
      }

      tags = {
        Name = "k8s_sg"
      }
    }

    resource "aws_security_group_rule" "ssh_within_group" {
      type                     = "ingress"
      from_port                = 22
      to_port                  = 22
      protocol                 = "tcp"
      security_group_id        = aws_security_group.k8s_sg.id
      source_security_group_id = aws_security_group.k8s_sg.id
      description              = "Allow SSH within the security group"
    }

    # Generate a TLS private key
    resource "tls_private_key" "k8s_key_pair" {
      algorithm = "RSA"
      rsa_bits  = 2048
    }

    # Key Pair
    resource "aws_key_pair" "k8s_key_pair" {
      key_name   = "my_k8s_key"
      public_key = tls_private_key.k8s_key_pair.public_key_openssh
    }

    # Save the private key locally
    resource "local_file" "save_private_key" {
      filename = "${path.module}/my_k8s_key.pem"
      content  = tls_private_key.k8s_key_pair.private_key_pem
      file_permission = "0600"

    }

    # Output the private key (for reference or debugging)
    output "k8s_private_key" {
      value     = tls_private_key.k8s_key_pair.private_key_pem
      sensitive = true
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
      key_name                    = aws_key_pair.k8s_key_pair.key_name
      private_ip                  = var.controlplane_ip
      user_data                   = data.template_file.controlplane_user_data.rendered


      source_dest_check           = false  # Disable Source/Destination Check

      tags = {
        Name = "controlplane"
      }

      depends_on = [aws_nat_gateway.k8s_nat_gw, aws_key_pair.k8s_key_pair]
          

    }

      # Worker Node Instances
      resource "aws_instance" "worker1" {
        ami                         = var.ami_id
        instance_type               = var.instance_type
        subnet_id                   = aws_subnet.k8s_private_subnet.id
        vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
        key_name                    = aws_key_pair.k8s_key_pair.key_name
        private_ip                  = "192.168.80.59"  # Specify your desired private IP here
        user_data                   = data.template_file.worker1_user_data.rendered

        source_dest_check           = false  # Disable Source/Destination Check

        tags = {
          Name = "worker1"
        }

        depends_on = [aws_nat_gateway.k8s_nat_gw, aws_key_pair.k8s_key_pair]
      
      }

      resource "aws_instance" "worker2" {
        ami                         = var.ami_id
        instance_type               = var.instance_type
        subnet_id                   = aws_subnet.k8s_private_subnet.id
        vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
        key_name                    = aws_key_pair.k8s_key_pair.key_name
        private_ip                  = "192.168.80.60"  # Specify your desired private IP here
        user_data                   = data.template_file.worker2_user_data.rendered

        source_dest_check           = false  # Disable Source/Destination Check

        tags = {
          Name = "worker2"
        }

        depends_on = [aws_nat_gateway.k8s_nat_gw, aws_key_pair.k8s_key_pair]
      
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

    data "template_file" "kubeadm_config" {
      template = file("${path.module}/kubeadm-config.tpl")
      vars = {
        controlplane_ip = var.controlplane_ip
        pod_subnet      = var.pod_subnet
      }
    }

    resource "local_file" "kubeadm_config" {
      filename = "${path.module}/kubeadm-config.yaml"
      content  = data.template_file.kubeadm_config.rendered
    }

    data "template_file" "custom_resources" {
      template = file("${path.module}/custom-resources.tpl")
      vars = {
        pod_subnet    = var.pod_subnet
        encapsulation = var.encapsulation
      }
    }

    resource "local_file" "custom_resources" {
      filename = "${path.module}/custom-resources.yaml"
      content  = data.template_file.custom_resources.rendered
    }

    resource "null_resource" "copy_files_to_bastion" {
      provisioner "local-exec" {
        command = <<-EOT
          sleep 60
          for file in ${join(" ", concat(var.copy_files_to_bastion, [local_file.kubeadm_config.filename, local_file.custom_resources.filename]))}; do
            echo "Copying $file to bastion"
            scp -i "my_k8s_key.pem" -o StrictHostKeyChecking=no "$file" ubuntu@${aws_instance.bastion.public_dns}:~/
          done

        EOT
      }

      depends_on = [aws_instance.bastion, local_file.save_private_key, local_file.kubeadm_config, local_file.custom_resources]
    }

    resource "null_resource" "copy_files_to_controlplane" {
      provisioner "remote-exec" {
        inline = [
          "scp -i my_k8s_key.pem -o StrictHostKeyChecking=no my_k8s_key.pem ubuntu@${aws_instance.controlplane.private_ip}:~/",
          "scp -i my_k8s_key.pem -o StrictHostKeyChecking=no kubeadm-config.yaml ubuntu@${aws_instance.controlplane.private_ip}:~/",
          "scp -i my_k8s_key.pem -o StrictHostKeyChecking=no custom-resources.yaml ubuntu@${aws_instance.controlplane.private_ip}:~/"

        ]

        connection {
          type        = "ssh"
          host        = aws_instance.bastion.public_dns
          user        = "ubuntu"
          private_key = tls_private_key.k8s_key_pair.private_key_pem
        }
      }

      depends_on = [null_resource.copy_files_to_bastion, aws_instance.controlplane, null_resource.wait_for_worker2_setup]
    }




    # Define the local-exec provisioner for each instance to update /etc/hosts
    resource "null_resource" "update_hosts" {
      depends_on = [null_resource.copy_files_to_bastion, aws_instance.bastion, aws_instance.controlplane, aws_instance.worker1, aws_instance.worker2, null_resource.wait_for_worker2_setup]

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

      depends_on = [null_resource.copy_files_to_bastion, aws_instance.worker2, local_file.save_private_key]
    }

    resource "null_resource" "kubeadm_init" {
      
      
      
      
      provisioner "remote-exec" {
        inline = [
          "sudo kubeadm init --config=kubeadm-config.yaml | tee /tmp/kubeadm_output.log",
          # Cluster Initialization Instructions 
          "mkdir -p $HOME/.kube",
          "sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config",
          "sudo chown $(id -u):$(id -g) $HOME/.kube/config",
          # Extract the token from the second line of the kubeadm token list output
          "TOKEN=$(sudo kubeadm token list | awk 'NR==2 {print $1}')",
          # Extract the CA cert hash
          "CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | awk '{print $2}')",
          # Get the API server endpoint (default to control plane private IP)
          "API_SERVER=${aws_instance.controlplane.private_ip}:6443",
          # Construct the join command and save it
          "echo \"sudo kubeadm join $API_SERVER --token $TOKEN --discovery-token-ca-cert-hash sha256:$CERT_HASH\" > /tmp/join_command.sh",
          # Create Calico Tigera Operator
          "kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/tigera-operator.yaml",
          # Apply custom-resources.yaml file
          "kubectl apply -f custom-resources.yaml",
          # Download calicoctl 
          #"wget https://github.com/projectcalico/calico/releases/download/v3.29.0/calicoctl-linux-amd64",
          #"chmod +x ./calicoctl-linux-amd64",
          #"sudo mv calicoctl-linux-amd64 /usr/local/bin/calicoctl",
          # Download k9s
          #"wget https://github.com/derailed/k9s/releases/download/v0.32.7/k9s_linux_amd64.deb && sudo apt install ./k9s_linux_amd64.deb && rm k9s_linux_amd64.deb",
          # Copy join_command.sh to worker nodes and execute
          "for worker in ${aws_instance.worker1.private_ip} ${aws_instance.worker2.private_ip}; do",
          "  scp -i my_k8s_key.pem -o StrictHostKeyChecking=no /tmp/join_command.sh ubuntu@$worker:~/",
          "  ssh -i my_k8s_key.pem -o StrictHostKeyChecking=no ubuntu@$worker 'chmod +x join_command.sh && sudo ./join_command.sh'",
          "done"
        ]

        connection {
          type                = "ssh"
          host                = aws_instance.controlplane.private_ip
          user                = "ubuntu"
          private_key         = tls_private_key.k8s_key_pair.private_key_pem
          bastion_host        = aws_instance.bastion.public_ip
          bastion_user        = "ubuntu"
          bastion_private_key = tls_private_key.k8s_key_pair.private_key_pem
        }
      }

      depends_on = [aws_instance.controlplane, aws_instance.bastion, null_resource.wait_for_worker2_setup, null_resource.copy_files_to_controlplane]
    }