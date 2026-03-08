output "instance_ids" {
  description = "EC2 instance IDs by instance key."
  value       = { for k, inst in aws_instance.windows : k => inst.id }
}

output "public_ipv4_by_instance" {
  description = "Public IPv4 by instance key (EIP if associated, else instance public IP)."
  value       = local.effective_public_ipv4_by_instance
}

output "public_dns_by_instance" {
  description = "Public DNS hostnames by instance key."
  value       = { for k, inst in aws_instance.windows : k => inst.public_dns }
}

output "ipv6_addresses_by_instance" {
  description = "IPv6 addresses by instance key."
  value       = { for k, inst in aws_instance.windows : k => inst.ipv6_addresses }
}

output "eip_allocation_ids_by_instance" {
  description = "Effective EIP allocation IDs by instance key (null when no EIP)."
  value       = local.eip_allocation_id_by_instance
}

output "rdp_endpoints_by_instance" {
  description = "RDP endpoints by instance key."
  value = {
    for k, ip in local.effective_public_ipv4_by_instance : k => (
      local.instances[k].enable_rdp_final && ip != null ? "${ip}:3389" : null
    )
  }
}

output "access_modes_by_instance" {
  description = "Effective access mode by instance key."
  value       = { for k, cfg in local.instances : k => cfg.effective_access_mode }
}

output "ssm_targets" {
  description = "SSM targets by instance key (only for instances with SSM access enabled)."
  value       = { for k, inst in aws_instance.windows : k => inst.id if local.instances[k].enable_ssm }
}

output "password_retrieval_commands_by_instance" {
  description = "CLI command to decrypt Windows Administrator password by instance key when key pair is configured."
  value = {
    for k, inst in aws_instance.windows : k => (
      (local.instances[k].create_key_pair || local.instances[k].key_pair_name != null) ?
      "aws ec2 get-password-data --region ${var.aws_region} --instance-id ${inst.id} --priv-launch-key /path/to/${local.instances[k].key_pair_name}.pem --query PasswordData --output text" :
      "No key pair configured. Prefer SSM for access, or set key_pair_name for this instance and re-apply."
    )
  }
}

output "managed_key_pair_names_by_instance" {
  description = "Managed key pair names created by Terraform."
  value       = { for k, kp in aws_key_pair.windows : k => kp.key_name }
}

output "managed_private_keys_pem_by_instance" {
  description = "Managed private keys in PEM format for key pairs created by Terraform."
  value       = { for k, key in tls_private_key.windows : k => key.private_key_pem }
  sensitive   = true
}

output "windows_password_data_encrypted_by_instance" {
  description = "Encrypted Windows password data by instance key."
  value       = { for k, inst in aws_instance.windows : k => inst.password_data }
  sensitive   = true
}

output "bootstrap_artifact_path" {
  description = "Path on each instance where bootstrap version/report artifacts are written."
  value       = "C:\\bootstrap\\tooling_versions.json"
}

# Backward-compatible single-instance style outputs for the selected primary instance key.
output "instance_id" {
  description = "Primary instance ID."
  value       = aws_instance.windows[local.primary_instance_key].id
}

output "public_ipv4" {
  description = "Primary instance public IPv4."
  value       = local.effective_public_ipv4_by_instance[local.primary_instance_key]
}

output "public_dns" {
  description = "Primary instance public DNS hostname."
  value       = aws_instance.windows[local.primary_instance_key].public_dns
}

output "ipv6_addresses" {
  description = "Primary instance IPv6 addresses."
  value       = aws_instance.windows[local.primary_instance_key].ipv6_addresses
}

output "rdp_endpoint" {
  description = "Primary instance RDP endpoint."
  value       = local.instances[local.primary_instance_key].enable_rdp_final && local.effective_public_ipv4_by_instance[local.primary_instance_key] != null ? "${local.effective_public_ipv4_by_instance[local.primary_instance_key]}:3389" : null
}

output "eip_allocation_id_effective" {
  description = "Primary instance associated EIP allocation ID, if any."
  value       = local.eip_allocation_id_by_instance[local.primary_instance_key]
}

output "ssm_target" {
  description = "Primary instance SSM target."
  value       = local.instances[local.primary_instance_key].enable_ssm ? aws_instance.windows[local.primary_instance_key].id : null
}

output "password_retrieval_command" {
  description = "Primary instance password retrieval command."
  value       = (local.instances[local.primary_instance_key].create_key_pair || local.instances[local.primary_instance_key].key_pair_name != null) ? "aws ec2 get-password-data --region ${var.aws_region} --instance-id ${aws_instance.windows[local.primary_instance_key].id} --priv-launch-key /path/to/${local.instances[local.primary_instance_key].key_pair_name}.pem --query PasswordData --output text" : "No key pair configured. Prefer SSM for access, or set key_pair_name and re-apply."
}

output "windows_password_data_encrypted" {
  description = "Primary instance encrypted Windows password data."
  value       = aws_instance.windows[local.primary_instance_key].password_data
  sensitive   = true
}

output "managed_private_key_pem" {
  description = "Primary instance managed private key PEM when create_key_pair=true."
  value       = local.instances[local.primary_instance_key].create_key_pair ? tls_private_key.windows[local.primary_instance_key].private_key_pem : null
  sensitive   = true
}
