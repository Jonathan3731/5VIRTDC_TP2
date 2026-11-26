# Couche 40 : les trois services de CyberSadiver

# cs-dns : CT 101 sur pve1, 512 Mio, 4 Gio, front seulement
module "cs_dns" {
  source = "../modules/ct"

  nom    = "cs-dns"
  vmid   = local.invites["cs-dns"].vmid
  noeud  = local.invites["cs-dns"].preferee
  modele = local.modele_lxc

  memoire = 512
  disque  = 4

  cartes = [
    {
      pont       = local.front.pont
      ip         = "${local.ip.cs_dns}/${local.prefixe_front}"
      passerelle = local.front.passerelle
    },
  ]

  groupe_securite = local.groupes.dns
  etiquettes      = ["cyber", "dns"]
  stockage        = local.fiche.stockage
  pool            = local.fiche.pool
  dns             = [local.front.dns]
  domaine         = local.fiche.domaine
  cle_ssh         = var.cle_ssh
  mot_de_passe    = var.mot_de_passe_invites
}

# cs-web : VM 102 sur pve2, deux cartes (front + vback sans passerelle), disque 9 Gio
module "cs_web" {
  source = "../modules/vm"

  nom    = "cs-web"
  vmid   = local.invites["cs-web"].vmid
  noeud  = local.invites["cs-web"].preferee
  modele = local.fiche.modele_vm

  memoire = 1024
  disque  = 9 # 3 Gio du modele + 6

  cartes = [
    {
      pont       = local.front.pont
      ip         = "${local.ip.cs_web}/${local.prefixe_front}"
      passerelle = local.front.passerelle
    },
    {
      pont = local.back.pont
      ip   = "${local.ip.cs_web_back}/${local.prefixe_back}"
      mtu  = 1 # herite du pont vback (1450)
    },
  ]

  groupe_securite = local.groupes.web
  etiquettes      = ["cyber", "web"]
  stockage        = local.fiche.stockage
  pool            = local.fiche.pool
  dns             = [local.front.dns]
  domaine         = local.fiche.domaine
  cle_ssh         = var.cle_ssh
  mot_de_passe    = var.mot_de_passe_invites
}

# cs-bdd : CT 103 sur pve3, 1 Gio, 8 Gio, une seule carte sur vback
module "cs_bdd" {
  source = "../modules/ct"

  nom    = "cs-bdd"
  vmid   = local.invites["cs-bdd"].vmid
  noeud  = local.invites["cs-bdd"].preferee
  modele = local.modele_lxc

  memoire = 1024
  disque  = 8

  cartes = [
    {
      pont = local.back.pont
      ip   = "${local.ip.cs_bdd}/${local.prefixe_back}"
      mtu  = local.back.mtu
    },
  ]

  groupe_securite = local.groupes.bdd
  etiquettes      = ["bdd", "cyber"]
  stockage        = local.fiche.stockage
  pool            = local.fiche.pool
  dns             = [local.front.dns]
  domaine         = local.fiche.domaine
  cle_ssh         = var.cle_ssh
  mot_de_passe    = var.mot_de_passe_invites
}
