variable "region" {
  default = "us-east-1"
}
variable "instance_type" {
  default = "t3.medium"
}

# AMI ID Variable
variable "ami_id" {
  description = "AMI ID for the Kubernetes nodes"
  type        = string
  default     = "ami-0866a3c8686eaeeba"  # Ubuntu 20.04 in us-east-1; change for your region/OS preference
}

variable "controlplane_hostname" {
  default = "controlplane"
}

variable "worker1_hostname" {
  default = "worker1"
}

variable "worker2_hostname" {
  default = "worker2"
}


variable "ssh_user" {
  default = "ubuntu"
}



variable "copy_files_to_bastion" {
  default = [
    "my_k8s_key.pem"
  ]
}

variable "controlplane_ip" {
  description = "The private IP address of the control plane"
  type        = string
  default     = "192.168.80.58"
}

variable "vpc_cidr_block" {
  description = "The CIDR for pod networking"
  type        = string
  default     = "192.168.0.0/16"
}


variable "pod_subnet" {
  description = "The CIDR for pod networking"
  type        = string
  default     = "10.244.0.0/16"
}

variable "encapsulation" {
  description = "The Encapsulatin method used by Calico"
  type        = string
  default     = "VXLANCrossSubnet"
}