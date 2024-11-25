
output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "controlplane_private_ip" {
  value = aws_instance.controlplane.private_ip
}

output "worker1_private_ip" {
  value = aws_instance.worker1.private_ip
}

output "worker2_private_ip" {
  value = aws_instance.worker2.private_ip
}

