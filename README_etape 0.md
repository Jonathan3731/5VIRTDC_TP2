# CyberSadiver : infrastructure en code

Reconstruction du cluster Proxmox VE `pve-cyber` (3 nœuds) uniquement à partir de ce dépôt,
avec OpenTofu et Ansible. Aucune modification manuelle en dehors de l'installation de
Proxmox VE, de la copie de la clé SSH et de la création du cluster.

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

- OpenTofu : v1.13.10 (`tofu version`)
- Ansible : v2.20.1 (`ansible --version`), sous Linux ou WSL
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
