# Chicken Station — Caisse & gestion

Application Windows de caisse et de gestion pour le fast-food Chicken Station (Burger & Tacos).
Developed by Minerva — +213 782 05 51 93 — koceilaidir92@gmail.com

**Étape actuelle : phase 1, test du matériel.** L'application démarre sur l'écran **Matériel**. Il sert à régler et tester :

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

Dans le dossier du dépôt (là où se trouve `pubspec.yaml`) :

```
flutter create --platforms=windows --project-name chicken_station .
flutter pub get
```

`flutter create .` ajoute seulement le dossier `windows/` (le lanceur C++). Il **n'écrase pas** `lib/` ni `pubspec.yaml`.

## 3. Lancer et compiler

Pendant le développement :
```
flutter run -d windows
```

Pour fabriquer l'exécutable :
```
flutter build windows --release
```

L'exécutable se trouve dans `build\windows\x64\runner\Release\`.
**Copiez tout le dossier `Release`** sur une clé USB, pas seulement `chicken_station.exe` : il a besoin des fichiers `.dll` et du dossier `data` à côté de lui.

## 4. Test à la boutique

1. **Fermez Front Cash** (ou le logiciel de caisse en place). Il peut garder le port COM de l'écran client ouvert et bloquer nos tests. **Ne le désinstallez pas.**
2. Copiez le dossier `Release` sur le PC de la caisse et lancez `chicken_station.exe`.
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
7. Quand les 4 tests sont **OK** (pastille verte en haut à droite), la phase 1 est validée.

Les réglages sont enregistrés automatiquement dans `%APPDATA%\…\chicken_station\hardware.json`.

## 5. Dépannage

| Message | Cause probable | Solution |
|---|---|---|
| « COMx est déjà utilisé par un autre logiciel » | Front Cash est ouvert | Fermez-le complètement (y compris dans la barre des tâches) |
| « Imprimante … introuvable dans Windows » | Mauvais nom choisi | Touchez « Actualiser » puis rechoisissez |
| « Imprimante cuisine injoignable » | Mauvaise IP ou câble débranché | Refaites la page d'auto-test, vérifiez le câble bleu |
| Le ticket sort avec des caractères bizarres | Mauvaise page de code | Faites « Essai des accents » et changez la page de code |
| Rien ne s'affiche sur l'écran client | Protocole ou vitesse | Utilisez « Essai automatique » |

Envoyez une photo du **Journal des tests** en cas de problème : chaque erreur y est expliquée.

## 6. Organisation du code

```
lib/
  main.dart                     coque de l'appli (menu à gauche, pied de page Minerva)
  ui/theme.dart                 couleurs et composants (style iOS)
  screens/hardware_screen.dart  écran Matériel (phase 1)
  hardware/
    escpos.dart                 construction des tickets ESC/POS + accents
    win_raw_printer.dart        impression RAW via winspool.drv (USB)
    net_printer.dart            imprimante réseau port 9100 (cuisine)
    serial_port_win.dart        port série Win32 (écran client)
    customer_display.dart       protocoles de l'écran client
    hardware_config.dart        réglages enregistrés sur le PC
    hardware_service.dart       actions de haut niveau + tickets de test
    system_lists.dart           liste des imprimantes et ports COM
data/seed/                      base de première installation (35 produits, 25 ingrédients, photos)
```

## 7. Prochaines étapes

1. ~~Phase 1 : test du matériel~~ ← **en cours**
2. Caisse : familles, produits, bon cuisine, ticket, tiroir, écran client (base SQLite locale, données de `data/seed/`)
3. Argent : fond de caisse, dépenses, clôture à l'aveugle, coffre, écarts par mois
4. Stock et fournisseurs, fiches techniques
5. Paie, utilisateurs avec code PIN, réglages d'impression
6. Mise en service en parallèle de Front Cash, puis retrait
