resource "proxmox_download_file" "debian13_cloud" {
  content_type = "import"
  datastore_id = local.fiche.stockage_partage
  node_name    = local.fiche.modele_vm.noeud
  url          = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  file_name    = "debian-13-genericcloud-amd64.qcow2"
  overwrite    = false
}

resource "proxmox_virtual_environment_vm" "modele" {
  vm_id       = local.fiche.modele_vm.vmid
  name        = "tpl-debian13"
  node_name   = local.fiche.modele_vm.noeud
  description = "Modèle Debian 13 Cloud-Init"

  template      = true
  started       = false
  scsi_hardware = "virtio-scsi-single"

  agent {
    enabled = true
  }

  cpu {
    type  = "x86-64-v2-AES"
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = local.fiche.stockage
    import_from  = proxmox_download_file.debian13_cloud.id
    interface    = "scsi0"
    size         = 10
  }

  network_device {
    bridge = local.fiche.front.pont
    model  = "virtio"
  }

  initialization {
    datastore_id        = local.fiche.stockage
    vendor_data_file_id = "${local.fiche.stockage_partage}:snippets/vendor-agent.yml"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
}