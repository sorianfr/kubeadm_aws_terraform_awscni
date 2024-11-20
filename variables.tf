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