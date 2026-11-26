locals {

  outils = {

    tofu = "CS-Tofu"

    ansible = "PVEAuditor"

  }

}

resource "proxmox_virtual_environment_role" "cs_tofu" {

  role_id = "CS-Tofu"

  privileges = [

    # Pools

    "Pool.Allocate",

    "Pool.Audit",

    # Datastores

    "Datastore.Allocate",

    "Datastore.AllocateSpace",

    "Datastore.AllocateTemplate",

    "Datastore.Audit",

    # SDN (dont SDN.Use pour le clonage)

    "SDN.Allocate",

    "SDN.Audit",

    "SDN.Use",

    # VM et conteneurs

    "VM.Allocate",

    "VM.Audit",

    "VM.Backup",

    "VM.Clone",

    "VM.Config.CDROM",

    "VM.Config.CPU",

    "VM.Config.Cloudinit",

    "VM.Config.Disk",

    "VM.Config.HWType",

    "VM.Config.Memory",

    "VM.Config.Network",

    "VM.Config.Options",

    "VM.Migrate",

    "VM.PowerMgmt",

    # Système et pare-feu

    "Sys.Audit",

    "Sys.Modify",

    # Utilisateurs, groupes et permissions

    "User.Modify",

    "Group.Allocate",

    "Permissions.Modify",

  ]

}

resource "proxmox_virtual_environment_user" "outils" {

  for_each = local.outils

  user_id = "${each.key}@pve"

  comment = "Compte outil ${each.key}"

}

resource "proxmox_virtual_environment_user_token" "jetons" {

  for_each = local.outils

  user_id = proxmox_virtual_environment_user.outils[each.key].user_id

  token_name = each.key

  privileges_separation = true

}

resource "proxmox_virtual_environment_acl" "acl_users" {

  for_each = local.outils

  user_id = proxmox_virtual_environment_user.outils[each.key].user_id

  path = "/"

  role_id = each.value

  propagate = true

  depends_on = [proxmox_virtual_environment_role.cs_tofu]

}

resource "proxmox_virtual_environment_acl" "acl_tokens" {

  for_each = local.outils

  token_id = proxmox_virtual_environment_user_token.jetons[each.key].id

  path = "/"

  role_id = each.value

  propagate = true

  depends_on = [proxmox_virtual_environment_role.cs_tofu]

}

output "jeton_tofu" {

  value = proxmox_virtual_environment_user_token.jetons["tofu"].value

  sensitive = true

}

output "secret_ansible" {

  value = proxmox_virtual_environment_user_token.jetons["ansible"].value

  sensitive = true

}
 