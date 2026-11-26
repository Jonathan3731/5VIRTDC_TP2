variable "nom" {
  description = "Nom de la VM (minuscules, chiffres, tirets)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.nom))
    error_message = "Nom en minuscules, sans accent."
  }
}

variable "vmid" {
  description = "Identifiant Proxmox de la VM"
  type        = number
  validation {
    condition     = var.vmid >= 100 && var.vmid < 900
    error_message = "Le VMID doit etre entre 100 et 899."
  }
}

variable "noeud" {
  description = "Noeud prefere de la VM"
  type        = string
}

variable "modele" {
  description = "Modele a cloner : son VMID et le noeud qui le porte"
  type        = object({ vmid = number, noeud = string })
}

variable "cartes" {
  description = "Cartes reseau, dans l'ordre. ip au format CIDR ; passerelle facultative ; mtu = 1 pour heriter du pont"
  type = list(object({
    pont       = string
    ip         = string
    passerelle = optional(string)
    mtu        = optional(number, 1)
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
  description = "Stockage des disques (ZFS pour la replication)"
  type        = string
  default     = "local-zfs"
}

variable "pool" {
  description = "Pool Proxmox de l'invite"
  type        = string
  default     = "cs-services"
}

variable "cpu" {
  type    = number
  default = 2
}

variable "memoire" {
  description = "Memoire en Mio"
  type        = number
  default     = 1024
}

variable "disque" {
  description = "Taille du disque systeme en Gio"
  type        = number
  default     = 9
}

variable "disque_interface" {
  description = "Interface du disque du modele (scsi0, virtio0...)"
  type        = string
  default     = "scsi0"
}

variable "dns" {
  type = list(string)
}

variable "domaine" {
  type = string
}

variable "utilisateur" {
  type    = string
  default = "admin"
}

variable "cle_ssh" {
  description = "Cle SSH publique de l'utilisateur"
  type        = string
  sensitive   = true
}

variable "mot_de_passe" {
  description = "Mot de passe pour la console"
  type        = string
  sensitive   = true
}
