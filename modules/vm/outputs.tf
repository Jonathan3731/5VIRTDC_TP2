output "vmid" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "nom" {
  value = proxmox_virtual_environment_vm.this.name
}

output "adresses" {
  description = "Adresses configurees, dans l'ordre des cartes"
  value       = [for c in var.cartes : split("/", c.ip)[0]]
}
