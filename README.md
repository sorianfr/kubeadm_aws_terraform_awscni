
## Installation

1. Clone this repository to your local machine:

   ```bash
   git clone https://github.com/sorianfr/kubeadm_aws_terraform.git

2. Download and Install Terraform
   ```bash
   curl -o terraform.zip https://releases.hashicorp.com/terraform/1.5.6/terraform_1.5.6_linux_amd64.zip && unzip terraform.zip && sudo mv terraform /usr/local/bin/

3. AWS Configure
   
4. Initialize and Apply Terraform

scp -i "my_k8s_key.pem" alpine-kube2.yaml ubuntu@192.168.80.58:~/ 
scp -i "my_k8s_key.pem" alpine-kube1.yaml ubuntu@192.168.80.58:~/
scp -i "my_k8s_key.pem" kubeadm-config.yaml ubuntu@192.168.80.58:~/
scp -i "my_k8s_key.pem" kubeadm-config-join.yaml ubuntu@192.168.80.59:~/
scp -i "my_k8s_key.pem" kubeadm-config-join.yaml ubuntu@192.168.80.60:~/

sudo kubeadm init --config=kubeadm-config.yaml
