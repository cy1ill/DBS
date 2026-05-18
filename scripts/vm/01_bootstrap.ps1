#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap fuer die HSLU-DBS-VM: installiert alle benoetigte Software.

.DESCRIPTION
    Installiert ueber Chocolatey:
      - Visual C++ Redistributable (Pflicht fuer MySQL)
      - MySQL Community Server 8.x + Workbench
      - MongoDB Community Server 7.x + Database Tools + mongosh
      - Java 17 LTS (Temurin) fuer Metabase
      - Python 3.12 fuer das Preprocessing
      - NSSM (Service-Wrapper fuer Metabase)

    Laedt zusaetzlich Metabase JAR nach C:\Metabase\.

    Voraussetzung: PowerShell als Administrator + Chocolatey installiert.

.NOTES
    Laufzeit: 15-25 Minuten (viele Downloads).
    Im Fehlerfall: einzelne 'choco install ...' manuell wiederholen.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # schnellere Downloads

function Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

function CheckChoco {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Chocolatey nicht gefunden. Installiere zuerst Chocolatey:" -ForegroundColor Yellow
        Write-Host "  Set-ExecutionPolicy Bypass -Scope Process -Force"
        Write-Host "  iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
        throw "Chocolatey muss vorher installiert sein."
    }
}

# -----------------------------------------------------------------------------
# (0) Pre-Checks
# -----------------------------------------------------------------------------
Step "Pre-Checks"
CheckChoco
$winVer = (Get-CimInstance Win32_OperatingSystem).Caption
Write-Host "Windows: $winVer"
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"

# -----------------------------------------------------------------------------
# (1) Basis-Tools
# -----------------------------------------------------------------------------
Step "Visual C++ Redistributable"
choco install vcredist140 -y --no-progress

Step "Python 3.12"
choco install python312 -y --no-progress
# PATH refresh in dieser Session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Step "Java 21 (Temurin LTS) -- fuer Metabase (braucht Java 21+ ab v0.51)"
choco install temurin21 -y --no-progress

Step "NSSM -- Service-Wrapper fuer Metabase"
choco install nssm -y --no-progress

# -----------------------------------------------------------------------------
# (2) MySQL
# -----------------------------------------------------------------------------
Step "MySQL Server 8.x"
# Chocolatey-MySQL setzt zufaelliges root-Passwort und schreibt es nach C:\ProgramData\chocolatey\logs
choco install mysql -y --no-progress

Step "MySQL Workbench"
choco install mysql.workbench -y --no-progress

# -----------------------------------------------------------------------------
# (3) MongoDB
# -----------------------------------------------------------------------------
Step "MongoDB Community Server"
choco install mongodb -y --no-progress

Step "MongoDB Database Tools (mongoimport, mongoexport, ...)"
choco install mongodb-database-tools -y --no-progress

Step "mongosh (direkt von mongodb.com -- Choco-Paket existiert nicht mehr)"
$mongoshVer = "2.3.4"
$mongoshDir = "C:\Program Files\mongosh"
if (-not (Get-ChildItem $mongoshDir -Recurse -Filter "mongosh.exe" -ErrorAction SilentlyContinue)) {
    $zipUrl  = "https://downloads.mongodb.com/compass/mongosh-$mongoshVer-win32-x64.zip"
    $zipFile = "$env:TEMP\mongosh-$mongoshVer.zip"
    Write-Host "  Downloading $zipUrl ..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
    Expand-Archive -Path $zipFile -DestinationPath $mongoshDir -Force
    Remove-Item $zipFile -Force
}
$mongoshBinDir = (Get-ChildItem $mongoshDir -Recurse -Filter "mongosh.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).Directory.FullName
if ($mongoshBinDir) {
    $sysPath = [Environment]::GetEnvironmentVariable("Path","Machine")
    if ($sysPath -notlike "*$mongoshBinDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$sysPath;$mongoshBinDir", "Machine")
        Write-Host "  PATH permanent ergaenzt um $mongoshBinDir"
    }
    $env:Path = "$env:Path;$mongoshBinDir"
    Write-Host "  mongosh installiert: $mongoshBinDir"
} else {
    Write-Warning "mongosh.exe nicht gefunden nach Extract!"
}

# -----------------------------------------------------------------------------
# (4) Metabase JAR + Verzeichnis
# -----------------------------------------------------------------------------
Step "Metabase JAR herunterladen"
$mbDir = "C:\Metabase"
if (-not (Test-Path $mbDir)) { New-Item -Path $mbDir -ItemType Directory | Out-Null }
$mbJar = Join-Path $mbDir "metabase.jar"
if (-not (Test-Path $mbJar)) {
    Write-Host "Lade Metabase JAR (~350 MB)..."
    Invoke-WebRequest -Uri "https://downloads.metabase.com/latest/metabase.jar" -OutFile $mbJar
    Write-Host "Metabase JAR: $mbJar ($([math]::Round((Get-Item $mbJar).Length/1MB,1)) MB)"
} else {
    Write-Host "Metabase JAR existiert bereits."
}

# -----------------------------------------------------------------------------
# (5) Python-Pakete (pandas fuer Preprocessing-Tests, kaggle optional)
# -----------------------------------------------------------------------------
Step "Python pip-Pakete"
$pythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonExe) {
    Write-Warning "python.exe nicht im PATH; ueberspringe pip-Install. Nach Neustart der Shell erneut versuchen."
} else {
    & $pythonExe -m pip install --upgrade pip
    & $pythonExe -m pip install pandas
    Write-Host "pip-Pakete installiert."
}

# -----------------------------------------------------------------------------
# (6) Zusammenfassung
# -----------------------------------------------------------------------------
Step "Installation abgeschlossen -- Versionen pruefen"

function ShowVersion {
    param([string]$Label, [string]$CmdName, [string[]]$VersionArgs = @("--version"))
    $cmd = Get-Command $CmdName -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            $raw = (& $CmdName $VersionArgs 2>&1 | Out-String).Trim()
            $firstLine = ($raw -split "`r?`n")[0]
            Write-Host ("  {0,-12} : {1}" -f $Label, $firstLine)
        } catch {
            Write-Host ("  {0,-12} : {1}" -f $Label, "FEHLER: $($_.Exception.Message)") -ForegroundColor Red
        }
    } else {
        Write-Host ("  {0,-12} : nicht im PATH (neue Shell starten oder Pfad ergaenzen)" -f $Label) -ForegroundColor Yellow
    }
}

ShowVersion "MySQL"       "mysql"
ShowVersion "MongoDB"     "mongod"
ShowVersion "mongoimport" "mongoimport"
ShowVersion "mongosh"     "mongosh"
ShowVersion "Java"        "java"       @("-version")
ShowVersion "Python"      "python"

Write-Host ""
Write-Host "Naechster Schritt:" -ForegroundColor Green
Write-Host "  1. PowerShell schliessen und neu als Admin oeffnen (damit PATH aktualisiert ist)"
Write-Host "  2. cd C:\dbs"
Write-Host "  3. .\scripts\vm\02_configure_services.ps1"
