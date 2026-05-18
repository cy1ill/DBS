#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Verlagert platzhungrige DBS-Projekt-Assets von C: auf E:
    (HSLU-VM hat oft nur ~30 GB C: aber eine grosse E:-Daten-Disk).

.DESCRIPTION
    Macht folgendes idempotent (kann mehrfach laufen):
      1. Stoppt MongoDB + Metabase (damit Files nicht in Benutzung sind)
      2. Cleanup C:\ (Choco-Cache, Temp, Recycle-Bin)
      3. Verschiebt C:\dbs\data\raw\* nach E:\dbs-data\raw\
      4. Verschiebt C:\Metabase nach E:\Metabase + updated NSSM-Service-Config
      5. Patcht mongod.cfg: dbPath + log path nach E:\MongoDB\
      6. Setzt Permissions fuer NetworkService auf E:\MongoDB\
      7. Startet MongoDB + Metabase
      8. Zeigt Disk-Status + Service-Status

    Code bleibt auf C:\dbs (klein, versioniert).
    Beim ELT-Lauf spaeter: DATA_DIR=E:\dbs-data\raw setzen.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

# -----------------------------------------------------------------------------
# (0) Vorab: E: existiert?
# -----------------------------------------------------------------------------
if (-not (Test-Path "E:\")) {
    throw "Drive E: existiert nicht. Pruefe Get-PSDrive."
}

# -----------------------------------------------------------------------------
# (1) Services stoppen
# -----------------------------------------------------------------------------
Step "Services stoppen"
Stop-Service Metabase -Force -ErrorAction SilentlyContinue
Stop-Service MongoDB  -Force -ErrorAction SilentlyContinue
Get-Process mongod  -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process java    -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# -----------------------------------------------------------------------------
# (2) C:\ Cleanup
# -----------------------------------------------------------------------------
Step "C: Cleanup (Choco-Cache, Temp, Recycle-Bin)"
$beforeFree = (Get-PSDrive C).Free / 1MB
Write-Host ("  Free vor Cleanup : {0:N1} MB" -f $beforeFree)

# Choco-Installer (MSIs/ZIPs sind nach Install nicht mehr noetig)
Get-ChildItem "C:\ProgramData\chocolatey\lib" -Recurse -Include "*.nupkg","*.msi","*.zip","*.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*\tools\nssm*" } |
    Remove-Item -Force -ErrorAction SilentlyContinue
Remove-Item "C:\ProgramData\chocolatey\lib-bad\*" -Recurse -Force -ErrorAction SilentlyContinue

# Temp-Verzeichnisse
Remove-Item "$env:TEMP\*"             -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Temp\*"       -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\*\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Recycle Bin
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# Windows Update Cache
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service wuauserv -ErrorAction SilentlyContinue

$afterFree = (Get-PSDrive C).Free / 1MB
Write-Host ("  Free nach Cleanup: {0:N1} MB (Delta: {1:N1} MB)" -f $afterFree, ($afterFree - $beforeFree))

# -----------------------------------------------------------------------------
# (3) Daten-Files von C:\dbs\data\raw\ nach E:\dbs-data\raw\
# -----------------------------------------------------------------------------
Step "Daten-Files nach E:\dbs-data\raw\"
$srcData = "C:\dbs\data\raw"
$dstData = "E:\dbs-data\raw"
New-Item -Path $dstData -ItemType Directory -Force | Out-Null
if (Test-Path $srcData) {
    Get-ChildItem $srcData -File -ErrorAction SilentlyContinue | ForEach-Object {
        $target = Join-Path $dstData $_.Name
        if (Test-Path $target) {
            Write-Host "  bereits vorhanden: $($_.Name)"
        } else {
            Write-Host "  verschiebe: $($_.Name) ($([math]::Round($_.Length/1MB,1)) MB)"
            Move-Item $_.FullName $target -Force
        }
    }
}
# .gitkeep behalten wir auf C: (sonst klagt git)
Write-Host "  Daten-Files jetzt unter: $dstData"
Get-ChildItem $dstData | Format-Table Name, @{N='MB';E={[math]::Round($_.Length/1MB,1)}} -AutoSize

# -----------------------------------------------------------------------------
# (4) Metabase nach E:\Metabase\
# -----------------------------------------------------------------------------
Step "Metabase nach E:\Metabase\"
$srcMb = "C:\Metabase"
$dstMb = "E:\Metabase"
New-Item -Path $dstMb -ItemType Directory -Force | Out-Null

if (Test-Path $srcMb) {
    Get-ChildItem $srcMb -File -ErrorAction SilentlyContinue | ForEach-Object {
        $target = Join-Path $dstMb $_.Name
        if (-not (Test-Path $target)) {
            Write-Host "  verschiebe: $($_.Name) ($([math]::Round($_.Length/1MB,1)) MB)"
            Move-Item $_.FullName $target -Force
        }
    }
    # Falls leer: alten Ordner entfernen
    if (-not (Get-ChildItem $srcMb -ErrorAction SilentlyContinue)) {
        Remove-Item $srcMb -Force -ErrorAction SilentlyContinue
    }
}

# NSSM Metabase-Service umkonfigurieren (oder neu installieren)
$javaExe = (Get-Command java -ErrorAction SilentlyContinue).Source
if (-not $javaExe) { throw "java.exe nicht im PATH" }

if (Get-Service Metabase -ErrorAction SilentlyContinue) {
    & nssm stop Metabase confirm 2>&1 | Out-Null
    & nssm remove Metabase confirm 2>&1 | Out-Null
    Start-Sleep -Seconds 2
}

$mbJar = Join-Path $dstMb "metabase.jar"
if (-not (Test-Path $mbJar)) { throw "Metabase JAR nicht in $dstMb gefunden" }

& nssm install Metabase $javaExe "-jar `"$mbJar`""
& nssm set Metabase AppDirectory $dstMb
& nssm set Metabase AppEnvironmentExtra "MB_DB_FILE=$dstMb\metabase.db"
& nssm set Metabase Start SERVICE_AUTO_START
& nssm set Metabase AppStdout "$dstMb\metabase.log"
& nssm set Metabase AppStderr "$dstMb\metabase-error.log"
& nssm set Metabase AppRotateFiles 1
& nssm set Metabase AppRotateBytes 10485760
Write-Host "  Metabase NSSM-Service neu konfiguriert mit Pfad $dstMb"

# -----------------------------------------------------------------------------
# (5) MongoDB dbPath + log nach E:\MongoDB\
# -----------------------------------------------------------------------------
Step "MongoDB-Datadir nach E:\MongoDB\"
$dbDir  = "E:\MongoDB\data\db"
$logDir = "E:\MongoDB\log"
New-Item -Path $dbDir  -ItemType Directory -Force | Out-Null
New-Item -Path $logDir -ItemType Directory -Force | Out-Null

# Permissions fuer NetworkService (Service-User)
& icacls "E:\MongoDB" /grant "NT AUTHORITY\NetworkService:(OI)(CI)F" /T | Out-Null
Write-Host "  Permissions auf E:\MongoDB\ gesetzt"

# Alte Verzeichnisse auf C: entfernen
Remove-Item "C:\ProgramData\MongoDB\data" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\ProgramData\MongoDB\log"  -Recurse -Force -ErrorAction SilentlyContinue

# mongod.cfg patchen
$cfgPath = Get-ChildItem "C:\Program Files\MongoDB" -Recurse -Filter "mongod.cfg" |
           Select-Object -First 1 -ExpandProperty FullName
if (-not $cfgPath) { throw "mongod.cfg nicht gefunden" }
Write-Host "  Patche: $cfgPath"

$cfg = Get-Content $cfgPath -Raw
$cfg = $cfg -replace "(?m)^\s*dbPath:.*$", "  dbPath: E:\MongoDB\data\db"
$cfg = $cfg -replace "(?m)^\s*path:\s+C:\\ProgramData\\MongoDB\\log\\mongod\.log.*$", "  path: E:\MongoDB\log\mongod.log"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($cfgPath, $cfg, $utf8NoBom)
Write-Host "  mongod.cfg gepatcht (dbPath + log nach E:)"

# -----------------------------------------------------------------------------
# (6) Services starten
# -----------------------------------------------------------------------------
Step "Services starten"
try {
    Start-Service MongoDB
    Start-Sleep -Seconds 3
    Write-Host "  MongoDB : $((Get-Service MongoDB).Status)"
} catch {
    Write-Warning "MongoDB konnte nicht gestartet werden: $($_.Exception.Message)"
    Write-Host "  Pruefe E:\MongoDB\log\mongod.log fuer Details"
}

try {
    Start-Service Metabase
    Start-Sleep -Seconds 3
    Write-Host "  Metabase: $((Get-Service Metabase).Status)"
} catch {
    Write-Warning "Metabase konnte nicht gestartet werden: $($_.Exception.Message)"
}

# -----------------------------------------------------------------------------
# (7) Status
# -----------------------------------------------------------------------------
Step "Disk-Status"
Get-PSDrive C, E | Select-Object Name, @{N='UsedGB';E={[math]::Round($_.Used/1GB,2)}}, @{N='FreeGB';E={[math]::Round($_.Free/1GB,2)}} | Format-Table -AutoSize

Step "Service-Status"
$mysqlSvc = (Get-Service | Where-Object Name -like "MySQL*" | Select-Object -First 1).Name
if (-not $mysqlSvc) { $mysqlSvc = "MySQL" }
Get-Service $mysqlSvc, MongoDB, Metabase -ErrorAction SilentlyContinue | Format-Table Name, Status -AutoSize

Write-Host ""
Write-Host "Fertig." -ForegroundColor Green
Write-Host ""
Write-Host "WICHTIG fuer ELT:" -ForegroundColor Yellow
Write-Host "  Bei Bash-Script: DATA_DIR=E:\\dbs-data\\raw  ./scripts/run_elt_mysql.sh"
Write-Host "  Bei Mongo-ELT  : die preprocess.py Pfade muessen evtl. angepasst werden"
