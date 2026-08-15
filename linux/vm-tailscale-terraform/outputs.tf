# output "tls_private_key" {
#   value     = tls_private_key.kube.private_key_pem
#   sensitive = true
# }

output "ssh_command" {
  value = "ssh ${var.vm_username}@${azurerm_linux_virtual_machine.ts.name}"
}

output "auth_url_command" {
  description = "Fetch the Tailscale login URL when deployed without Tailscale API credentials."
  value       = "az vm run-command invoke --resource-group ${local.resource_group_name} --name ${azurerm_linux_virtual_machine.ts.name} --command-id RunShellScript --scripts \"tailscale-authurl\" --query \"value[0].message\" -o tsv"
}
