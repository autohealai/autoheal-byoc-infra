output "fqdns" {
  description = "Fully qualified names of the records, keyed like var.records."
  value = merge(
    { for k, r in azurerm_dns_a_record.this : k => r.fqdn },
    { for k, r in azurerm_private_dns_a_record.this : k => r.fqdn },
  )
}
