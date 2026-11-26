variable "mot_de_passe_initial" {
  description = "Mot de passe initial des administrateurs et de direction@pve"
  type        = string
  sensitive   = true

}

variable "pare_feu_actif" {
  description = "Active ou désactive le pare-feu du datacenter"
  type        = bool
  default     = true
}