variable "nom" {
  description = "Nom d'hote du conteneur (minuscules, chiffres, tirets)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.nom))
    error_message = "Nom en minuscules, sans accent."
  }
}

variable "vmid" {
  description = "Identifiant Proxmox du conteneur"
  type        = number
  validation {
    condition     = var.vmid >= 100 && var.vmid < 900
    error_message = "Le VMID doit etre entre 100 et 899."
  }
}

variable "noeud" {
  description = "Noeud prefere du conteneur"
  type        = string
}

variable "modele" {
  description = "Modele LXC, ex. cs-nfs:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
  type        = string
}

variable "cartes" {
  description = "Cartes reseau, dans l'ordre (eth0, eth1...). ip au format CIDR ; passerelle facultative"
  type = list(object({
    pont       = string
    ip         = string
    passerelle = optional(string)
    mtu        = optional(number)
  }))
  validation {
    condition     = length(var.cartes) >= 1
    error_message = "Il faut au moins une carte reseau."
  }
}

variable "groupe_securite" {
  description = "Groupe de securite du pare-feu applique a l'invite"
  type        = string
}

variable "etiquettes" {
  description = "Etiquettes Proxmox (role du service)"
  type        = list(string)
  validation {
    condition     = length(var.etiquettes) >= 1 && alltrue([for e in var.etiquettes : can(regex("^[a-z0-9-]+$", e))])
    error_message = "Au moins une etiquette de role, en minuscules."
  }
}

variable "stockage" {
  type    = string
  default = "local-zfs"
}

variable "pool" {
  type    = string
  default = "cs-services"
}

variable "cpu" {
  type    = number
  default = 1
}

variable "memoire" {
  description = "Memoire en Mio"
  type        = number
  default     = 512
}

variable "disque" {
  description = "Taille du disque racine en Gio"
  type        = number
  default     = 4
}

variable "dns" {
  type = list(string)
}

variable "domaine" {
  type = string
}

variable "cle_ssh" {
  description = "Cle SSH publique installee pour root (indispensable pour Ansible)"
  type        = string
  sensitive   = true
}

variable "mot_de_passe" {
  description = "Mot de passe root pour la console"
  type        = string
  sensitive   = true
}
