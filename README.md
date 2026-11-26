# CyberSadiver — 5VIRTDC

# CyberSadiver : infrastructure en code

Reconstruction du cluster Proxmox VE `pve-cyber` (3 nœuds) uniquement à partir de ce dépôt,
avec OpenTofu et Ansible. Aucune modification manuelle en dehors de l'installation de
Proxmox VE et de la copie de la clé SSH.

## Structure du dépôt

Une couche par dossier, exécutées dans un ordre fixe.

| Ordre | Dossier | Outil | Rôle |
|---|---|---|---|
| 1 | `00-hotes/` | Ansible | Configuration des nœuds : dépôts, mises à jour, chrony, NFS |
| 2 | `10-amorcage/` | OpenTofu | Rôle, utilisateurs et jetons d'API |
| 3 | `20-socle/` | OpenTofu | Stockage, SDN, droits, pare-feu |
| 4 | `30-image/` | OpenTofu | Image maître Debian 13 (Cloud-Init) |
| 5 | `40-services/` | OpenTofu | Invités cs-dns, cs-web, cs-bdd, sauvegardes, réplication, HA |
| 6 | `50-config/` | Ansible | Configuration des services |
| - | `modules/vm`, `modules/ct` | OpenTofu | Modules réutilisables (VM et conteneurs) |

## Prérequis

- OpenTofu : `1.13.9` (`tofu version`)
- Ansible : `` (`ansible --version`), sous Linux ou WSL
- Provider OpenTofu : `bpg/proxmox` `0.123.1`
- Collections Ansible : `community.proxmox`, `community.mysql`
- Git

Ansible ne fonctionne pas nativement sous Windows : utiliser WSL (Ubuntu).

## Préparation

1. Cloner le dépôt.
2. Créer la fiche réelle à partir de l'exemple, puis l'adapter à son environnement :
   ```bash
   cp fiche.exemple.yml fiche.yml
   ```
   `fiche.yml` contient toutes les valeurs propres à l'environnement (adresses, noms,
   réseaux). Elle est ignorée par Git et ne doit jamais être commitée.
3. Récupérer le mot de passe du coffre Ansible (auprès du responsable, jamais dans Git) :
   ```bash
   printf '%s' '<mot-de-passe-du-coffre>' > 50-config/.vault_pass
   chmod 600 50-config/.vault_pass
   ```

## Secrets

| Fichier | Versionné | Remarque |
|---|---|---|
| `fiche.exemple.yml` | oui | Valeurs d'exemple, sans secret |
| `fiche.yml` | **non** | Valeurs réelles |
| `50-config/secrets.yml` | oui | Chiffré avec `ansible-vault` |
| `50-config/.vault_pass` | **non** | Mot de passe du coffre |
| `*.tfstate*`, `.terraform/`, `*.tfvars` | **non** | États et variables réelles |

Gérer le coffre :
```bash
ansible-vault view 50-config/secrets.yml
ansible-vault edit 50-config/secrets.yml
```

Les jetons d'API ne sont jamais écrits dans le dépôt : ils sont exportés dans des
variables d'environnement.

## Ordre d'exécution

```
00-hotes -> 10-amorcage -> 20-socle -> 30-image -> 40-services -> 50-config
```

Les commandes détaillées de chaque couche sont ajoutées ici au fil de la réalisation.

## Destruction

À compléter : ordre inverse de l'exécution. Avant de détruire le socle, éteindre le
pare-feu du centre de données (`tofu -chdir=20-socle apply -var pare_feu_actif=false`).

## Contrôle de l'étape 0

- `git status` est propre après un `tofu init`.
- Aucun secret n'apparaît dans `git log -p`.

---

## Source : Binôme B — couches 10, 20 et 30

# Binôme B — Amorçage, Socle et Image Maître (Couches 10, 20, 30)

Ce document décrit l'architecture, la mise en œuvre, les contrôles de validation et les procédures de maintenance des couches gérées par le **Binôme B** dans le cadre du redéploiement en code (*Infrastructure as Code*) de l'infrastructure **CyberSadiver** sur Proxmox VE 9.

---

## 1. Périmètre et Règles d'Or

* **Couches gérées :**
  * `10-amorcage` : création du rôle personnalisé `CS-Tofu`, des comptes techniques (`tofu@pve`, `ansible@pve`) et de leurs jetons API.
  * `20-socle` : montage du stockage partagé `cs-nfs`, configuration SDN (VXLAN `vback` et zone Simple `vlabo`), gestion des droits/pools (`cs-services`) et déploiement du pare-feu du datacenter.
  * `30-image` : téléchargement de l'image cloud Debian 13 et création du modèle maître `900` (`tpl-debian13`) avec Cloud-Init et agent QEMU.
* **Rôles transverses :** Contrôleur des étapes 2, 3 et 4 (conservation des preuves) et rédacteur de la note d'architecture.
* **Règles impératives :**
  1. **Aucune modification manuelle** dans l'interface web Proxmox (toute correction passe par le code HCL et `tofu apply`).
  2. **Aucun secret dans Git** : `fiche.yml`, `*.tfstate*`, `.terraform/` et les jetons restent strictement locaux.
  3. **Un seul poste Pilote (Binôme A)** exécute les commandes `tofu apply` et `tofu destroy` qui modifient le cluster (l'état `.tfstate` est local).

---

## 2. Prérequis et Arborescence

### Versions requises
* **OpenTofu :** `>= 1.8` (validé avec `v1.13.9`)
* **Provider Proxmox :** `bpg/proxmox` version `0.123.1`
* **Configuration locale :** fichier `fiche.yml` copié depuis `fiche.exemple.yml` à la racine du dépôt (non versionné).

### Structure des fichiers du Binôme B

```text
5VIRTDC_TP2/
├── fiche.yml                   # Source unique des variables (ignoré par Git)
├── 10-amorcage/
│   ├── provider.tf             # Provider configuré avec root@pam (PROXMOX_VE_PASSWORD)
│   ├── main.tf                 # Rôle CS-Tofu, utilisateurs outils, jetons et ACL
│   └── .terraform.lock.hcl     # Verrou du provider (versionné)
├── 20-socle/
│   ├── provider.tf             # Provider authentifié via PROXMOX_VE_API_TOKEN
│   ├── variables.tf            # Variables mot_de_passe_initial et pare_feu_actif
│   ├── stockages.tf            # Stockage NFS cs-nfs (v4.2) et template LXC Debian 13
│   ├── sdn.tf                  # Zone VXLAN back (VNI 30030, MTU 1450) + zone Simple labo
│   ├── droits.tf               # Pool cs-services, groupes, admins, direction, supervision + ACL vmbr0
│   ├── parefeu.tf              # Alias, IPSet management/noeuds, groupes sg-web/sg-dns/sg-bdd, activation
│   ├── outputs.tf              # Sorties (pool_services, security_groups, jeton_supervision)
│   └── .terraform.lock.hcl     # Verrou du provider (versionné)
└── 30-image/
    ├── provider.tf             # Provider authentifié via PROXMOX_VE_API_TOKEN
    ├── main.tf                 # Téléchargement qcow2 (contenu import) + VM modèle 900 tpl-debian13
    └── .terraform.lock.hcl     # Verrou du provider (versionné)
```

---

## 3. Points de Synchronisation Inter-Binômes

| Étape | Dépendance / Attente | Livrable / Action du Binôme B |
| :--- | :--- | :--- |
| **Étape 0-1** | Arborescence et `fiche.exemple.yml` poussés par **C** | Écriture et validation hors-ligne (`tofu validate`) des couches `10`, `20` et `30`. |
| **Étape 2** | **Contrôle 1 validé par A** (cluster `pve-cyber` quorate à 3 nœuds, NFS actif sur `pve3`) | Déploiement de `10-amorcage`, validation du **Contrôle 2**, transmission des jetons à **A**. |
| **Étape 3** | Relecture des règles SSH avec **A** | Déploiement de `20-socle`, validation du **Contrôle 3**, transmission de `cs-services` et `sg-*` à **C**. |
| **Étape 4** | Présence confirmée par **A** de `/rpool/nfs/snippets/vendor-agent.yml` sur `pve3` | Déploiement de `30-image`, validation du **Contrôle 4**, mise à disposition du modèle `900` pour **C**. |
| **Étapes 5-7** | Tests modules (**C**) et configuration Ansible (**A**) | Diagnostic et ajustement éventuel des règles dans `20-socle/parefeu.tf`. |

---

## 4. Guide d'Exécution Pas-à-Pas

### Phase A : Validation syntaxique hors-ligne (Poste Binôme B)

À exécuter avant tout envoi sur GitHub :

```powershell
# S'assurer que fiche.yml existe localement
Copy-Item fiche.exemple.yml fiche.yml

# Validation de chaque couche
foreach ($couche in @("10-amorcage", "20-socle", "30-image")) {
    tofu -chdir=$couche fmt
    tofu -chdir=$couche init -backend=false
    tofu -chdir=$couche validate
}
```

### Phase B : Couche `10-amorcage` — Identités et Jetons (Étape 2 / Contrôle 2)

> **Piège :** Toujours exécuter `unset PROXMOX_VE_API_TOKEN` avant d'appliquer la couche `10-amorcage`, sinon OpenTofu tentera d'utiliser un ancien jeton `tofu@pve` au lieu de `root@pam`.

Sur le terminal du **Pilote (Binôme A)** :

```bash
export PROXMOX_VE_PASSWORD='<MOT_DE_PASSE_ROOT_PVE>'
unset PROXMOX_VE_API_TOKEN

tofu -chdir=10-amorcage init
tofu -chdir=10-amorcage plan
tofu -chdir=10-amorcage apply

# Récupération des jetons
export JETON_TOFU=$(tofu -chdir=10-amorcage output -raw jeton_tofu)
export SECRET_ANSIBLE=$(tofu -chdir=10-amorcage output -raw secret_ansible)

# Contrôle 2a : Authentification des deux jetons (HTTP 200 attendu)
curl -k -H "Authorization: PVEAPIToken=tofu@pve!tofu=${JETON_TOFU}" \
  https://172.19.0.11:8006/api2/json/version
curl -k -H "Authorization: PVEAPIToken=ansible@pve!ansible=${SECRET_ANSIBLE}" \
  https://172.19.0.11:8006/api2/json/version

# Contrôle 2b : Vérification de l'isolation en lecture seule d'Ansible (HTTP 403 attendu)
curl -k -i -X POST -H "Authorization: PVEAPIToken=ansible@pve!ansible=${SECRET_ANSIBLE}" \
  -d "poolid=test-refus" https://172.19.0.11:8006/api2/json/pools

# Bascule définitive sur le jeton OpenTofu et suppression du mot de passe root
unset PROXMOX_VE_PASSWORD
export PROXMOX_VE_API_TOKEN="tofu@pve!tofu=${JETON_TOFU}"
```

### Phase C : Couche `20-socle` — Stockage, SDN, Droits et Pare-feu (Étape 3 / Contrôle 3)

> **Vérification préalable :** Contrôler dans `fiche.yml` que `postes_admin` contient bien le sous-réseau ou les adresses IP des postes d'administration avant d'activer le pare-feu.

Sur le terminal du **Pilote (Binôme A)** :

```bash
export TF_VAR_mot_de_passe_initial='<MOT_DE_PASSE_INITIAL_COMPTES>'

tofu -chdir=20-socle init
tofu -chdir=20-socle plan
tofu -chdir=20-socle apply

# Contrôle 3a : Idempotence ("No changes" attendu)
tofu -chdir=20-socle plan

# Contrôle 3b : Vérification VXLAN (VNI 30030, MTU 1450), SDN et pare-feu sur les nœuds
for ip in 172.19.0.11 172.19.0.12 172.19.0.13; do
  ssh root@$ip 'ip -d link show vxlan_vback'
done
ssh root@172.19.0.11 'pvesh get /cluster/sdn/vnets'
ssh root@172.19.0.11 'pve-firewall status'
```

*Validation complémentaire (Contrôle 3c) :* Déployer temporairement un conteneur de test LXC sur le VNet `vlabo`, vérifier l'attribution d'une IP DHCP (`10.0.99.100-150`) et le fonctionnement de `apt update` avec le pare-feu actif, puis retirer cette ressource temporaire du code HCL et relancer `apply`.

### Phase D : Couche `30-image` — Modèle Maître Debian 13 (Étape 4 / Contrôle 4)

Sur le terminal du **Pilote (Binôme A)** :

```bash
# Vérifier la présence du snippet Cloud-Init déposé par la couche 00 (Ansible)
ssh root@172.19.0.13 'ls -l /rpool/nfs/snippets/vendor-agent.yml'

tofu -chdir=30-image init
tofu -chdir=30-image apply

# Contrôle 4a : Vérification de la configuration du modèle 900
ssh root@172.19.0.11 'qm config 900'

# Contrôle 4b : Test de clonage temporaire et remontée d'IP par l'agent QEMU
ssh root@172.19.0.11 'qm clone 900 999 --full 1 --storage local-zfs && qm start 999'
# Attendre le premier démarrage Cloud-Init (installation qemu-guest-agent) puis vérifier l'IP :
ssh root@172.19.0.11 'qm guest cmd 999 network-get-interfaces'
# Nettoyage obligatoire du clone de test
ssh root@172.19.0.11 'qm stop 999 && qm destroy 999'
```

#### Commande de reconstruction de l'image maître
En cas de publication d'une nouvelle image Debian 13 Cloud, forcer le remplacement des deux ressources :

```bash
tofu -chdir=30-image apply \
  -replace=proxmox_download_file.debian13_cloud \
  -replace=proxmox_virtual_environment_vm.modele
```

---

## 5. Architecture de Sécurité et Diagnostic (Étapes 5 à 7)

### Matrice des flux pare-feu (`20-socle/parefeu.tf`)

| Cible / Groupe | Protocole / Port | Source autorisée | Justification |
| :--- | :--- | :--- | :--- |
| **Cluster (Datacenter)** | UDP `4789` | `net_lan` | Encapsulation VXLAN (`vback`, VNI `30030`). |
| **Cluster (Datacenter)** | TCP `111, 2049` | `net_lan` | Montage du partage NFSv4.2 `cs-nfs`. |
| **Cluster (Datacenter)** | UDP `67, 68` | Interface `vlabo` | Attribution DHCP par `dnsmasq` sur la zone `labo`. |
| **`sg-web` (`cs-web`)** | TCP `80`, ICMP | Tout (`0.0.0.0/0`) | Accès HTTP à l'intranet et diagnostic ping. |
| **`sg-web` (`cs-web`)** | TCP `22` | `+noeuds` | Rebond SSH uniquement depuis les nœuds Proxmox. |
| **`sg-web` (`cs-web`)** | TCP `3142` | `10.0.30.103/32` (`cs-bdd`) | Accès au cache de paquets `apt-cacher-ng` depuis le réseau back. |
| **`sg-dns` (`cs-dns`)** | UDP/TCP `53` | `net_lan` | Résolution DNS interne (`cybersadiver.lan`). |
| **`sg-dns` (`cs-dns`)** | TCP `22` | `+noeuds` | Rebond SSH uniquement depuis les nœuds Proxmox. |
| **`sg-bdd` (`cs-bdd`)** | TCP `3306`, TCP `22` | `10.0.30.102/32` (`cs-web`) | Requêtes MariaDB et rebond SSH depuis `cs-web` uniquement. |

### Commandes de diagnostic pare-feu (si erreur `UNREACHABLE` sous Ansible)

```bash
ssh root@172.19.0.11 'pve-firewall compile | head -50'
ssh root@172.19.0.11 'pvesh get /cluster/firewall/groups/sg-bdd'
ssh root@172.19.0.11 'journalctl -u pve-firewall -n 50'
```

---

## 6. Dérive, Destruction Sécurisée et Reconstruction (Étape 8)

### 1. Test de détection et correction de dérive
1. Modifier manuellement dans l'interface web Proxmox la mémoire de `cs-web` et une règle du groupe `sg-web`.
2. Constater l'écart avec `tofu -chdir=40-services plan` et `tofu -chdir=20-socle plan`.
3. Rétablir l'état déclaré avec `tofu -chdir=40-services apply` et `tofu -chdir=20-socle apply`.
4. *Limite d'OpenTofu :* OpenTofu ne détecte pas les modifications internes aux invités (paquets installés à la main, fichiers modifiés) ni les ressources non déclarées dans son état (VM créée manuellement).

### 2. Procédure de destruction (Ordre inverse obligatoire)

> **CRITIQUE :** Ne **jamais** exécuter `tofu -chdir=20-socle destroy` tant que le pare-feu du datacenter est actif. La suppression de l'IPSet `management` et des règles cluster avant la désactivation du pare-feu couperait immédiatement les flux NFS, VXLAN et l'accès administration.

```bash
# 1. Après destruction de 40-services (C), nettoyage (A) et destruction de 30-image :
tofu -chdir=30-image destroy

# 2. Désactiver d'abord le pare-feu du datacenter, puis détruire le socle :
tofu -chdir=20-socle apply -var="pare_feu_actif=false"
tofu -chdir=20-socle destroy
```

### 3. Reconstruction complète
Rejouer les couches dans l'ordre exact :
1. `tofu -chdir=10-amorcage apply` (puis ré-exporter `PROXMOX_VE_API_TOKEN` et `SECRET_ANSIBLE`).
2. `tofu -chdir=20-socle apply` (avec `TF_VAR_mot_de_passe_initial` défini).
3. `tofu -chdir=30-image apply`.

---

## Source : Binôme C — dépôt, modules et services

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
---

# Synthèse de cohérence avec le TP

## Ordre global attendu

`00-hotes` → `10-amorcage` → `20-socle` → `30-image` → `40-services` → `50-config`. L’amorçage reste en place lors des reconstructions de l’étape 8. L’état OpenTofu est local : un seul poste pilote exécute les commandes qui modifient le cluster.

## Écarts et arbitrages à faire

- **Version du provider Proxmox :** le document B annonce `0.123.1`; le document C annonce une validation en `0.124.0`; le README d’étape 0 ne fixe pas de version. Vérifier la version réellement verrouillée dans le dépôt et l’aligner dans le README et les couches.
- **Groupes de sécurité :** le document B et le TP utilisent `sg-web`, `sg-dns`, `sg-bdd`; le document C mentionne provisoirement `gs-web`, `gs-dns`, `gs-bdd`. Utiliser les noms du TP partout, sauf décision documentée.
- **Déploiement du snippet Cloud-Init :** le document B suppose que la couche `00-hotes` a déjà déposé `/rpool/nfs/snippets/vendor-agent.yml`. Le TP précise que le provider peut le déposer par SSH sur les nœuds et demande de justifier l’outil retenu. Décrire cette opération dans une couche et la rendre reproductible; ne pas dépendre d’une copie manuelle.
- **Accès aux paquets pour `cs-bdd` :** le TP exige une solution qui permette l’installation sans rendre le conteneur joignable depuis le front, et demande de n’ouvrir que les flux nécessaires. La matrice B évoque `apt-cacher-ng` sur `cs-web` (port TCP 3142, source `10.0.30.103`), mais les trois fichiers ne décrivent pas son déploiement ni la configuration du client. Compléter et justifier ce choix, ou documenter une autre solution.
- **README non encore autosuffisant :** il annonce que les commandes détaillées seront ajoutées au fil de la réalisation. Le TP exige qu’un inconnu puisse reconstruire toutes les couches depuis le seul README. Il manque notamment ici les procédures complètes de `00-hotes`, `50-config`, la configuration des services Ansible (étape 7), les prérequis définitifs et les contrôles/preuves de reconstruction.
- **Dérive HA :** C propose `ignore_changes = [node_name]`, qui évite une recréation après déplacement HA. Le TP demande de décider et justifier comment OpenTofu traite le placement après bascule (migration, ignorance ou laisser HA maître). Documenter aussi la conséquence pour la réplication.
- **Modification manuelle :** le TP interdit les changements manuels en exploitation, mais l’étape 8 demande expressément une modification temporaire dans l’interface pour démontrer la détection de dérive, puis sa correction par code. Présenter cela comme un test ponctuel, pas comme une méthode d’administration.
- **Valeurs héritées du TP 1 :** le TP demande de comparer le dossier d’exploitation d’origine à l’infrastructure reconstruite et de noter les écarts. Les valeurs indiquées dans les documents B/C (par exemple disque de `cs-web`, mémoire de `cs-bdd`, heure de sauvegarde) doivent être confirmées contre ce dossier et reportées comme écarts justifiés si elles diffèrent.

## Points du TP à ajouter au README final

- Redémarrer les trois nœuds après mise à jour et avant la création du cluster; contrôler le second passage Ansible (`changed=0`), l’export NFS, `dnsmasq` désactivé et le quorum à trois votes.
- Pour l’étape 4, déclarer le processeur `x86-64-v2-AES`, le contrôleur VirtIO SCSI single, le lecteur Cloud-Init, et le dépôt reproductible de la vendor data qui installe et démarre l’agent QEMU.
- Pour les modules, conserver toutes les entrées exigées par le TP (identité, ressources, cartes, groupe de sécurité et étiquettes), avec règles de validation et contrôles négatifs.
- Pour l’étape 7, ajouter l’inventaire dynamique `community.proxmox.proxmox` avec `want_facts: true`, les rebonds SSH, les trois rôles `unbound`, `nginx` et `mariadb`, les secrets sous Ansible Vault et le contrôle idempotent.
- Pour l’étape 8, renseigner les durées et preuves des reconstructions partielle et complète; le contrôle exige le passage des contrôles 3 à 7 et aucune commande hors du README.
