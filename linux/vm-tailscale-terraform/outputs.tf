# output "tls_private_key" {
#   value     = tls_private_key.kube.private_key_pem
#   sensitive = true
# }

output "ssh_command" {
  value = "ssh ${var.vm_username}@${azurerm_linux_virtual_machine.ts.name}"
}

output "auth_url_command" {
  description = "Command to re-fetch the Tailscale login URL when deployed without Tailscale API credentials."
  value       = "az vm run-command invoke --resource-group ${local.resource_group_name} --name ${azurerm_linux_virtual_machine.ts.name} --command-id RunShellScript --scripts \"tailscale-authurl\" --query \"value[0].message\" -o tsv"
}

output "tailscale_auth_url" {
  description = "Tailscale login URL captured during apply when deployed without Tailscale API credentials."
  value       = try(trimspace(azurerm_virtual_machine_run_command.tailscale_auth_url[0].instance_view[0].output), null)
}
