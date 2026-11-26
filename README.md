# Rapport de redéploiement de l’infrastructure CyberSadiver en code

## Présentation

Nous avons préparé le redéploiement du cluster Proxmox VE 9 `pve-cyber`, composé de trois nœuds, à partir d’un dépôt Git unique. OpenTofu décrit les ressources accessibles par l’API Proxmox et Ansible configure les hôtes et les services. Nous avons organisé le travail en couches indépendantes, exécutées dans un ordre fixe, et réparti leur réalisation entre les binômes A, B et C.

La règle retenue est que l’infrastructure finale provient du dépôt. Les seules opérations manuelles de la reconstruction sont l’installation de Proxmox VE, la copie de la clé SSH et la création initiale du cluster. La lecture de l’état et les contrôles restent permis. L’état OpenTofu étant local, un seul poste pilote par groupe exécute les opérations qui modifient le cluster.

Ce rapport rassemble les informations des trois fichiers Markdown transmis. Il distingue les choix d’architecture et les procédures décrites des résultats d’exécution : les documents donnent les contrôles à effectuer, mais ne contiennent pas leurs sorties, captures ou mesures de durée.

## 1. Architecture du dépôt et ordre d’exécution

Nous avons découpé le dépôt de la manière suivante :

| Ordre | Dossier | Outil | Fonction |
|---:|---|---|---|
| 1 | `00-hotes` | Ansible | Configuration des nœuds, dépôts, mises à jour, chrony, NFS et préparation de dnsmasq |
| 2 | `10-amorcage` | OpenTofu | Rôle, comptes techniques et jetons API |
| 3 | `20-socle` | OpenTofu | Stockage partagé, SDN, droits, pool et pare-feu |
| 4 | `30-image` | OpenTofu | Image maître Debian 13 avec Cloud-Init |
| 5 | `40-services` | OpenTofu | Invités, sauvegardes, réplications et haute disponibilité |
| 6 | `50-config` | Ansible | Configuration des services invités |
| Transversal | `modules/vm`, `modules/ct` | OpenTofu | Modules réutilisables pour les machines virtuelles et les conteneurs |

Nous reconstruisons les couches dans l’ordre `00-hotes`, `10-amorcage`, `20-socle`, `30-image`, `40-services`, puis `50-config`. La couche d’amorçage reste présente lors des reconstructions ultérieures. Le dépôt contient également `fiche.exemple.yml`, le modèle non secret des paramètres du cluster, et `.gitignore`, qui protège les données locales.

## 2. Prérequis et paramètres du cluster

Le README fourni indique OpenTofu 1.13.9, Ansible 2.20.1, le provider `bpg/proxmox` en version 0.123.1, les collections Ansible `community.proxmox` et `community.mysql`, ainsi que Git. Ansible s’exécute sous Linux ou WSL, car il n’est pas pris en charge nativement sous Windows.

Les notes du binôme C indiquent également une validation avec le provider 0.124.0. Cette différence avec la version 0.123.1 indiquée dans le README et les notes du binôme B doit être résolue à partir du fichier `.terraform.lock.hcl` du dépôt. Le verrou versionné doit fournir la référence commune des couches.

Nous regroupons les paramètres propres à l’environnement dans `fiche.exemple.yml`, puis le pilote en crée une copie locale nommée `fiche.yml`. Cette fiche décrit notamment le domaine `cybersadiver.lan`, le cluster `pve-cyber`, les nœuds `pve1` à `pve3`, leurs adresses de gestion, les réseaux front et back, les stockages et les invités. La fiche réelle n’est jamais versionnée.

Les valeurs récapitulées dans les notes sont les suivantes :

| Élément | Valeur documentée |
|---|---|
| Cluster et domaine | `pve-cyber`, `cybersadiver.lan` |
| Nœuds | `pve1` : `172.19.0.11`, `pve2` : `172.19.0.12`, `pve3` : `172.19.0.13` |
| Réseau front | `vmbr0`, MTU 1500, `172.19.0.0/16`, passerelle `172.19.0.1`, DNS `8.8.8.8` |
| Réseau back | `vback`, `10.0.30.0/24`, MTU 1450 |
| Stockages | `local-zfs` pour les disques, `cs-nfs` pour le partage |
| Pool | `cs-services` |
| Invités | `cs-dns` : `172.19.0.101`; `cs-web` : `172.19.0.102` et `10.0.30.102`; `cs-bdd` : `10.0.30.103` |
| Modèles | VM 900 sur `pve1`; modèle LXC Debian 13 sur `cs-nfs` |
| Comptes administrateurs cités | `tomy`, `jojo`, `momo`, `romain`, `soulay`, `matheo` |

Le fichier `.gitignore` exclut `fiche.yml`, les états `*.tfstate*`, le répertoire `.terraform`, les fichiers `*.tfvars`, les fichiers de configuration SSH, les fichiers PEM et les clés privées. À l’inverse, `fiche.exemple.yml` et `.terraform.lock.hcl` restent versionnés. Les secrets Ansible sont conservés dans `50-config/secrets.yml` chiffré par Ansible Vault; le mot de passe du coffre et les jetons API sont fournis localement au moment de l’exécution.

## 3. Hôtes et amorçage

### 3.1 Configuration des hôtes

Nous configurons les trois nœuds avec Ansible après leur réinstallation. Les tâches documentées portent sur les dépôts Proxmox sans abonnement au format deb822, la désactivation des dépôts entreprise, la mise à jour des paquets, le réglage de chrony sur `fr.pool.ntp.org`, l’ajout des noms courts et complets dans `/etc/hosts`, ainsi que l’installation de `dnsmasq` avec son service désactivé par défaut.

Sur le troisième nœud, nous préparons le jeu de données ZFS `rpool/nfs`, installons `nfs-kernel-server` et exportons le partage vers le seul réseau de gestion. Après les mises à jour, les nœuds doivent redémarrer avant la création du cluster afin de démarrer sur le noyau actualisé. La création manuelle du cluster `pve-cyber`, avec le lien 0 associé à l’adresse de gestion de chaque nœud, constitue la dernière opération manuelle de cette phase.

Le contrôle prévu vérifie que le second passage Ansible ne produit aucun changement, que `exportfs -v` affiche l’export NFS, que `systemctl is-enabled dnsmasq` répond `disabled` et que `pvecm status` indique un cluster quorate avec trois votes.

### 3.2 Couche `10-amorcage`

Cette couche est la seule à utiliser `root@pam`. Nous y créons le rôle personnalisé `CS-Tofu`, le compte `tofu@pve`, le compte `ansible@pve`, leurs jetons et les ACL associées. Chaque outil reçoit uniquement les droits nécessaires. Le jeton Ansible sert à la lecture de l’inventaire; il ne peut pas créer de ressources. Les sorties sensibles des jetons restent dans l’environnement local et ne sont jamais inscrites dans Git.

Avant l’application de cette couche, le pilote retire de son environnement tout ancien jeton OpenTofu afin que le provider s’authentifie bien avec `root@pam`. Après l’amorçage, nous supprimons le mot de passe root de l’environnement et utilisons le jeton OpenTofu pour les couches suivantes.

Le contrôle prévu appelle `/api2/json/version` avec les deux jetons et attend une réponse HTTP 200. Une requête de création de pool avec le jeton Ansible doit être refusée avec une réponse HTTP 403.

### 3.3 Validation hors ligne des couches B

Avant l’envoi des couches sur GitHub, le binôme B valide les dossiers `10-amorcage`, `20-socle` et `30-image` avec `tofu fmt`, `tofu init -backend=false` et `tofu validate`. La fiche locale est créée à partir de l’exemple avant cette vérification.

## 4. Socle Proxmox : stockage, SDN, droits et pare-feu

Dans `20-socle`, nous déclarons le stockage NFS `cs-nfs` en version 4.2. Il accepte les contenus nécessaires aux sauvegardes, aux images à importer, aux ISO, aux snippets et aux modèles de conteneurs. Les notes mentionnent également le modèle LXC Debian 13.

La couche configure deux zones SDN. La zone VXLAN `back` utilise le VNI 30030, les adresses de gestion des nœuds comme pairs et la MTU 1450. Elle fournit le VNet `vback` sur `10.0.30.0/24`, sans passerelle. La zone Simple `labo`, avec IPAM Proxmox et DHCP assuré par dnsmasq, fournit le VNet `vlabo` sur `10.0.99.0/24`, la passerelle `10.0.99.1`, le SNAT et la plage DHCP `10.0.99.100` à `10.0.99.150`.

Nous créons le pool `cs-services`, les groupes `admins-cs` et `direction-cs`, les comptes nominatifs, les comptes `direction@pve` et `supervision@pve`, ainsi qu’un jeton de lecture pour la supervision. Les notes prévoient aussi les ACL nécessaires sur `vmbr0`.

Le pare-feu reçoit les alias `net_lan` et `net_back`, l’IPSet `management` et les groupes de sécurité des invités. Le réseau des postes d’administration doit être présent dans l’IPSet avant l’activation du pare-feu. Les règles du cluster autorisent UDP 4789 depuis `net_lan` pour le VXLAN, TCP 111 et 2049 depuis `net_lan` pour NFS, ainsi que UDP 67 et 68 sur l’interface de la zone labo pour DHCP.

La matrice de flux décrite dans les notes B est la suivante :

| Cible | Flux | Source | Justification |
|---|---|---|---|
| Cluster | UDP 4789 | `net_lan` | VXLAN `vback`, VNI 30030 |
| Cluster | TCP 111 et 2049 | `net_lan` | NFS 4.2 `cs-nfs` |
| Cluster | UDP 67 et 68 | Interface `vlabo` | DHCP de la zone labo |
| `sg-web`, invité `cs-web` | TCP 80 et ICMP | Toutes les adresses | Accès HTTP à l’intranet et diagnostic réseau |
| `sg-web`, invité `cs-web` | TCP 22 | Groupe `noeuds` | Rebond SSH depuis les nœuds Proxmox |
| `sg-web`, invité `cs-web` | TCP 3142 | `10.0.30.103/32`, `cs-bdd` | Accès à `apt-cacher-ng` depuis le réseau back |
| `sg-dns`, invité `cs-dns` | UDP et TCP 53 | `net_lan` | Résolution DNS interne |
| `sg-dns`, invité `cs-dns` | TCP 22 | Groupe `noeuds` | Rebond SSH depuis les nœuds Proxmox |
| `sg-bdd`, invité `cs-bdd` | TCP 3306 et TCP 22 | `10.0.30.102/32`, `cs-web` | MariaDB et rebond SSH depuis `cs-web` |

Une vérification temporaire du VNet `vlabo` consiste à déclarer un conteneur de test, confirmer qu’il reçoit une adresse DHCP et qu’il peut exécuter `apt update` pare-feu actif, puis à retirer la ressource de test du code et à réappliquer la couche.

Les documents B utilisent les noms `sg-web`, `sg-dns` et `sg-bdd`. Une partie des notes C cite provisoirement `gs-web`, `gs-dns` et `gs-bdd`. Nous retenons les noms `sg-*` employés par le TP et la couche B comme convention commune.

## 5. Image maître Debian 13

Dans `30-image`, nous téléchargeons l’image `debian-13-genericcloud-amd64.qcow2` dans `cs-nfs`, qui autorise le contenu `import`. Nous déclarons le modèle 900 `tpl-debian13` à partir de cette image. Le TP demande un processeur `x86-64-v2-AES`, un contrôleur VirtIO SCSI single, un lecteur Cloud-Init et l’agent QEMU actif dans les clones.

L’image Cloud Debian ne contenant pas l’agent QEMU, une vendor-data Cloud-Init doit l’installer et démarrer son service lors du premier démarrage. Les notes B référencent `/rpool/nfs/snippets/vendor-agent.yml` et supposent sa présence sur `pve3`; elles attribuent son dépôt à la couche 00 par Ansible. Le TP précise que le provider peut déposer un fichier snippet par SSH sur les nœuds. Nous devons garder une seule méthode automatisée dans le dépôt et expliquer le rôle de l’outil choisi.

Le contrôle du modèle vérifie la configuration de la VM 900, puis crée temporairement un clone, le démarre, attend l’installation de l’agent QEMU et interroge ses interfaces réseau. Après le contrôle, le clone temporaire est arrêté et supprimé. Lorsqu’une nouvelle image Debian est publiée, les notes B reconstruisent l’image en forçant le remplacement de la ressource de téléchargement et du modèle.

## 6. Modules OpenTofu et invités

### 6.1 Modules `vm` et `ct`

Nous avons conçu deux modules réutilisables. Le module VM reçoit le nom, le VMID, le nœud préféré, le modèle, les cartes réseau, le groupe de sécurité, les étiquettes, le stockage et le pool, le dimensionnement CPU, mémoire et disque, ainsi que les paramètres DNS, domaine, utilisateur et Cloud-Init. Les informations de clé SSH et de mot de passe sont des variables sensibles.

Le module VM réalise un clone complet du modèle 900 vers `local-zfs`. Le clonage commence sur le nœud du modèle, puis la VM rejoint son nœud préféré. Les cartes réseau sont générées à partir de la liste fournie, avec le pare-feu activé. Cloud-Init configure l’utilisateur `admin`, la clé publique, le mot de passe console, les adresses IP, le DNS et le domaine. Le lecteur Cloud-Init est placé sur `local-zfs`; l’agent QEMU est activé. Le pare-feu de l’invité applique une politique d’entrée `DROP` et le groupe de sécurité associé. Les sorties exposent le VMID, le nom et les adresses.

Le module conteneur crée un invité non privilégié avec nesting activé. Il utilise un modèle LXC situé sur `cs-nfs`, place le disque racine sur `local-zfs` et installe la clé SSH dans le compte root pour permettre la connexion Ansible.

Les deux modules valident les VMID de 100 à 899, les noms en minuscules sans accent et la présence d’au moins une étiquette de rôle en minuscules. Les contrôles négatifs prévus utilisent le VMID 950 puis le nom `CS-Web`; le plan doit refuser ces valeurs sans créer de ressource. Les contrôles positifs vérifient l’appartenance au pool, les étiquettes, le pare-feu sur les cartes et la politique d’entrée `DROP`.

### 6.2 Couche `40-services`

Nous déclarons les trois invités à l’aide des modules :

| Invité | Type | VMID | Nœud préféré | Ressources indiquées | Réseau | Étiquettes |
|---|---|---:|---|---|---|---|
| `cs-dns` | Conteneur | 101 | `pve1` | 512 Mio de mémoire, disque de 4 Gio | Front `172.19.0.101/16` | `cyber`, `dns` |
| `cs-web` | VM | 102 | `pve2` | 1 Gio de mémoire, disque de 9 Gio | Front `172.19.0.102/16`; back `10.0.30.102/24` sans passerelle | `cyber`, `web` |
| `cs-bdd` | Conteneur | 103 | `pve3` | 1 Gio de mémoire, disque de 8 Gio | Back uniquement `10.0.30.103/24` | `bdd`, `cyber` |

Les notes du binôme C justifient un disque de 9 Gio pour `cs-web` par l’ajout de 6 Gio au disque de 3 Gio du modèle. Elles indiquent 1 Gio de mémoire pour `cs-bdd`. Elles comparent ces choix aux valeurs du premier TP. L’heure de sauvegarde y est également indiquée à 01 h, contre 21 h dans le TP initial. Nous présentons ces différences comme des écarts documentés à vérifier contre le dossier d’exploitation du premier TP.

### 6.3 Sauvegarde, réplication et haute disponibilité

La ressource `sauvegarde-nuit` sauvegarde le pool `cs-services` sur `cs-nfs` à 01 h en mode snapshot, avec compression zstd, sept rétentions quotidiennes et quatre hebdomadaires. Nous déclarons six réplications exécutées toutes les deux minutes, chaque invité étant répliqué vers les deux autres nœuds. Trois ressources HA restent à l’état `started` : `ct:101`, `vm:102` et `ct:103`. Trois règles d’affinité de type `node-affinity` donnent la priorité 2 au nœud préféré et 1 aux autres, avec `strict` désactivé.

Après une bascule HA, l’invité peut fonctionner sur un nœud différent de celui indiqué dans le code et la réplication peut changer de sens. Le module C ignore les changements de `node_name` afin qu’OpenTofu ne recrée pas la VM après un déplacement HA. Ce choix doit être conservé avec son explication dans la note d’architecture.

### 6.4 Accès aux paquets de `cs-bdd`

Le TP impose que `cs-bdd`, qui ne possède qu’une interface back, puisse installer ses paquets sans devenir accessible depuis le réseau front. Les notes B proposent `apt-cacher-ng` sur `cs-web`, au port TCP 3142, avec une règle entrante limitée à l’adresse back de `cs-bdd`. Les documents ne décrivent pas le déploiement effectif du cache ni la configuration du client. Nous ne pouvons donc pas conclure que ce mécanisme a été installé; le rapport conserve la proposition comme choix à justifier dans les fichiers de configuration et les règles de pare-feu.

## 7. Configuration Ansible des services

Le TP décrit une couche Ansible `50-config` avec inventaire dynamique `community.proxmox.proxmox`. Les faits des invités doivent être demandés pour construire les groupes à partir des étiquettes. La connexion aux invités utilise des rebonds SSH : un nœud Proxmox pour `cs-dns` et `cs-web`, puis `cs-web` pour atteindre `cs-bdd` sur le réseau back.

Les trois rôles attendus configurent Unbound pour `cybersadiver.lan`, Nginx pour la page « Intranet CyberSadiver » et le client MariaDB, puis MariaDB sur `10.0.30.103` avec la base `intranet` et un utilisateur web limité à `10.0.30.102`. Les mots de passe de base sont conservés dans Ansible Vault. Le playbook est exécuté deux fois; le second passage doit afficher `changed=0`. Les contrôles fonctionnels interrogent le DNS depuis un poste d’administration, consultent la page intranet et vérifient l’accès de `cs-web` à la base.

Les fichiers Markdown fournis détaillent les couches 10 à 40, mais ne comportent pas la mise en œuvre complète des rôles Ansible de l’étape 7. Nous avons donc distingué ici les exigences du TP des éléments effectivement décrits dans les notes des binômes.

## 8. Contrôles, diagnostic et reconstruction

Les notes B prescrivent un second plan OpenTofu après application des couches 20 et 40; le résultat attendu est `No changes`. La vérification VXLAN interroge `vxlan_vback` sur les trois nœuds, puis consulte le SDN et l’état du pare-feu. Les diagnostics du pare-feu comprennent la compilation des règles, la lecture du groupe `sg-bdd` et les journaux du service `pve-firewall`.

Pour l’étape 8, le binôme C prévoit de chronométrer la destruction de `40-services`, le nettoyage des copies de réplication orphelines par le playbook de nettoyage, puis la recréation de la couche et la vérification d’un plan sans changement. Pour détruire le socle, nous détruisons d’abord les services et l’image; nous désactivons ensuite le pare-feu du centre de données avant de détruire `20-socle`. Cette précaution évite de couper les flux NFS, VXLAN et l’accès d’administration au milieu de la destruction.

La reconstruction complète rejoue `10-amorcage`, `20-socle`, `30-image`, `40-services` et `50-config` après la préparation des hôtes, en respectant l’ordre du README. Les sources prévoient de vérifier les contrôles 3 à 7 et de relever les durées de chaque couche. Elles ne donnent aucune durée, sortie de commande ni capture; nous ne déclarons donc pas ces contrôles réussis sans ces preuves.

Le test de dérive décrit dans les notes modifie temporairement la mémoire de `cs-web` et une règle de `sg-web` dans l’interface Proxmox, puis constate les écarts avec les plans OpenTofu et rétablit la configuration déclarée. Cette intervention est limitée à la démonstration demandée à l’étape 8. OpenTofu ne détecte pas les modifications internes aux invités, comme des paquets ou fichiers changés à la main, ni les ressources créées hors de son état.

## 9. Historique, incidents et coordination

Nous avons organisé l’historique Git en petits commits consacrés au squelette du dépôt, à la fiche exemple, aux modules et à la couche `40-services`. Les notes C rapportent trois incidents : un refus HTTP 403 lors d’un premier envoi GitHub lié à l’utilisation d’un compte différent de celui du dépôt; un refus de l’authentification Git par mot de passe, remplacée par un jeton personnel; enfin, un dépôt qui ne contenait que le README parce que les autres dossiers n’avaient pas encore été ajoutés et poussés.

La coordination des binômes suit les dépendances du TP. Le binôme C prépare l’arborescence et la fiche exemple; le binôme A valide le cluster et le NFS avant l’amorçage; le binôme B transmet ensuite les jetons, le pool et les groupes de sécurité; le modèle 900 est remis au binôme C pour les services. Le binôme A prend en charge la configuration Ansible et confirme le snippet Cloud-Init. Les contrôleurs conservent les preuves des contrôles et le chronométreur consigne les durées de reconstruction.

## Annexe — arborescence et procédures opérationnelles

### Arborescence détaillée

Le dépôt `5VIRTDC_TP2` comprend la fiche exemple, les dossiers `00-hotes`, `10-amorcage`, `20-socle`, `30-image`, `40-services` et `50-config`, ainsi que `modules/vm` et `modules/ct`. La couche 10 comprend le provider, la déclaration du rôle et des identités, ainsi que son verrou de provider. La couche 20 comprend le provider, les variables, les fichiers de stockage, SDN, droits et pare-feu, les sorties et le verrou. La couche 30 comprend le provider, la ressource de téléchargement et le modèle, ainsi que son verrou. La couche 40 comprend le provider, les variables, les valeurs locales, les services, l’exploitation et les sorties. Chaque module comporte son fichier principal, ses variables et ses sorties.

Dans `40-services`, les ressources de sauvegarde, de réplication et de haute disponibilité se trouvent dans `exploitation.tf`. Les ressources des trois invités se trouvent dans `services.tf`. Les valeurs locales relient la fiche du cluster aux groupes de sécurité. La structure de fichiers est partagée entre les binômes afin que chaque couche puisse être exécutée depuis son dossier.

### Historique Git et contrôle du dépôt

Nous avons organisé les commits en quatre ensembles : squelette du dépôt et `.gitignore`, fiche exemple, modules OpenTofu `vm` et `ct`, puis couche `40-services`. Nous vérifions le contrôle 0 après l’initialisation de la couche : `git status` doit rester propre et la recherche des termes relatifs aux jetons, mots de passe et secrets dans `git log -p` ne doit révéler aucune valeur confidentielle.

### Validation et déploiement des couches

Avant le déploiement, le binôme B formate et valide chaque couche avec `tofu -chdir=10-amorcage fmt`, `tofu -chdir=20-socle fmt` et `tofu -chdir=30-image fmt`, puis initialise chacune avec `init -backend=false` et exécute `validate`. Le contrôle des modules initialise `modules/vm` et `modules/ct` sans backend, puis valide leurs configurations. Les cas VMID 950 et nom `CS-Web` sont présentés au plan pour confirmer le refus des valeurs invalides.

Pour l’amorçage, le pilote initialise `10-amorcage`, relit le plan, puis applique la couche avec le compte root. Il récupère ensuite les sorties sensibles `jeton_tofu` et `secret_ansible` directement dans son environnement. Les requêtes API confirment l’authentification de chaque jeton; une tentative de création de pool avec le jeton Ansible doit être refusée. Le pilote bascule ensuite sur le jeton OpenTofu et retire le mot de passe root de son environnement.

Pour le socle, le pilote fournit localement le mot de passe initial des comptes, initialise `20-socle`, relit le plan, applique la couche puis relance le plan. Il inspecte le VXLAN `vback` sur les trois nœuds, les VNets SDN et l’état du pare-feu. Le contrôle complémentaire déploie un LXC temporaire sur `vlabo`, vérifie son bail DHCP et l’accès aux dépôts, puis retire cette ressource temporaire du code.

Pour l’image, le pilote confirme que le snippet Cloud-Init existe sur le partage, initialise `30-image` et applique la couche. Il consulte la configuration de la VM 900 et effectue le test de clonage prévu. Après vérification de l’adresse remontée par l’agent QEMU, le clone de contrôle est arrêté et supprimé. Lorsqu’une nouvelle image Debian est retenue, le plan force le remplacement de la ressource de téléchargement puis du modèle.

Pour les services, le pilote initialise `40-services`, relit le plan, applique la couche et produit un second plan. Les contrôles consultent `pvesr status` pour les six réplications, `ha-manager status` pour les trois ressources HA et la configuration Proxmox des invités pour le pool, les étiquettes, la politique d’entrée et l’activation du pare-feu sur les interfaces. Les notes indiquent aussi des vérifications de connectivité de l’agent QEMU et de l’état Cloud-Init pour diagnostiquer un démarrage lent de `cs-web`.

### Choix techniques consignés

Nous retenons un clone complet pour rendre les disques compatibles avec la réplication et plaçons les disques ainsi que le lecteur Cloud-Init sur `local-zfs`. Le modèle 900 étant hébergé sur `pve1`, le module effectue le clonage sur ce nœud avant de rejoindre le nœud préféré. Le cycle de vie ignore le changement de nœud après un déplacement HA.

Les notes C indiquent que le disque de `cs-web` comprend le disque de 3 Gio du modèle et une extension de 6 Gio, pour un total de 9 Gio. Elles indiquent 1 Gio de mémoire pour `cs-bdd`, une sauvegarde à 01 h avec quatre rétentions hebdomadaires, et une MTU héritée du pont pour la carte VM de `vback` tandis que le conteneur utilise 1450. Ces valeurs sont des décisions consignées dans les notes C; leur comparaison avec le cahier d’exploitation du premier TP reste nécessaire pour expliquer les écarts.

Les notes précisent que les noms longs du provider `proxmox_virtual_environment_*` sont utilisés pour les ressources VM, conteneur et pare-feu, tandis que les formes courtes `proxmox_*` servent aux ressources de sauvegarde, de réplication et de haute disponibilité.

### Incidents signalés

Lors d’un premier envoi GitHub, le dépôt a refusé l’accès car Git et l’éditeur utilisaient un compte différent du compte propriétaire du dépôt. L’équipe a corrigé l’identité mémorisée et poussé avec le compte autorisé. Une tentative d’authentification Git par mot de passe a ensuite échoué, car GitHub n’accepte plus ce mode; l’équipe a utilisé un jeton d’accès personnel disposant du droit de dépôt. Enfin, un dépôt qui ne contenait que le README a été complété en ajoutant, validant et poussant les autres dossiers.

### Ordre de destruction documenté

La destruction des services précède celle de l’image. Nous supprimons ensuite les copies de réplication orphelines par le playbook de nettoyage. Avant de détruire le socle, nous appliquons d’abord la configuration qui désactive le pare-feu du centre de données; nous lançons seulement après la destruction de `20-socle`. L’amorçage est conservé. La reconstruction reprend les couches dans l’ordre indiqué dans le rapport, puis reconfigure les services avec Ansible. Les documents ne fournissent pas de chronométrage rempli ni de sorties de reconstruction.
## Conclusion

Nous avons rassemblé les trois contributions dans un seul rapport continu : préparation du dépôt, amorçage, socle Proxmox, image maître, modules, services, sécurité, exploitation, incidents et reconstruction. Les paramètres et procédures sont maintenant présentés dans le même ordre que l’exécution du cluster. Les divergences relevées portent sur la version verrouillée du provider, les noms provisoires `gs-*` ou `sg-*`, le dépôt du snippet Cloud-Init, l’accès aux paquets de `cs-bdd` et les écarts de valeurs héritées du premier TP. Les comptes rendus et preuves d’exécution restent nécessaires pour attester les contrôles et les temps de reconstruction.
