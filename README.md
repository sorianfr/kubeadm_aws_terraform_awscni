
## Installation

1. Clone this repository to your local machine:

   ```bash
   git clone https://github.com/sorianfr/kubeadm_aws_terraform.git

2. Download and Install Terraform
   ```bash
   curl -o terraform.zip https://releases.hashicorp.com/terraform/1.5.6/terraform_1.5.6_linux_amd64.zip && unzip terraform.zip && sudo mv terraform /usr/local/bin/

3. AWS Configure
   
4. Initialize and Apply Terraform
   ```bash
   terraform init
   terraform apply -var="encapsulation=None"

5. SSH inton Controlplane and start kubeadm
   ```bash
   
