terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.128.1"
    }
  }
}

resource "proxmox_virtual_environment_container" "this" {
  vm_id        = var.vmid
  node_name    = var.noeud
  pool_id      = var.pool
  tags         = sort(var.etiquettes)
  unprivileged = true

  start_on_boot = true
  started       = true

  features {
    nesting = true
  }

  operating_system {
    template_file_id = var.modele
    type             = "debian"
  }

  cpu {
    cores = var.cpu
  }

  memory {
    dedicated = var.memoire
    swap      = 0
  }

  # Disque racine sur ZFS, sinon la replication est refusee
  disk {
    datastore_id = var.stockage
    size         = var.disque
  }

  dynamic "network_interface" {
    for_each = var.cartes
    content {
      name     = "eth${network_interface.key}"
      bridge   = network_interface.value.pont
      firewall = true
      mtu      = network_interface.value.mtu
    }
  }

  initialization {
    hostname = var.nom

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

    # Compte root : cle SSH (pour Ansible) + mot de passe console
    user_account {
      keys     = [trimspace(var.cle_ssh)]
      password = var.mot_de_passe
    }
  }

  lifecycle {
    ignore_changes = [node_name]
  }
}

resource "proxmox_virtual_environment_firewall_options" "this" {
  node_name     = var.noeud
  container_id  = proxmox_virtual_environment_container.this.vm_id
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "this" {
  node_name    = var.noeud
  container_id = proxmox_virtual_environment_container.this.vm_id

  rule {
    security_group = var.groupe_securite
    comment        = "Groupe ${var.groupe_securite}"
  }
}
