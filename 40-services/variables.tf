# Secrets : uniquement via l'environnement, jamais dans un fichier commite
#   export TF_VAR_cle_ssh="$(cat ~/.ssh/id_cybersadiver.pub)"
#   export TF_VAR_mot_de_passe_invites='<mot de passe console>'

variable "cle_ssh" {
  description = "Cle SSH publique installee dans les invites"
  type        = string
  sensitive   = true
}

variable "mot_de_passe_invites" {
  description = "Mot de passe console des invites (admin pour les VM, root pour les CT)"
  type        = string
  sensitive   = true
}
