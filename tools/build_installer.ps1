# Chicken Station - fabrique l'installateur Windows a copier sur une cle USB.
# Depuis le dossier du projet :
#   powershell -ExecutionPolicy Bypass -File tools\build_installer.ps1
# Resultat : dist\ChickenStation-Installation-<version>.exe

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Step([string]$t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Yellow }

# 1. Version lue dans pubspec.yaml (ex. 0.5.0+8 -> 0.5.0)
$line = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)' | Select-Object -First 1
if (-not $line) { throw "Version introuvable dans pubspec.yaml" }
$version = $line.Matches[0].Groups[1].Value
Step "Chicken Station $version"

# 2. Marque (icone, nom de l'exe, SQLite local) puis compilation Release
Step "Preparation"
& powershell -ExecutionPolicy Bypass -File (Join-Path $root 'tools\brand_windows.ps1')
if ($LASTEXITCODE -ne 0) { throw "tools\brand_windows.ps1 a echoue." }

Step "Compilation (quelques minutes)"
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get a echoue." }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "La compilation a echoue : lisez les erreurs ci-dessus." }

$release = Join-Path $root 'build\windows\x64\runner\Release'
$exe = Get-ChildItem $release -Filter *.exe | Select-Object -First 1
if (-not $exe) { throw "Aucun .exe dans $release" }
Write-Host "OK  $($exe.Name)"

# 3. Runtime Visual C++ a cote de l'exe : l'appli demarre meme sur un PC ou il n'est pas installe.
Step "Runtime Visual C++"
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    $src = Join-Path $env:WINDIR "System32\$dll"
    if (Test-Path $src) { Copy-Item $src $release -Force; Write-Host "OK  $dll" }
    else { Write-Warning "$dll absent de ce PC : installez 'Visual C++ Redistributable x64' sur le PC de la boutique si l'appli ne demarre pas." }
}

# 4. Inno Setup (installe automatiquement s'il manque)
Step "Inno Setup"
function Find-Iscc {
    foreach ($p in @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}
$iscc = Find-Iscc
if (-not $iscc) {
    Write-Host "Inno Setup absent : installation avec winget..."
    try {
        winget install --id JRSoftware.InnoSetup -e --silent --accept-package-agreements --accept-source-agreements
    } catch {
        Write-Warning "winget indisponible : $_"
    }
    $iscc = Find-Iscc
}
if (-not $iscc) {
    throw "Inno Setup introuvable. Installez-le depuis https://jrsoftware.org/isdl.php puis relancez ce script."
}
Write-Host "OK  $iscc"

# 5. Fabrication de l'installateur
Step "Installateur"
& $iscc "/DAppVersion=$version" "/DSourceDir=$release" "/DExeName=$($exe.Name)" (Join-Path $root 'installer\chicken_station.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup a echoue." }

$out = Join-Path $root "dist\ChickenStation-Installation-$version.exe"
Step "Termine"
Write-Host "Installateur : $out" -ForegroundColor Green
Write-Host "Copiez ce fichier sur la cle USB. A la boutique : double-clic, Suivant, Installer."
explorer.exe (Join-Path $root 'dist')
