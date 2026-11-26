resource "proxmox_storage_nfs" "cs_nfs" {
  id      = local.fiche.stockage_partage
  server  = local.noeuds["pve3"].ip
  export  = "/rpool/nfs"
  options = "vers=4.2"
  content = ["backup", "import", "iso", "snippets", "vztmpl"]
}

resource "proxmox_download_file" "vztmpl_debian" {
  content_type = "vztmpl"
  datastore_id = proxmox_storage_nfs.cs_nfs.id
  node_name    = local.fiche.modele_vm.noeud
  url          = "http://download.proxmox.com/images/system/${local.fiche.lxc_template}"
  overwrite    = false
}
 