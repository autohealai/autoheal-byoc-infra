# Outputs for the clients of the Temporal VM.
#
#   temporal_address         dns_name or the IP, with :7233: what clients dial
#   temporal_ip              the load balancer's static IP, for DNS and allow lists
#   temporal_server_name     the name clients check in the certificate
#   temporal_ca_certificate  the private CA clients trust; null with certificate_name
#   key_vault_secret_names   the vault entries the app and the VM read
#
# temporal_address, temporal_server_name and temporal_ca_certificate are
# compositions/azure-runner's inputs of the same names, with temporal_tls =
# true, temporal_token = the runner-token entry and temporal_ip = temporal_ip.
# The keys are not outputs: they are in the vault. The generated SSH private
# key, the CA's private key and the gate's private key stay in the state.

output "temporal_address" {
  description = "Address clients dial: dns_name, or the load balancer's IP, with :7233. Pass it to compositions/azure-runner as temporal_address."
  value       = "${var.dns_name != "" ? var.dns_name : module.temporal_vm.public_ip}:7233"
}

output "temporal_ip" {
  description = "Static public IP of the load balancer. It stays when the VM is reimaged. Point dns_name at it, add it to the install vault's firewall (see the README), pass it to compositions/azure-runner as temporal_ip, and allow it out of your network on TCP 7233 if your egress is filtered."
  value       = module.temporal_vm.public_ip
}

output "temporal_server_name" {
  description = "Name in the gate's certificate, which clients check: dns_name, or temporal.autoheal.internal. Pass it to compositions/azure-runner as temporal_server_name, and set it as the TLS server name in the app."
  value       = local.server_name
}

output "temporal_ca_certificate" {
  description = "PEM of the private CA that signed the gate's certificate, also in the vault entry temporal-ca. Not a secret. Null with certificate_name, whose CA the clients already trust. Pass it to compositions/azure-runner as temporal_ca_certificate."
  value       = local.private_ca ? tls_self_signed_cert.ca[0].cert_pem : null
}

output "key_vault_secret_names" {
  description = "Vault entries in key_vault_id: the api-server key, the agents key, the runner key, the gate's certificate and, with the private CA, the CA."
  value       = local.vm_secrets
}

output "vmss_name" {
  description = "Name of the Temporal scale set, for az vmss run-command and az vmss reimage."
  value       = module.temporal_vm.vmss_name
}

output "resource_group_name" {
  description = "Resource group of the VM."
  value       = local.rg
}

output "identity_principal_id" {
  description = "Principal ID of the VM's identity, which reads the vault entries."
  value       = module.temporal_vm.identity_principal_id
}
