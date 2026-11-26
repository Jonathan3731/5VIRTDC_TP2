output "pool_services" {
  value = proxmox_virtual_environment_pool.cs_services.pool_id
}

output "security_groups" {
  value = [
    proxmox_virtual_environment_cluster_firewall_security_group.sg_web.name,
    proxmox_virtual_environment_cluster_firewall_security_group.sg_dns.name,
    proxmox_virtual_environment_cluster_firewall_security_group.sg_bdd.name,
  ]
}

output "jeton_supervision" {
  value     = proxmox_virtual_environment_user_token.supervision_lecture.value
  sensitive = true
}