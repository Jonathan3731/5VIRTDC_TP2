output "invites" {
  description = "VMID, noeud prefere et adresses des invites (utile pour Ansible)"
  value = {
    cs-dns = { vmid = module.cs_dns.vmid, noeud = local.invites["cs-dns"].preferee, adresses = module.cs_dns.adresses }
    cs-web = { vmid = module.cs_web.vmid, noeud = local.invites["cs-web"].preferee, adresses = module.cs_web.adresses }
    cs-bdd = { vmid = module.cs_bdd.vmid, noeud = local.invites["cs-bdd"].preferee, adresses = module.cs_bdd.adresses }
  }
}

output "replications" {
  value = keys(local.replications)
}
