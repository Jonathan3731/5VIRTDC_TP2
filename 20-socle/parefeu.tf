resource "proxmox_virtual_environment_firewall_alias" "net_lan" {
  name    = "net_lan"
  cidr    = local.fiche.front.reseau
  comment = "Réseau de gestion et front"
}

resource "proxmox_virtual_environment_firewall_alias" "net_back" {
  name    = "net_back"
  cidr    = local.fiche.back.reseau
  comment = "Réseau privé VXLAN back"
}

resource "proxmox_virtual_environment_firewall_ipset" "management" {
  name    = "management"
  comment = "Postes d'administration et réseau du cluster"

  dynamic "cidr" {
    for_each = toset(local.fiche.postes_admin)
    content {
      name    = can(regex("/", cidr.value)) ? cidr.value : "${cidr.value}/32"
      comment = "Poste administration"
    }
  }

  cidr {
    name    = local.fiche.front.reseau
    comment = "Réseau cluster LAN"
  }
}

resource "proxmox_virtual_environment_firewall_ipset" "noeuds" {
  name    = "noeuds"
  comment = "Adresses de gestion des nœuds"

  dynamic "cidr" {
    for_each = local.noeuds
    content {
      name    = "${cidr.value.ip}/32"
      comment = cidr.key
    }
  }
}

resource "proxmox_virtual_environment_firewall_rules" "cluster" {
  depends_on = [
    proxmox_virtual_environment_firewall_alias.net_lan,
    proxmox_virtual_environment_firewall_ipset.management,
    proxmox_virtual_environment_firewall_ipset.noeuds,
  ]

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "4789"
    source  = "net_lan"
    comment = "VXLAN vback"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "111,2049"
    source  = "net_lan"
    comment = "NFS cs-nfs"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "67,68"
    iface   = "vlabo"
    comment = "DHCP dnsmasq zone labo"
    enabled = true
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "sg_web" {
  name       = "sg-web"
  comment    = "Serveur web frontal et apt-cacher-ng"
  depends_on = [proxmox_virtual_environment_firewall_ipset.noeuds]

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    comment = "HTTP entrant"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "icmp"
    comment = "Ping"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "+noeuds"
    comment = "SSH rebond depuis les nœuds"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "3142"
    source  = "${local.fiche.invites.cs_bdd}/32"
    comment = "Proxy apt depuis cs-bdd"
    enabled = true
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "sg_dns" {
  name    = "sg-dns"
  comment = "Serveur DNS Unbound"

  depends_on = [
    proxmox_virtual_environment_firewall_alias.net_lan,
    proxmox_virtual_environment_firewall_ipset.noeuds,
  ]

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "53"
    source  = "net_lan"
    comment = "DNS UDP depuis net_lan"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "53"
    source  = "net_lan"
    comment = "DNS TCP depuis net_lan"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "+noeuds"
    comment = "SSH rebond depuis les nœuds"
    enabled = true
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "sg_bdd" {
  name    = "sg-bdd"
  comment = "Base de données MariaDB"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "3306"
    source  = "${local.fiche.invites.cs_web_back}/32"
    comment = "MySQL depuis cs-web"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "${local.fiche.invites.cs_web_back}/32"
    comment = "SSH rebond depuis cs-web"
    enabled = true
  }
}

resource "proxmox_virtual_environment_cluster_firewall" "datacenter" {
  enabled = var.pare_feu_actif

  depends_on = [
    proxmox_virtual_environment_firewall_ipset.management,
    proxmox_virtual_environment_firewall_rules.cluster,
    proxmox_virtual_environment_cluster_firewall_security_group.sg_web,
    proxmox_virtual_environment_cluster_firewall_security_group.sg_dns,
    proxmox_virtual_environment_cluster_firewall_security_group.sg_bdd,
  ]
}
