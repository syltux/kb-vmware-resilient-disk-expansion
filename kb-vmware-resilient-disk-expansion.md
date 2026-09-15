# KB0001 : Remplacement et agrandissement d'un disque virtuel sans casser les Snapshots (VMware Workstation Pro 26H1)

## Contexte et objectif
Sur une machine virtuelle (dans notre cas un serveur sous Windows Server 2022, mais cela s'applique pour toute VM), le besoin est d'augmenter la capacité d'un disque de données (par exemple de 40 Go à 200 Go).
**Contrainte majeure :** Il est fortement déconseillé de modifier la taille du disque virtuel directement via VMware si la VM possède des snapshots. L'extension directe brise la chaîne de snapshots existante ou est tout simplement grisée (c'était le cas ici, impossible car snapshots présentes).

**Stratégie:** La solution "safe" consiste à créer un nouveau disque plus grand, migrer les données en interne, inverser les lettres de lecteur, puis détacher virtuellement l'ancien disque sans supprimer ses fichiers physiques afin de préserver la possibilité de rollback des snapshots existantes.

## Point d'attention : vérification des chemins et contrôleurs
Avant toute manipulation dans les paramètres VMware, il est crucial d'identifier précisément vos disques pour éviter de supprimer le disque système ou de provoquer une erreur d'amorçage (BSOD `INACCESSIBLE_BOOT_DEVICE`) :
* **Vérifier le chemin du fichier (`.vmdk`) :** Si la VM a des snapshots, le disque actif pointe vers un fichier de type `NomDeLaVM-00000x.vmdk`. Notez bien quel fichier correspond au disque Système (`C:`) et quel fichier correspond au disque de Données. Pour ce faire: Paramètres > Matériel et sur chaque disque consulter "Fichier de disque".
* **Vérifier le type de contrôleur :** Repérez si le disque à remplacer est monté en **NVMe**, **SCSI** ou **SATA**. Lors de l'ajout ou de la réimportation d'un disque, il faut impérativement respecter le contrôleur d'origine sous peine de plantage système au démarrage.

---

## Procédure de migration étape par étape

### Étape 1 : Préparation matérielle de la VM (VM Éteinte)
1. Ouvrir les paramètres (Settings) de la machine virtuelle sous VMware.
2. Identifier le disque de données actuel à remplacer (ex: 40 Go). **Le laisser branché.**
3. **Ajouter** un nouveau disque dur virtuel avec la nouvelle capacité désirée (ex: 200 Go). Assurez-vous d'utiliser un type de contrôleur cohérent avec votre architecture (ex: NVMe).
4. *À ce stade, la VM possède simultanément son disque système, l'ancien disque de données et le nouveau disque de données.*
5. Démarrer la machine virtuelle.

### Étape 2 : préparation des disques

#### Disque d'origine des données

1. Ouvrir une console **PowerShell en tant qu'Administrateur**.
2. Fermer les applications (ex: Gestionnaire de serveur) et arrêter temporairement les services (via `services.msc`) exploitant le disque de données (WDS, WSUS, IIS...) pour libérer les fichiers. 

Pour ce faire utiliser les commande suivante:

```powershell
# Pour récupérer les services en cours d'exécution:
Get-Service | Where-Object Status -eq 'Running'
# Pour arrêter les services identifiés:
`Stop-Service -Name "NomDuServiceAArrêter" -Force`
```
NB: Un script `startstopprocess.ps1`est disponible si besoin.

NB: Vu qu'il n'existe pas de commande permettant de s'assurer qu'on arrête bien tous les processus serveurs en cours en une fois ainsi que tout ce qui écrit sur le disque sans rien oublier, on va inverser la logique en rendant le disque DATA E:\ accessible en Read-Only après avoir fermé le Gestionnaire de serveur.

- Etape 1: Gestion de l'ordinateur > Gestion des disques. Repérer le numéro de disque dans le Gestionnaire et ajuster le paramètre dans la console en fonction:
- Etape 2: ajuster le paramètre "-Number N" avec le numéro de disque repéré puis exécuter la commande suivante:

**ATTENTION de bien vérifier de ne pas cibler par erreur le disque C: !**

```powershell
Set-Disk -Number N -IsReadOnly $true 
```
Le disque DATA est maintenant en lecture seule !


#### Disque de destination (le nouveau)

3. Identifier le numéro du nouveau disque et s'assurer qu'il n'est pas en lecture seule (sécurité Windows sur les nouveaux disques SAN/virtuels), puis l'initialiser et le formater :

- Ouvrir Gestion de l'ordinateur > Gestion des disques. 
Une fenêtre pop-up devrait apparaître automatiquement demandant d'initialiser le nouveau disque (sinon clic droit sur le bandeau noir). Choisis GPT (recommandé) et valide.
- Repère ton nouveau disque (il sera affiché en noir avec la mention "Non alloué").
- Fais un clic droit sur cet espace non alloué > Nouveau volume simple...
- Suis l'assistant :
* Taille : Laisse le maximum.
* Lettre de lecteur : Attribue-lui une lettre temporaire, par exemple F:.
* Formatage : Choisis NTFS, taille d'allocation par défaut, et donne-lui le nom DATA_NEW (pour bien le repérer) ou laisse simplement DATA (le label n'a pas d'incidence, seule la lettre de lecteur compte pour le système). Coche "Effectuer un formatage rapide".
- Termine l'assistant.

Alternative à la console:

```powershell
# Remplacer 'X' par le numéro du nouveau disque (visible via Get-Disk)
Set-Disk -Number X -IsReadOnly $false
Initialize-Disk -Number X -PartitionStyle GPT
New-Partition -DiskNumber X -DriveLetter F -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel "DATA" -Confirm:$false
```


### Étape 3 : Migration des données (PowerShell)
Exécuter un Robocopy complet de l'ancien lecteur (ex: E:) vers le nouveau lecteur temporaire (F:) :

(Remplacer par les lettres de lecteur d'origine et de destination qui correspondent à votre VM)
```powershell
robocopy E:\ F:\ /MIR /COPYALL /DCOPY:DAT /B /R:3 /W:3
```

Explication des paramètres:

/MIR : Mode miroir, copie tout et supprime sur la destination ce qui n'existe plus sur la source.
/COPYALL : Copie toutes les informations des fichiers (Données, Attributs, Horodatages, ACL/Droits NTFS, Propriétaire, Infos d'audit). Très important pour ne pas casser les droits.
/DCOPY:DAT : Copie les attributs et horodatages des dossiers.
/B : Copie les fichiers en mode Sauvegarde (Backup mode). Permet de contourner les restrictions de droits NTFS (Accès refusé) en utilisant les privilèges d'administrateur.
/R:3 /W:3 : Réessaie 3 fois avec 3 secondes d'attente si un fichier est verrouillé (évite que la commande bloque indéfiniment).


### Étape 4 : Bascule des lettres de lecteur (PowerShell)
Toujours dans la console PowerShell (Administrateur), inverser les lettres pour que le nouveau disque prenne le relais de la production :

```powershell
# 1. On retire la lettre E: de l'ancien disque et on lui donne la lettre Z: (ou on la supprime)
Get-Partition -DriveLetter E | Set-Partition -NewDriveLetter Z

# 2. On attribue la lettre E: au nouveau disque de 200 Go
Get-Partition -DriveLetter F | Set-Partition -NewDriveLetter E
```

On repasse l'ancien disque en écriture:

```powershell
Set-Disk -Number N -IsReadOnly $false
```

Éteindre ensuite proprement la machine virtuelle.

### Étape 5 : Nettoyage et préservation des Snapshots VMware

1. Retourner dans les paramètres matériels de la VM sous VMware.
2. Sélectionner l'ancien disque de données (celui de 40 Go). Vérifier avant suppression d'être sur le bon disque (cf. intro de la KB).
NB: en cas de suppression involontaire ou erronée il est toujours possible de réimporter le disque en ciblant le bon .vmdk.
3. Cliquer sur **Supprimer (Remove)**.

🛑 **RÈGLE D'OR : Ne JAMAIS cocher l'option de suppression des fichiers sur le disque dur physique si l'hyperviseur le demande.**

**Explication :** Faire un "Remove" simple détache le disque de la configuration de la VM, mais laisse le fichier de base `.vmdk` et ses snapshots (`-00000x.vmdk`) sur votre PC. Ainsi, la chaîne de vos anciens snapshots reste parfaitement valide et exploitable en cas de restauration.

Valider (**OK**).

### Étape 6 : Validation finale et Snapshot

1. Démarrer la machine virtuelle.
2. Vérifier dans l'explorateur que le lecteur E: correspond bien à la nouvelle volumétrie (200 Go) et contient toutes les données.
3. Relancer les services ou vérifier sur le tableau de bord (Gestionnaire de serveur) que les rôles démarrent correctement et que tout est au vert.
4. Prendre un nouveau Snapshot pour figer ce nouvel état fonctionnel (ex: `12 DISK RESIZE SUCCESSFULL`).
