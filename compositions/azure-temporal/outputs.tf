# Outputs for the clients of the Temporal VM.
#
#   temporal_address         <public IP>:7233, what clients dial
#   temporal_server_name     the name clients check in the certificate
#   temporal_ca_certificate  the CA clients trust
#   temporal_app_key         the app key (sensitive)
#   public_ip                the VM's public IP, for allow lists
#
# The first three are compositions/azure-runner's temporal_address,
# temporal_server_name and temporal_ca_certificate, with temporal_tls = true and
# temporal_token = the same runner_token. The generated SSH private key and the
# proxy's private key stay in the state.

output "temporal_address" {
  description = "Address clients dial, <public IP>:7233. Pass it to compositions/azure-runner as temporal_address."
  value       = "${module.temporal_vm.public_ip}:7233"
}

output "temporal_server_name" {
  description = "Name in the proxy's certificate, which clients check. Pass it to compositions/azure-runner as temporal_server_name, and set it as the TLS server name in the app."
  value       = local.server_name
}

output "temporal_ca_certificate" {
  description = "PEM of the private CA that signed the proxy's certificate. Not a secret. Pass it to compositions/azure-runner as temporal_ca_certificate."
  value       = tls_self_signed_cert.ca.cert_pem
}

output "temporal_app_key" {
  description = "The app key, also in the vault entry temporal-app-key when key_vault_id is set. The app sends it as \"Bearer <key>\". Sensitive: shown only with terraform output -raw temporal_app_key."
  value       = random_password.app_key.result
  sensitive   = true
}

output "public_ip" {
  description = "The VM's static public IP. It stays when the VM is replaced. Allow it out of your network on TCP 7233 if your egress is filtered."
  value       = module.temporal_vm.public_ip
}
