resource "proxmox_virtual_environment_pool" "cs_services" {
  pool_id = local.fiche.pool
  comment = "Pool des services CyberSadiver"
}

resource "proxmox_virtual_environment_group" "admins_cs" {
  group_id = "admins-cs"
  comment  = "Administrateurs CyberSadiver"
}

resource "proxmox_virtual_environment_group" "direction_cs" {
  group_id = "direction-cs"
  comment  = "Direction CyberSadiver"
}

resource "proxmox_virtual_environment_acl" "admins_cs" {
  group_id  = proxmox_virtual_environment_group.admins_cs.group_id
  path      = "/"
  role_id   = "Administrator"
  propagate = true
}

resource "proxmox_virtual_environment_acl" "direction_cs" {
  group_id  = proxmox_virtual_environment_group.direction_cs.group_id
  path      = "/pool/${proxmox_virtual_environment_pool.cs_services.pool_id}"
  role_id   = "PVEAuditor"
  propagate = true
}

resource "proxmox_virtual_environment_user" "admins" {
  for_each = toset(local.fiche.administrateurs)

  user_id  = "${each.key}@pve"
  password = var.mot_de_passe_initial
  groups   = [proxmox_virtual_environment_group.admins_cs.group_id]

  lifecycle {
    ignore_changes = [password]
  }
}

resource "proxmox_virtual_environment_user" "direction" {
  user_id  = "direction@pve"
  password = var.mot_de_passe_initial
  groups   = [proxmox_virtual_environment_group.direction_cs.group_id]

  lifecycle {
    ignore_changes = [password]
  }
}

resource "proxmox_virtual_environment_user" "supervision" {
  user_id = "supervision@pve"
  comment = "Compte supervision lecture seule"
}

resource "proxmox_virtual_environment_user_token" "supervision_lecture" {
  user_id               = proxmox_virtual_environment_user.supervision.user_id
  token_name            = "lecture"
  privileges_separation = true
}

resource "proxmox_virtual_environment_acl" "supervision_user" {
  user_id   = proxmox_virtual_environment_user.supervision.user_id
  path      = "/"
  role_id   = "PVEAuditor"
  propagate = true
}

resource "proxmox_virtual_environment_acl" "supervision_token" {
  token_id  = proxmox_virtual_environment_user_token.supervision_lecture.id
  path      = "/"
  role_id   = "PVEAuditor"
  propagate = true
}

resource "proxmox_virtual_environment_acl" "tofu_vmbr0_user" {
  user_id   = "tofu@pve"
  path      = "/sdn/zones/localnetwork/${local.fiche.front.pont}"
  role_id   = "CS-Tofu"
  propagate = true
}

resource "proxmox_virtual_environment_acl" "tofu_vmbr0_token" {
  token_id  = "tofu@pve!tofu"
  path      = "/sdn/zones/localnetwork/${local.fiche.front.pont}"
  role_id   = "CS-Tofu"
  propagate = true
}