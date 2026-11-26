# Binôme C : dépôt, modules et services (couche 40)

TP CyberSadiver : redéploiement de l'infrastructure Proxmox en code (OpenTofu + Ansible).

**Périmètre du binôme C :** le dépôt Git (étape 0), les modules OpenTofu `vm` et `ct` (étape 5) et la couche `40-services` (étape 6).
**Contrôles portés :** 0, 5 et 6, ainsi que le chronométrage et le rapport du contrôle 8.

**Règle d'or :** tout ce qui existe à la fin vient du dépôt Git. Aucun secret n'est versionné.

---

## 1. Le dépôt (étape 0)

Dépôt GitHub : `Jonathan3731/5VIRTDC_TP2`, poussé avec le compte `tomh57`.

### Arborescence

```
cybersadiver/
├── .gitignore
├── README.md              # rempli par le binôme A
├── fiche.exemple.yml      # modèle de fiche, versionné
├── 00-hotes/              # binôme A
├── 10-amorcage/           # binôme B
├── 20-socle/              # binôme B
├── 30-image/              # binôme B
├── 40-services/           # binôme C
│   ├── provider.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── services.tf
│   ├── exploitation.tf
│   └── outputs.tf
├── 50-config/             # binôme A (Ansible)
└── modules/
    ├── vm/  (main.tf, variables.tf, outputs.tf)
    └── ct/  (main.tf, variables.tf, outputs.tf)
```

### La fiche : une seule source pour les valeurs

`fiche.exemple.yml` regroupe toutes les valeurs du TP 1 :

| Élément | Valeur |
|---|---|
| Domaine / cluster | `cybersadiver.lan` / `pve-cyber` |
| Nœuds | pve1 `172.19.0.11`, pve2 `172.19.0.12`, pve3 `172.19.0.13` |
| Front | `vmbr0`, MTU 1500, `172.19.0.0/16`, passerelle `172.19.0.1`, DNS `8.8.8.8` |
| Back | `vback`, `10.0.30.0/24`, MTU 1450 |
| Stockage | `local-zfs` (disques), `cs-nfs` (partagé), pool `cs-services` |
| Invités | cs-dns `172.19.0.101`, cs-web `172.19.0.102` et `10.0.30.102`, cs-bdd `10.0.30.103` |
| Modèles | VM 900 sur pve1, LXC `debian-13-standard_13.1-2_amd64.tar.zst` |
| Administrateurs | tomy, jojo, momo, romain, soulay, matheo |

Sur le poste pilote, la fiche est copiée en `fiche.yml`, qui n'est **jamais commité** :

```powershell
Copy-Item fiche.exemple.yml fiche.yml
```

La couche 40 lit les valeurs dans `fiche.yml` avec `yamldecode(file("../fiche.yml"))`. Aucune IP n'est donc écrite en dur dans le code.

### Le `.gitignore`

```
fiche.yml
*.tfstate*
.terraform/
*.tfvars
.ssh_config
*.pem
id_*
```

Le fichier `.terraform.lock.hcl` est **versionné**, pour que tout le monde utilise la même version du provider.

### Historique Git

Les commits sont petits et lisibles, car l'historique est un livrable :

```powershell
git add .gitignore 00-hotes 10-amorcage 20-socle 30-image 50-config
git commit -m "Squelette du depot et .gitignore"
git add fiche.exemple.yml
git commit -m "Fiche exemple du TP"
git add modules
git commit -m "Modules OpenTofu vm et ct"
git add 40-services
git commit -m "Couche 40-services"
git push
```

### Contrôle 0

```powershell
tofu -chdir=40-services init
git status                                      # doit être propre
git log -p | Select-String -Pattern "token|password|secret"   # ne doit rien afficher
```

- [ ] `git status` propre après `tofu init` (capture)
- [ ] Aucun secret dans `git log -p` (capture)

---

## 2. Les modules OpenTofu `vm` et `ct` (étape 5)

Provider : **`bpg/proxmox` (>= 0.99.0)**, validé avec la version 0.124.0.

### Module `modules/vm`

| Variable | Rôle |
|---|---|
| `nom`, `vmid`, `noeud` | identité et nœud préféré |
| `modele = { vmid, noeud }` | modèle à cloner (900 sur pve1) |
| `cartes` | liste `{ pont, ip, passerelle?, mtu? }`, une carte réseau par entrée |
| `groupe_securite` | groupe de sécurité du pare-feu |
| `etiquettes` | étiquettes de rôle |
| `stockage`, `pool` | `local-zfs`, `cs-services` |
| `cpu`, `memoire`, `disque`, `disque_interface` | dimensionnement |
| `dns`, `domaine`, `utilisateur` | réglages Cloud-Init |
| `cle_ssh`, `mot_de_passe` | **sensitive** |

Ce que crée le module :

- **Clone complet** (`full = true`) du modèle, vers `local-zfs`. Le provider clone sur pve1 puis migre vers le nœud préféré.
- **Cartes réseau** générées par `dynamic "network_device"`, avec le **pare-feu coché** sur chacune.
- **Cloud-Init** : utilisateur `admin`, clé SSH, mot de passe console, une `ip_config` par carte, DNS et domaine. Le lecteur Cloud-Init est aussi sur `local-zfs`.
- **Agent QEMU** activé.
- `lifecycle { ignore_changes = [node_name] }`, pour que HA puisse déplacer la VM sans qu'OpenTofu veuille la recréer.
- **Pare-feu de l'invité** : `input_policy = "DROP"` et une règle qui applique le groupe de sécurité.
- **Sorties** : `vmid`, `nom`, `adresses`.

### Module `modules/ct`

Il a la même structure, avec ces différences :

- `unprivileged = true` et `nesting = true` ;
- le modèle LXC est pris sur `cs-nfs` (`cs-nfs:vztmpl/...`) ;
- le disque racine est sur `local-zfs` ;
- l'**utilisateur root** reçoit la clé SSH, ce qui est indispensable pour Ansible, ainsi que le mot de passe console.

### Validations

Les deux modules contiennent les mêmes blocs `validation` :

| Règle | Message |
|---|---|
| `100 <= vmid < 900` | « Le VMID doit etre entre 100 et 899. » |
| nom conforme à `^[a-z0-9-]+$` | « Nom en minuscules, sans accent. » |
| au moins une étiquette, en minuscules | « Au moins une etiquette de role, en minuscules. » |

### Contrôle 5

```powershell
tofu -chdir=modules/vm init -backend=false
tofu -chdir=modules/vm validate
tofu -chdir=modules/ct init -backend=false
tofu -chdir=modules/ct validate
```

Pour le test de refus, on ajoute dans `40-services` un appel de module temporaire avec `vmid = 950`, puis avec `nom = "CS-Web"`. Le `plan` doit échouer sans rien créer, puis on retire l'appel.

```
Error: Invalid value for variable
Le VMID doit etre entre 100 et 899.

Error: Invalid value for variable
Nom en minuscules, sans accent.
```

Après la création des invités, on vérifie sur les nœuds :

```bash
pvesh get /pools/cs-services                       # les 3 invités sont dans le pool
qm config 102 | grep -E "firewall|tags"            # firewall=1 sur les cartes, étiquettes
pvesh get /nodes/pve2/qemu/102/firewall/options    # policy_in: DROP
```

- [ ] `tofu validate` OK sur les deux modules (capture)
- [ ] VMID 950 refusé au plan (capture)
- [ ] Nom `CS-Web` refusé au plan (capture)
- [ ] Pool, groupe de sécurité, DROP et pare-feu coché vérifiés (capture)

---

## 3. La couche 40-services (étape 6)

### `services.tf` : les trois invités

| Invité | Type | VMID | Nœud | Ressources | Réseau | Étiquettes |
|---|---|---|---|---|---|---|
| cs-dns | CT | 101 | pve1 | 512 Mio, 4 Gio | front `172.19.0.101/16` | `cyber;dns` |
| cs-web | VM | 102 | pve2 | 1 Gio, **9 Gio** | front `172.19.0.102/16` et vback `10.0.30.102/24` sans passerelle | `cyber;web` |
| cs-bdd | CT | 103 | pve3 | **1 Gio**, 8 Gio | vback `10.0.30.103/24` uniquement | `bdd;cyber` |

### `exploitation.tf` : sauvegarde, réplication et HA

- **`proxmox_backup_job` `sauvegarde-nuit`** : pool `cs-services` vers `cs-nfs`, à **01:00**, en mode snapshot, compression zstd, rétention `keep-daily = 7` et `keep-weekly = 4`.
- **Six `proxmox_replication`** toutes les 2 minutes (`*/2`) : chaque invité est répliqué vers les deux autres nœuds. Les clés sont calculées dans `local.replications` (`101-0`, `101-1`, `102-0`…).
- **Trois `proxmox_haresource`** en état `started` : `ct:101`, `vm:102` et `ct:103`.
- **Trois `proxmox_harule` de type `node-affinity`** : priorité 2 sur le nœud préféré, 1 sur les autres, `strict = false`.

### Secrets : uniquement dans le terminal du poste pilote

```powershell
$env:PROXMOX_VE_API_TOKEN = 'tofu@pve!tofu=<secret>'
$env:TF_VAR_cle_ssh = Get-Content "$HOME\.ssh\id_cybersadiver.pub" -Raw
$env:TF_VAR_mot_de_passe_invites = '<mot de passe console>'
```

### Déploiement

```powershell
tofu -chdir=40-services init
tofu -chdir=40-services plan
tofu -chdir=40-services apply
tofu -chdir=40-services plan      # 2e plan : No changes
```

Si cs-web reste bloqué, il peut attendre l'agent QEMU jusqu'à 15 minutes. Pour diagnostiquer :

```bash
ssh root@172.19.0.12 qm guest cmd 102 ping
ssh root@172.19.0.12 qm terminal 102
cloud-init status --long          # dans la console de la VM
```

### Contrôle 6

```bash
ssh root@172.19.0.11 'pvesr status'       # 6 réplications OK
ssh root@172.19.0.11 'ha-manager status'  # 3 ressources started, chacune sur son nœud préféré
```

- [ ] Les trois invités sur leur nœud préféré (capture)
- [ ] Six réplications vertes (capture de `pvesr status`)
- [ ] Trois ressources HA `started` (capture de `ha-manager status`)
- [ ] Second plan « No changes » (capture)

Une fois le contrôle validé, on prévient le binôme A : les étiquettes sont posées et la clé SSH est dans le compte root des conteneurs.

---

## 4. Choix techniques et pièges évités

| Piège | Solution retenue |
|---|---|
| Réplication refusée à cause d'un clone lié ou d'un disque hors ZFS | `full = true`, et tous les disques ainsi que le lecteur Cloud-Init sur `local-zfs` |
| Modèle 900 présent seulement sur pve1 | argument `modele = { vmid, noeud }` : clone sur pve1 puis migration |
| Dérive HA : après une bascule, le plan propose de détruire la VM | `ignore_changes = [node_name]` sur les invités |
| Disque de cs-web | 9 Gio (3 du modèle + 6), pas 6 comme au TP 1 |
| Mémoire de cs-bdd | 1 Gio, pas 512 Mio |
| Heure de sauvegarde | 01:00 (21:00 au TP 1), avec 4 hebdomadaires en plus des 7 quotidiennes |
| MTU de la carte vback | `mtu = 1` (hérité du pont) pour la VM, 1450 pour le CT ; vérifier avec `ip link` |
| Nom de ressource du provider | noms longs `proxmox_virtual_environment_*` pour la VM, le CT et le pare-feu (pas encore de nom court pour le CT et le pare-feu) ; noms courts `proxmox_*` pour la sauvegarde, la réplication et HA |
| Secrets dans Git | variables `sensitive` alimentées par `TF_VAR_*`, jeton Proxmox dans `PROXMOX_VE_API_TOKEN`, `fiche.yml` ignoré |

### Valeurs à aligner avec le binôme B

- Les noms des groupes de sécurité, dans `40-services/locals.tf` (provisoirement `gs-dns`, `gs-web` et `gs-bdd`).
- Le `provider.tf` commun, s'il diffère de celui de la couche 40.
- L'interface du disque du modèle 900 (`scsi0` par défaut).

---

## 5. Incidents rencontrés

| Incident | Cause | Résolution |
|---|---|---|
| `git push` refusé (403) | VS Code et Git utilisaient le compte `tmyh` au lieu de `tomh57` | URL du dépôt avec `tomh57@`, puis suppression de l'identifiant mémorisé |
| `Password authentication is not supported` | GitHub n'accepte plus les mots de passe pour Git | jeton d'accès personnel (`repo`) utilisé à la place du mot de passe |
| Dépôt GitHub vide en dehors du README | seul le premier commit avait été poussé | `git add` et `commit` des dossiers, puis `git push` |

---

## 6. Étape 8 : reconstruction (rôle de chronométreur)

Reconstruction partielle de la couche 40 :

```bash
time tofu -chdir=40-services destroy
ansible-playbook -i localhost, 00-hotes/nettoyage.yml   # supprime les copies de réplication orphelines
time tofu -chdir=40-services apply
tofu -chdir=40-services plan                            # No changes
```

| Couche | Commande | Début | Fin | Durée | Incidents |
|---|---|---|---|---|---|
| 40 (destroy) | `tofu -chdir=40-services destroy` | | | | |
| nettoyage | `ansible-playbook ... nettoyage.yml` | | | | |
| 40 (apply) | `tofu -chdir=40-services apply` | | | | |
| reconstruction complète | ordre du README | | | | |
