# Toutes les valeurs du TP viennent de fiche.yml (copie non commitee de fiche.exemple.yml)
locals {
  fiche  = yamldecode(file("${path.module}/../fiche.yml"))
  noeuds = local.fiche.noeuds
  front  = local.fiche.front
  back   = local.fiche.back
  ip     = local.fiche.invites

  prefixe_front = split("/", local.front.reseau)[1] # 16
  prefixe_back  = split("/", local.back.reseau)[1]  # 24

  modele_lxc = "${local.fiche.stockage_partage}:vztmpl/${local.fiche.lxc_template}"

  # Groupes de securite crees par le binome B (couche 20-socle) : aligner les noms
  groupes = {
    dns = "gs-dns"
    web = "gs-web"
    bdd = "gs-bdd"
  }
}
