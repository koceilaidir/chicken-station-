; Chicken Station - installateur Windows (Inno Setup 6)
; Ne pas lancer a la main : utilisez tools\build_installer.ps1, qui compile l'appli puis ce script.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef ExeName
  #define ExeName "ChickenStation.exe"
#endif

[Setup]
AppId={{9B7F70CB-4664-441D-976C-563D918094DC}
AppName=Chicken Station
AppVersion={#AppVersion}
AppVerName=Chicken Station {#AppVersion}
AppPublisher=Minerva
AppPublisherURL=mailto:koceilaidir92@gmail.com
AppSupportPhone=+213 782 05 51 93
; Installation pour l'utilisateur Windows courant : pas besoin de mot de passe administrateur.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Chicken Station
DisableDirPage=yes
DefaultGroupName=Chicken Station
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=ChickenStation-Installation-{#AppVersion}
SetupIconFile=..\branding\app_icon.ico
UninstallDisplayIcon={app}\{#ExeName}
UninstallDisplayName=Chicken Station
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; L'appli est fermee automatiquement si elle tourne pendant une mise a jour.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
; Tout le dossier Release : l'exe, les DLL Flutter et SQLite, le dossier data (images, polices).
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Chicken Station"; Filename: "{app}\{#ExeName}"
Name: "{group}\Désinstaller Chicken Station"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Chicken Station"; Filename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#ExeName}"; Description: "Lancer Chicken Station"; Flags: nowait postinstall skipifsilent

; Les donnees (ventes, menu, photos) sont dans %APPDATA% : elles ne sont jamais effacees
; par une mise a jour ni par la desinstallation.
