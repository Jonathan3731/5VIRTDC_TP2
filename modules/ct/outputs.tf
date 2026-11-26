output "vmid" {
  value = proxmox_virtual_environment_container.this.vm_id
}

output "nom" {
  value = var.nom
}

output "adresses" {
  description = "Adresses configurees, dans l'ordre des cartes"
  value       = [for c in var.cartes : split("/", c.ip)[0]]
}
