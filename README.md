# Rapport de redéploiement de l’infrastructure CyberSadiver en code

## Synthèse

Nous avons défini une reconstruction du cluster Proxmox VE 9 `pve-cyber`, composé de trois nœuds, à partir d’un dépôt Git. OpenTofu décrit les ressources Proxmox et Ansible configure les hôtes et les services. Le dépôt est organisé en couches exécutées dans un ordre stable, depuis la configuration des hôtes jusqu’aux services.

Notre démarche vise à rendre l’infrastructure reproductible, à limiter les secrets exposés et à réduire les interventions manuelles. Les seules opérations prévues hors code sont l’installation initiale de Proxmox, la copie de la clé SSH et la création du cluster. L’état OpenTofu étant local, un seul poste pilote effectue les changements sur le cluster.

## 1. Organisation du dépôt

Nous avons réparti le dépôt en six couches : `00-hotes` configure les nœuds avec Ansible; `10-amorcage` crée les identités et jetons API; `20-socle` déclare le stockage, le réseau, les droits et le pare-feu; `30-image` construit le modèle Debian; `40-services` déploie les invités et leur exploitation; enfin, `50-config` configure les services avec Ansible. Les modules `vm` et `ct` regroupent les paramètres communs aux machines virtuelles et aux conteneurs.

L’ordre de reconstruction est donc `00-hotes`, `10-amorcage`, `20-socle`, `30-image`, `40-services`, puis `50-config`. Lors d’une reconstruction complète, nous conservons la couche d’amorçage et rétablissons les couches suivantes dans cet ordre.

## 2. Gestion des paramètres et des secrets

Nous avons retenu `fiche.exemple.yml` comme modèle versionné des paramètres propres au cluster. Le pilote en crée une copie locale, `fiche.yml`, qui contient les adresses, les noms et les réseaux réels. Cette copie n’est pas envoyée dans Git. Les états OpenTofu, les dossiers `.terraform`, les fichiers de variables réels et les clés privées sont également exclus du dépôt.

Les secrets Ansible sont conservés dans un fichier chiffré par Ansible Vault. Le mot de passe du coffre et les jetons Proxmox restent hors du dépôt. La couche d’amorçage utilise temporairement le compte `root@pam`; après la création des identités techniques, OpenTofu et Ansible utilisent chacun leur propre jeton. Le jeton Ansible est limité à la lecture nécessaire à l’inventaire, tandis que le jeton OpenTofu reçoit les droits de gestion requis par les ressources déclarées.

Le README fourni indique OpenTofu 1.13.9, Ansible 2.20.1 et le provider `bpg/proxmox` 0.123.1. Une note du binôme C rapporte toutefois une validation avec la version 0.124.0. Nous retenons la version verrouillée dans les fichiers du dépôt comme référence opérationnelle; les documents seuls ne permettent pas de confirmer que cette version verrouillée correspond bien à 0.123.1.

## 3. Préparation des hôtes et amorçage

Nous configurons les trois hôtes avec Ansible : dépôts Proxmox sans abonnement, mises à jour, synchronisation de l’heure avec `fr.pool.ntp.org`, noms des nœuds dans `/etc/hosts` et installation de `dnsmasq` avec son service par défaut désactivé. Le troisième nœud héberge le partage NFS dans `rpool/nfs`, exporté vers le réseau de gestion.

Après cette configuration, nous créons le cluster `pve-cyber` en reliant chaque nœud à son adresse de gestion. Le contrôle attendu confirme un cluster quorate à trois votes, un export NFS présent et un second passage Ansible sans changement. Les notes décrivent ces vérifications, mais ne contiennent pas leurs sorties de commande.

La couche `10-amorcage` crée le rôle OpenTofu, les comptes `tofu@pve` et `ansible@pve`, leurs jetons et les droits associés. Nous vérifions l’authentification des deux jetons par l’API Proxmox et l’impossibilité pour le jeton Ansible de créer une ressource.

## 4. Socle Proxmox et image Debian

Dans `20-socle`, nous déclarons le stockage partagé `cs-nfs` en NFS 4.2. Il accueille les sauvegardes, les images à importer, les ISO, les modèles de conteneurs et les snippets. Nous configurons le réseau VXLAN `vback` avec le VNI 30030, le réseau `10.0.30.0/24` et une MTU de 1450. La zone Simple `labo` fournit le VNet `vlabo`, le réseau `10.0.99.0/24`, la passerelle `10.0.99.1`, le SNAT et une plage DHCP allant de `10.0.99.100` à `10.0.99.150`.

La même couche crée le pool `cs-services`, les groupes et comptes Proxmox, les droits de supervision, les alias et l’IPSet `management`. Le pare-feu du centre de données n’est activé qu’avec les adresses des postes d’administration et les flux nécessaires au NFS, au VXLAN et au DHCP. Les règles des groupes `sg-web`, `sg-dns` et `sg-bdd` limitent les accès aux ports et aux sources définis pour chaque service.

Dans `30-image`, nous téléchargeons l’image Debian 13 Cloud et déclarons le modèle `900`, nommé `tpl-debian13`. Le modèle utilise un disque importé depuis `cs-nfs`, Cloud-Init et l’agent QEMU. Les notes prévoient le déploiement d’un fichier vendor-data qui installe et démarre l’agent au premier démarrage des clones. Elles citent un fichier situé dans `/rpool/nfs/snippets` et un dépôt automatisé par Ansible; le TP décrit aussi le dépôt du snippet par le provider en SSH. La méthode effectivement retenue doit rester identique dans le code, la procédure et le compte rendu final.

## 5. Modules et services

Nous utilisons un module OpenTofu pour les machines virtuelles et un autre pour les conteneurs non privilégiés. Ils partagent les paramètres d’identité, de ressources, de cartes réseau, de groupe de sécurité et d’étiquettes. Les modules refusent les VMID hors de la plage 100 à 899, les noms qui ne sont pas en minuscules et les invités sans étiquette de rôle. Chaque invité rejoint le pool `cs-services`, reçoit une politique d’entrée restrictive et active le pare-feu sur ses interfaces.

La couche `40-services` déclare trois invités : `cs-dns`, un conteneur sur le premier nœud avec une interface front; `cs-web`, une machine virtuelle clonée du modèle 900 sur le deuxième nœud avec une interface front et une interface `vback`; et `cs-bdd`, un conteneur non privilégié sur le troisième nœud, relié uniquement au réseau `vback`. L’adresse de `cs-web` sur le réseau back est `10.0.30.102`; celle de `cs-bdd` est `10.0.30.103`.

Nous déclarons également une sauvegarde nocturne du pool `cs-services` vers `cs-nfs`, exécutée à 01 h en mode snapshot avec compression zstd, sept sauvegardes quotidiennes et quatre hebdomadaires. Six tâches de réplication transfèrent chaque invité vers les deux autres nœuds toutes les deux minutes. Trois ressources HA et trois règles d’affinité expriment les nœuds préférés.

Le document C indique des choix de dimensionnement différents du premier TP pour `cs-web` et `cs-bdd`, ainsi qu’une heure de sauvegarde différente. Ces différences doivent être rapprochées du dossier d’exploitation du premier TP pour être présentées comme des décisions d’architecture plutôt que comme des écarts implicites.

## 6. Configuration des services et accès réseau

La cible fonctionnelle décrite par le TP comprend la résolution DNS de `cybersadiver.lan` par `cs-dns`, une page intranet servie par Nginx sur `cs-web` et une base MariaDB `intranet` sur `cs-bdd`. Ansible doit configurer ces services, établir les connexions par rebond SSH et utiliser Ansible Vault pour les mots de passe de base de données. L’inventaire dynamique Proxmox doit demander les faits des invités afin de former les groupes à partir des étiquettes.

Le TP exige aussi que `cs-bdd` puisse installer ses paquets sans devenir joignable depuis le réseau front. La note du binôme B évoque `apt-cacher-ng` sur `cs-web`, accessible depuis l’adresse back de `cs-bdd`. Les documents transmis ne décrivent pas le déploiement de ce cache ni la configuration du client; ils ne permettent donc pas de confirmer que ce flux est opérationnel. La solution retenue doit limiter les règles de pare-feu aux seuls échanges nécessaires.

## 7. Contrôles et reconstruction

Les contrôles prévus portent sur la validation OpenTofu, l’authentification et les droits des jetons, l’idempotence des couches, le réseau VXLAN, le DHCP sur `vlabo`, le modèle Debian, les validations des modules, les trois invités, les réplications, les ressources HA et les services Ansible. Pour la reconstruction, les notes détaillent une destruction puis une recréation de `40-services`, ainsi qu’une procédure de destruction ordonnée du modèle et du socle. Elles rappellent de désactiver d’abord le pare-feu avant de détruire le socle.

Après une bascule HA, le nom du nœud courant peut différer de celui déclaré. Le module C ignore cette différence pour éviter qu’OpenTofu ne recrée la machine. Ce choix doit être expliqué avec son effet sur le placement et les tâches de réplication. Le TP demande également une démonstration ponctuelle de dérive : nous modifions temporairement une valeur dans Proxmox, constatons l’écart avec un plan OpenTofu, puis rétablissons la configuration déclarée. Cette manipulation constitue un test encadré, et non une méthode d’exploitation.

Les documents fournis décrivent les contrôles et les procédures, mais ne contiennent ni sorties de commande, ni captures, ni durées de reconstruction. Nous ne présentons donc pas les contrôles comme réussis sur la seule base de ces textes. Les preuves d’exécution sont nécessaires pour établir le résultat effectif et le temps de reconstruction.

## 8. Cohérence documentaire

Nous avons relevé trois divergences à résoudre dans le dépôt et ses documents : le provider est indiqué en version 0.123.1 dans le README et les notes B, tandis que les notes C mentionnent une validation en 0.124.0; les groupes de sécurité sont nommés `sg-*` dans le TP et les notes B, mais `gs-*` dans une partie des notes C; enfin, le dépôt du snippet Cloud-Init est attribué à des mécanismes différents selon les textes. La configuration effective du dépôt doit servir de référence unique pour ces trois points.

## Conclusion

Nous avons structuré le redéploiement autour de couches réutilisables, d’une source unique pour les paramètres locaux et de jetons distincts pour les outils. L’architecture couvre les hôtes, le socle Proxmox, l’image Debian, les services, leur exploitation et leur configuration. Les documents définissent les principaux contrôles et les choix techniques; ils ne fournissent pas les preuves d’exécution nécessaires pour conclure que la reconstruction complète a été validée. Notre rapport distingue donc les décisions et procédures documentées des résultats qui nécessitent encore des traces vérifiables.
