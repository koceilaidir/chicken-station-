# Chicken Station — Caisse & gestion

Application Windows de caisse et de gestion pour le fast-food Chicken Station (Burger & Tacos).
Developed by Minerva — +213 782 05 51 93 — koceilaidir92@gmail.com

**Version 0.3.** Caisse (commandes en attente, annulations tracées), clôture, coffre, compta (objectif du mois, écarts), stock (fiches techniques, réceptions, inventaire), achats (fournisseurs, dettes) et paie, menu, réglages (utilisateurs avec règles de droits, activité, sauvegarde chiffrée, matériel, impressions, plein écran et démarrage avec Windows).

L'écran **Matériel** sert à régler et tester :

| Appareil | Liaison | Comment on le pilote |
|---|---|---|
| Imprimante ticket POSLUX 80 mm | USB | Octets ESC/POS envoyés en « RAW » par le spouleur Windows |
| Imprimante cuisine POSLUX 80 mm | Câble réseau | Connexion TCP sur le port 9100 |
| Tiroir-caisse riva | Prise RJ11 sur l'imprimante ticket | Commande ESC/POS `ESC p` envoyée à l'imprimante ticket |
| Écran client POSLUX | Port COM (série ou USB-série) | Protocole LED 8 chiffres, CD5220 ou Epson (au choix) |

Aucun paquet tiers pour le matériel : tout passe par `dart:ffi` vers `winspool.drv` et `kernel32.dll`, ce qui évite les incompatibilités de versions.

---

## 1. Préparer le PC de développement (une seule fois)

1. Installer **Flutter** (canal stable) : https://docs.flutter.dev/get-started/install/windows/desktop
2. Installer **Visual Studio 2022** (pas VS Code) avec la charge de travail **« Développement Desktop en C++ »**. C'est obligatoire pour compiler une appli Windows.
3. Vérifier dans un terminal :
   ```
   flutter doctor
   ```
   La ligne « Visual Studio - develop Windows apps » doit être verte.

## 2. Créer le projet à partir de ce dépôt

Dans le dossier du dépôt (là où se trouve `pubspec.yaml`), **une seule fois** :

```
flutter create --platforms=windows --org com.minerva --project-name chicken_station .
powershell -ExecutionPolicy Bypass -File tools\brand_windows.ps1
flutter pub get
```

- `flutter create .` ajoute seulement le dossier `windows/` (le lanceur C++). Il **n'écrase pas** `lib/`, `test/` ni `pubspec.yaml`.
- `tools\brand_windows.ps1` remplace les mentions Flutter :
  - icône Chicken Station pour l'exécutable, la fenêtre et la barre des tâches ;
  - titre de fenêtre « Chicken Station » en 1280 × 800 ;
  - éditeur « Minerva » dans les propriétés du fichier ;
  - exécutable nommé `ChickenStation.exe`.

## 3. Lancer et compiler

Pendant le développement :
```
flutter run -d windows
```

Pour fabriquer l'exécutable :
```
flutter build windows --release
```

L'exécutable `ChickenStation.exe` se trouve dans `build\windows\x64\runner\Release\`.
**Copiez tout le dossier `Release`**, pas seulement le .exe : il a besoin des `.dll` et du dossier `data` à côté de lui.

### Premier lancement

- La base de données est créée automatiquement et remplie avec les 35 produits et leurs photos (`data/seed/`).
- Un utilisateur **Administrateur** existe avec le code PIN **1234**. Changez-le tout de suite dans **Utilisateurs**.
- Le **mode simulation** est activé : les tickets, bons cuisine, ouvertures du tiroir et montants de l'écran client s'affichent à l'écran au lieu d'aller au matériel. À la boutique, coupez-le dans **Matériel**.

### Tester l'appli à la maison (mode simulation)

1. Connectez-vous (Administrateur, 1234).
2. **Clôture › Ouvrir la journée** : tapez le fond de caisse (un fond conseillé est proposé).
3. **Caisse** : ajoutez des produits.
   - Pour une remarque cuisine (« sans oignon »), double-cliquez sur une ligne.
   - « Cuisine » envoie le bon. « Encaisser » demande les espèces reçues et calcule le rendu.
   - Les tickets s'affichent en bas à droite, l'écran client en haut à droite.
4. **Clôture** :
   - ajoutez des dépenses ;
   - tapez le montant compté puis « Valider » : l'attendu et l'écart apparaissent ;
   - « Clôturer et imprimer le Z ».
5. **Coffre** : l'argent emporté a été ajouté, le fond du matin retiré.
6. **Compta** : l'écart de la journée apparaît dans le mois en cours.
7. **Menu** : modifiez un prix, l'ordre, une photo (« Importer des photos » pour une clé USB).
8. **Utilisateurs** : créez un caissier avec son code. Déconnectez-vous (en bas du menu) et reconnectez-vous avec lui : il ne voit que la Caisse.

Les données sont dans `%APPDATA%\com.minerva\chicken_station\` (base `chicken_station.db`, photos, réglages matériel).

## 4. Test à la boutique

1. **Fermez Front Cash** (ou le logiciel de caisse en place). Il peut garder le port COM de l'écran client ouvert et bloquer nos tests. **Ne le désinstallez pas.**
2. Copiez le dossier `Release` sur le PC de la caisse et lancez `ChickenStation.exe`. Connectez-vous en administrateur, ouvrez **Matériel** et **coupez le mode simulation**.
3. **Imprimante ticket**
   - Choisissez l'imprimante dans la liste (elle doit être installée dans Windows, ce qui est le cas puisque Front Cash l'utilise).
   - Touchez « Imprimer un ticket test ».
   - Touchez « Essai des accents » : un ticket sort avec 4 lignes numérotées [16], [19], [2], [0]. Choisissez dans « Page de code » le numéro dont les accents (é è à ç €) sont justes.
   - Si la ligne `1234567890…` dépasse ou s'arrête trop tôt, changez la **Largeur** (48 en 80 mm, 42 sur certains modèles).
4. **Imprimante cuisine**
   - Pour trouver son adresse IP : éteignez-la, maintenez **FEED** appuyé, rallumez. Elle imprime une page d'auto-test avec l'IP.
   - Tapez l'IP, gardez le port 9100, touchez « Imprimer un bon cuisine test ».
   - Le PC et l'imprimante doivent être sur le même réseau. Par exemple, PC en 192.168.1.10 et imprimante en 192.168.1.x.
5. **Tiroir** : touchez « Ouvrir le tiroir ». S'il ne s'ouvre pas, essayez « Broche 5 ».
6. **Écran client**
   - Choisissez le port COM. Pour le trouver : Gestionnaire de périphériques › Ports (COM et LPT).
   - Touchez « Essai automatique ». L'appli envoie successivement les nombres 1.00, 2.00, 3.00… avec des réglages différents.
   - Notez le nombre qui s'affiche sur l'écran client, puis touchez le bouton de ce nombre : le bon réglage est enregistré.
7. Quand les 4 tests sont **OK** (pastille verte en haut à droite), le matériel est validé.

Les réglages sont enregistrés automatiquement dans `%APPDATA%\…\chicken_station\hardware.json`.

## Plein écran et démarrage automatique

Réglages › Écran et démarrage :
- **Plein écran** (activé par défaut) : la barre des tâches Windows est cachée. Touche **F11** pour basculer (gérant du matériel).
- **Lancer avec Windows** : l'appli s'ouvre au démarrage du PC (clé `HKCU\…\Run`). À activer depuis l'exécutable final (`build\windows\x64\runner\Release\ChickenStation.exe`), pas depuis `flutter run`.
- **Verrouillage automatique** après 2, 5 ou 15 minutes sans toucher l'écran.
- L'appli démarre toujours sur l'écran des codes PIN ; une session restée ouverte (coupure de courant…) est fermée et notée dans le journal.
- Pour fermer l'appli en plein écran : avatar en bas à gauche › **Quitter l'appli** (administrateur).

## Stock, achats et objectif du mois

- **Stock** : ingrédients (photo, unité, seuil d'alerte, coût moyen), réceptions, inventaire, pertes, mouvements. Chaque vente sort les ingrédients d'après la **fiche technique** du produit ; une annulation les remet.
- **Fiches techniques** : quantités par produit, coût matière et marge.
- **Achats** : fournisseurs, réceptions à crédit ou payées, dette restante, paiements depuis la caisse ou le coffre. **Employés** : salaire mensuel, acomptes, primes, reste à payer.
- **Compta › Objectif du mois** : marge (ventes − marchandise) comparée aux charges fixes + salaires, avec la marge et les ventes à faire par jour.
- Tout paiement est enregistré comme une dépense : la caisse attendue, le coffre et le rapport Z restent justes.

## Sauvegarde et restauration

- **Sauvegarde** (menu de gauche, administrateur) : choisissez un dossier (clé USB, OneDrive…). L'appli y écrit des fichiers `ChickenStation_AAAA-MM-JJ_HH-MM-SS_….csbak`.
- Chaque fichier est **relu et vérifié** juste après l'écriture.
- Automatique à chaque **clôture** et au **démarrage** si la dernière a plus de 20 h. Bouton « Sauvegarder maintenant » à tout moment.
- Chaque fichier contient la base complète (réglages compris), les photos importées et les réglages du matériel, **compressés et chiffrés** (ChaCha20 + sceau HMAC-SHA256). Il ne s'ouvre qu'avec Chicken Station, et un fichier modifié ou abîmé est refusé.
- **Restaurer** : choisissez une date dans la liste (ou « Restaurer un fichier… »). Un aperçu s'affiche (date, ventes, journées…). Avant de remplacer, l'état actuel est lui-même sauvegardé (`…_avant-restauration.csbak`).
- **PC neuf** : à la connexion, le lien « Nouvelle installation ? Charger une sauvegarde » apparaît tant qu'aucune vente n'existe.
- **Base illisible au démarrage** : un écran de secours propose directement de charger une sauvegarde. Le fichier abîmé est gardé de côté.

## Journal d'activité

Menu **Activité** : tout ce qui se passe (connexions, ventes, annulations, tiroir sans vente, PIN ratés, dépenses, coffre, clôtures, menu et prix, utilisateurs, matériel, sauvegardes), avec un résumé par utilisateur et des filtres par période et par type.

## 5. Dépannage

| Message | Cause probable | Solution |
|---|---|---|
| « COMx est déjà utilisé par un autre logiciel » | Front Cash est ouvert | Fermez-le complètement (y compris dans la barre des tâches) |
| « Imprimante … introuvable dans Windows » | Mauvais nom choisi | Touchez « Actualiser » puis rechoisissez |
| « Imprimante cuisine injoignable » | Mauvaise IP ou câble débranché | Refaites la page d'auto-test, vérifiez le câble bleu |
| Le ticket sort avec des caractères bizarres | Mauvaise page de code | Faites « Essai des accents » et changez la page de code |
| Rien ne s'affiche sur l'écran client | Protocole ou vitesse | Utilisez « Essai automatique » |
| Compilation : `downloading 'https://sqlite.org/…' failed` | sqlite.org coupe la connexion | Relancez `tools\brand_windows.ps1` (il branche les sources SQLite de `third_party\`) puis `flutter clean` |

Envoyez une photo du **Journal des tests** en cas de problème : chaque erreur y est expliquée.

## 6. Organisation du code

```
lib/
  main.dart                     démarrage, connexion, coque (menu, pied de page Minerva, aperçu simulation)
  data/db.dart                  base SQLite + première installation (data/seed)
  data/models.dart, repos.dart  utilisateurs, menu, journées, ventes, dépenses, coffre
  data/activity.dart            journal d'activité et résumé par utilisateur
  data/backup.dart              sauvegarde, liste, restauration
  data/secure_box.dart          format .csbak (compression, chiffrement, sceau)
  state/session.dart            utilisateur connecté et droits
  ui/                           thème iOS, composants, formats (DA, dates)
  screens/                      connexion, caisse, clôture, coffre, compta, menu, utilisateurs, matériel
  hardware/
    escpos.dart                 construction des tickets ESC/POS + accents
    win_raw_printer.dart        impression RAW via winspool.drv (USB)
    net_printer.dart            imprimante réseau port 9100 (cuisine)
    serial_port_win.dart        port série Win32 (écran client)
    customer_display.dart       protocoles de l'écran client
    hardware_config.dart        réglages enregistrés sur le PC
    hardware_service.dart       actions de haut niveau, mode simulation, tickets de test
    tickets.dart                ticket client, bon cuisine, rapport Z
    system_lists.dart           liste des imprimantes et ports COM
data/seed/                      base de première installation (35 produits, 25 ingrédients, photos)
assets/images/                  logo et icône affichés dans l'appli
branding/                       icône Windows (.ico)
tools/brand_windows.ps1         applique la marque au lanceur Windows + SQLite hors ligne
third_party/                    sources SQLite 3.52.0 (compilées sans téléchargement)
```

## 7. Prochaines étapes

1. Test du matériel à la boutique (écran Matériel, mode simulation coupé)
2. ~~Caisse, journée, clôture, coffre, écarts, menu, utilisateurs~~ (v0.2)
3. Stock et fiches techniques, fournisseurs, paie, réglages d'impression (v0.3)
4. Protection de l'installation (code d'activation lié au PC)
5. Mise en service en parallèle de Front Cash, puis retrait
