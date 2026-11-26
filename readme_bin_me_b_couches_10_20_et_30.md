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