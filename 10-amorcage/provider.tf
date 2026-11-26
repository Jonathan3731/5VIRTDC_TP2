terraform {
  required_version = ">= 1.8"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.123.1"
    }
  }
}

locals {
  fiche    = yamldecode(file("${path.module}/../fiche.yml"))
  noeuds   = local.fiche.noeuds
  n1       = values(local.noeuds)[0]
  mtu_back = local.fiche.front.mtu - 50
}

provider "proxmox" {
  endpoint = "https://${local.n1.ip}:8006/"
  username = "root@pam"
  insecure = true
}