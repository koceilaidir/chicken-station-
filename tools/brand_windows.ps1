# Chicken Station - applique la marque (Minerva) au lanceur Windows genere par Flutter.
# A lancer UNE FOIS apres "flutter create", depuis le dossier du projet :
#   powershell -ExecutionPolicy Bypass -File tools\brand_windows.ps1
# Le script est sans risque : on peut le relancer autant de fois que l'on veut.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $root 'windows\runner'

if (-not (Test-Path $runner)) {
    throw "Dossier windows\runner introuvable. Lancez d'abord : flutter create --platforms=windows --org com.minerva --project-name chicken_station ."
}

function Update-File([string]$path, [scriptblock]$change) {
    if (-not (Test-Path $path)) { Write-Warning "Fichier absent : $path"; return }
    $text = [System.IO.File]::ReadAllText($path)
    $new = & $change $text
    [System.IO.File]::WriteAllText($path, $new, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "OK  $path"
}

# 1. Icone de l'executable, de la fenetre et de la barre des taches
Copy-Item (Join-Path $root 'branding\app_icon.ico') (Join-Path $runner 'resources\app_icon.ico') -Force
Write-Host "OK  icone copiee"

# 2. Titre et taille de la fenetre
Update-File (Join-Path $runner 'main.cpp') {
    param($t)
    $t = $t -replace 'window\.Create\(L"[^"]*"', 'window.Create(L"Chicken Station"'
    $t = $t -replace 'Win32Window::Size size\(\s*\d+\s*,\s*\d+\s*\)', 'Win32Window::Size size(1280, 800)'
    $t
}

# 3. Proprietes du fichier .exe (clic droit > Proprietes > Details)
Update-File (Join-Path $runner 'Runner.rc') {
    param($t)
    $t = $t -replace 'VALUE "CompanyName", "[^"]*"', 'VALUE "CompanyName", "Minerva"'
    $t = $t -replace 'VALUE "FileDescription", "[^"]*"', 'VALUE "FileDescription", "Chicken Station - Caisse et gestion"'
    $t = $t -replace 'VALUE "ProductName", "[^"]*"', 'VALUE "ProductName", "Chicken Station"'
    $t = $t -replace 'VALUE "InternalName", "[^"]*"', 'VALUE "InternalName", "ChickenStation"'
    $t = $t -replace 'VALUE "OriginalFilename", "[^"]*"', 'VALUE "OriginalFilename", "ChickenStation.exe"'
    $t = $t -replace 'VALUE "LegalCopyright", "[^"]*"', 'VALUE "LegalCopyright", "Copyright (C) 2026 Minerva"'
    $t
}

# 4. Nom de l'executable : ChickenStation.exe
Update-File (Join-Path $root 'windows\CMakeLists.txt') {
    param($t)
    $t -replace 'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "ChickenStation")'
}

# 5. SQLite compile depuis le dossier third_party (aucun telechargement pendant la compilation)
$sqliteDir = Join-Path $root 'third_party\sqlite-autoconf-3520000'
if (-not (Test-Path (Join-Path $sqliteDir 'sqlite3.c'))) {
    tar -xzf (Join-Path $root 'third_party\sqlite-autoconf-3520000.tar.gz') -C (Join-Path $root 'third_party')
    if (-not (Test-Path (Join-Path $sqliteDir 'sqlite3.c'))) { throw "Extraction de SQLite impossible." }
}
Write-Host "OK  sources SQLite pretes"
Update-File (Join-Path $root 'windows\CMakeLists.txt') {
    param($t)
    if ($t -match 'FETCHCONTENT_SOURCE_DIR_SQLITE3') { return $t }
    $line = 'set(FETCHCONTENT_SOURCE_DIR_SQLITE3 "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/sqlite-autoconf-3520000" CACHE PATH "SQLite local" FORCE)'
    $anchor = 'include(flutter/generated_plugins.cmake)'
    $i = $t.IndexOf($anchor)
    if ($i -lt 0) { Write-Warning "Ligne generated_plugins introuvable dans windows\CMakeLists.txt"; return $t }
    $t.Insert($i, $line + "`r`n")
}

Write-Host ""
Write-Host "Marque appliquee. Compilez avec : flutter build windows --release"
