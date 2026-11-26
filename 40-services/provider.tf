# Provider commun (ecrit par le binome B) : remplacer ce fichier par le leur s'il differe.
# Authentification : jeton d'API exporte dans le terminal du pilote, jamais dans Git :
#   export PROXMOX_VE_API_TOKEN='tofu@pve!tofu=xxxxxxxx-xxxx-...'
terraform {
  required_version = ">= 1.8.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.99.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://${local.fiche.noeuds.pve1.ip}:8006/"
  insecure = true # certificat autosigne de Proxmox
}
