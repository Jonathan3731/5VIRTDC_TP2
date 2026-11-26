terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.123.1"
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.nom
  vm_id     = var.vmid
  node_name = var.noeud
  pool_id   = var.pool
  tags      = sort(var.etiquettes)

  on_boot         = true
  started         = true
  stop_on_destroy = true

  # Clone complet : un clone lie empeche la replication.
  # Le modele est sur pve1 : le provider clone sur pve1 puis migre vers var.noeud.
  clone {
    vm_id        = var.modele.vmid
    node_name    = var.modele.noeud
    datastore_id = var.stockage
    full         = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cpu
    type  = "host"
  }

  memory {
    dedicated = var.memoire
  }

  disk {
    interface    = var.disque_interface
    datastore_id = var.stockage
    size         = var.disque
  }

  dynamic "network_device" {
    for_each = var.cartes
    content {
      bridge   = network_device.value.pont
      model    = "virtio"
      firewall = true
      mtu      = network_device.value.mtu
    }
  }

  initialization {
    # Lecteur Cloud-Init sur ZFS, sinon la replication est refusee
    datastore_id = var.stockage

    dynamic "ip_config" {
      for_each = var.cartes
      content {
        ipv4 {
          address = ip_config.value.ip
          gateway = ip_config.value.passerelle
        }
      }
    }

    dns {
      domain  = var.domaine
      servers = var.dns
    }

    user_account {
      username = var.utilisateur
      keys     = [trimspace(var.cle_ssh)]
      password = var.mot_de_passe
    }
  }

  # HA peut deplacer la VM : sans cela, un plan apres bascule propose de la detruire
  lifecycle {
    ignore_changes = [node_name]
  }
}

# Pare-feu de l'invite : politique d'entree DROP + groupe de securite
resource "proxmox_virtual_environment_firewall_options" "this" {
  node_name     = var.noeud
  vm_id         = proxmox_virtual_environment_vm.this.vm_id
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "this" {
  node_name = var.noeud
  vm_id     = proxmox_virtual_environment_vm.this.vm_id

  rule {
    security_group = var.groupe_securite
    comment        = "Groupe ${var.groupe_securite}"
  }
}
