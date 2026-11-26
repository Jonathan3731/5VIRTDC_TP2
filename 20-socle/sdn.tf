resource "proxmox_sdn_applier" "finalizer" {}

resource "proxmox_sdn_zone_vxlan" "back" {
  id         = "back"
  peers      = [for _, n in local.noeuds : n.ip]
  mtu        = local.mtu_back
  depends_on = [proxmox_sdn_applier.finalizer]
}

resource "proxmox_sdn_vnet" "vback" {
  id   = local.fiche.back.pont
  zone = proxmox_sdn_zone_vxlan.back.id
  tag  = 30030
}

resource "proxmox_sdn_subnet" "sub_back" {
  cidr = local.fiche.back.reseau
  vnet = proxmox_sdn_vnet.vback.id
}

resource "proxmox_sdn_zone_simple" "labo" {
  id         = "labo"
  ipam       = "pve"
  dhcp       = "dnsmasq"
  depends_on = [proxmox_sdn_applier.finalizer]
}

resource "proxmox_sdn_vnet" "vlabo" {
  id   = "vlabo"
  zone = proxmox_sdn_zone_simple.labo.id
}

resource "proxmox_sdn_subnet" "sub_labo" {
  cidr    = "10.0.99.0/24"
  vnet    = proxmox_sdn_vnet.vlabo.id
  gateway = "10.0.99.1"
  snat    = true

  dhcp_range = {
    start_address = "10.0.99.100"
    end_address   = "10.0.99.150"
  }
}

resource "proxmox_sdn_applier" "sdn" {
  depends_on = [
    proxmox_sdn_zone_vxlan.back,
    proxmox_sdn_vnet.vback,
    proxmox_sdn_subnet.sub_back,
    proxmox_sdn_zone_simple.labo,
    proxmox_sdn_vnet.vlabo,
    proxmox_sdn_subnet.sub_labo,
  ]
}