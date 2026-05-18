#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Verschiebt das MySQL-Datadir von C:\tools\mysql\current\data nach E:\MySQL\data.

.DESCRIPTION
    C: ist nur ~30 GB, nach Bootstrap + halbem ELT praktisch voll (0.14 GB free).
    MySQL kippt mit ERROR 1114 'table is full'. Loesung: Datadir auf E:.

    Schritte:
      1. MySQL-Service stoppen
      2. robocopy von C:\tools\mysql\current\data nach E:\MySQL\data
      3. my.ini patchen: datadir=E:/MySQL/data
      4. Permissions auf E:\MySQL\ fuer Service-User setzen
      5. MySQL starten und Test-Query
      6. Alten Datadir auf C: loeschen (nur wenn neuer funktioniert)

    Resultat: ~3 GB Platz auf C: zurueckgewonnen, MySQL hat 97 GB Headroom.
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

# -----------------------------------------------------------------------------
# (0) Voraussetzungen
# -----------------------------------------------------------------------------
if (-not (Test-Path "E:\")) { throw "Drive E: nicht vorhanden." }

$mysqlSvc = (Get-Service | Where-Object Name -like "MySQL*" | Select-Object -First 1).Name
if (-not $mysqlSvc) { throw "Kein MySQL-Service gefunden." }
$mysqlIni   = "C:\tools\mysql\current\my.ini"
$oldDatadir = "C:\tools\mysql\current\data"
$newDatadir = "E:\MySQL\data"

if (-not (Test-Path $mysqlIni))   { throw "my.ini nicht gefunden: $mysqlIni" }
if (-not (Test-Path $oldDatadir)) { throw "Alter Datadir nicht gefunden: $oldDatadir" }

Step "Pre-Check"
Write-Host "  Service        : $mysqlSvc"
Write-Host "  my.ini         : $mysqlIni"
Write-Host "  Alter Datadir  : $oldDatadir"
Write-Host "  Neuer Datadir  : $newDatadir"
Get-PSDrive C, E | Select-Object Name, @{N='FreeGB';E={[math]::Round($_.Free/1GB,2)}} | Format-Table -AutoSize

# -----------------------------------------------------------------------------
# (1) MySQL stoppen
# -----------------------------------------------------------------------------
Step "MySQL stoppen"
Stop-Service $mysqlSvc -Force
Start-Sleep -Seconds 5
Get-Service $mysqlSvc

# -----------------------------------------------------------------------------
# (2) Datadir kopieren
# -----------------------------------------------------------------------------
Step "Datadir kopieren ($oldDatadir -> $newDatadir)"
New-Item -Path $newDatadir -ItemType Directory -Force | Out-Null

$oldSize = (Get-ChildItem $oldDatadir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
Write-Host "Quell-Volumen: $([math]::Round($oldSize/1MB,1)) MB"
Write-Host "Kopiere (kann 1-3 Minuten dauern)..."

# robocopy /MIR ist sauberer als Move-Item bei vielen Files
& robocopy $oldDatadir $newDatadir /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
# robocopy exitcodes: 0-7 = success, 8+ = error
if ($LASTEXITCODE -ge 8) {
    throw "robocopy fehlgeschlagen mit Exit-Code $LASTEXITCODE"
}

$newSize = (Get-ChildItem $newDatadir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
Write-Host "Ziel-Volumen : $([math]::Round($newSize/1MB,1)) MB"
if ($newSize -lt $oldSize * 0.95) {
    throw "Copy unvollstaendig -- Abbruch. Alter Datadir bleibt unberuehrt."
}

# -----------------------------------------------------------------------------
# (3) my.ini patchen
# -----------------------------------------------------------------------------
Step "my.ini patchen (datadir -> E:/MySQL/data)"
Copy-Item $mysqlIni "$mysqlIni.bak2" -Force

$ini = Get-Content $mysqlIni -Raw
$newPath = "E:/MySQL/data"
if ($ini -match "(?m)^\s*datadir\s*=") {
    $ini = $ini -replace "(?m)^\s*datadir\s*=.*", "datadir=$newPath"
    Write-Host "  existierende datadir-Zeile ersetzt"
} else {
    # In [mysqld]-Section einfuegen
    $ini = $ini -replace "(?ms)(\[mysqld\][^\[]*)", "`$1datadir=$newPath`r`n"
    Write-Host "  datadir-Zeile in [mysqld] eingefuegt"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($mysqlIni, $ini, $utf8NoBom)

# -----------------------------------------------------------------------------
# (4) Permissions auf E:\MySQL\
# -----------------------------------------------------------------------------
Step "Permissions auf E:\MySQL\"
$svcInfo = Get-CimInstance -ClassName Win32_Service -Filter "Name='$mysqlSvc'"
$svcUser = $svcInfo.StartName
Write-Host "  Service laeuft als: $svcUser"

& icacls "E:\MySQL" /grant "NT AUTHORITY\NetworkService:(OI)(CI)F" /T | Out-Null
& icacls "E:\MySQL" /grant "BUILTIN\Administrators:(OI)(CI)F" /T | Out-Null
if ($svcUser -and $svcUser -notmatch "NetworkService") {
    try {
        & icacls "E:\MySQL" /grant "${svcUser}:(OI)(CI)F" /T 2>&1 | Out-Null
    } catch {}
}
Write-Host "  Permissions gesetzt"

# -----------------------------------------------------------------------------
# (5) MySQL starten + Test
# -----------------------------------------------------------------------------
Step "MySQL starten"
Start-Service $mysqlSvc
Start-Sleep -Seconds 6
$status = (Get-Service $mysqlSvc).Status
Write-Host "  Status: $status"

if ($status -ne 'Running') {
    Write-Warning "MySQL startet nicht. Pruefe Error-Log."
    $errLog = Get-ChildItem "$newDatadir" -Filter "*.err" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($errLog) {
        Write-Host "Letzte 30 Zeilen $($errLog.FullName):"
        Get-Content $errLog.FullName -Tail 30
    }
    Write-Host ""
    Write-Host "Rollback: Restore-Item '$mysqlIni.bak2' und Service neu starten." -ForegroundColor Yellow
    exit 1
}

Step "Test-Query"
& mysql -u root -e "SHOW DATABASES;"

# -----------------------------------------------------------------------------
# (6) Alten Datadir loeschen
# -----------------------------------------------------------------------------
Step "Alten Datadir loeschen (C: zurueckgewinnen)"
Write-Host "Loesche: $oldDatadir"
Remove-Item $oldDatadir -Recurse -Force
Write-Host "  done"

# -----------------------------------------------------------------------------
# (7) Endstatus
# -----------------------------------------------------------------------------
Step "Endstatus"
Get-PSDrive C, E | Select-Object Name, @{N='UsedGB';E={[math]::Round($_.Used/1GB,2)}}, @{N='FreeGB';E={[math]::Round($_.Free/1GB,2)}} | Format-Table -AutoSize
Get-Service $mysqlSvc, MongoDB, Metabase | Format-Table Name, Status -AutoSize

Write-Host ""
Write-Host "MySQL-Datadir liegt jetzt auf E:\MySQL\data" -ForegroundColor Green
Write-Host "ELT kann erneut laufen, diesmal mit 97 GB Headroom." -ForegroundColor Green
Write-Host ""
Write-Host "Optional: Projekt-Ordner auch nach E: schieben (30 MB, kosmetisch):" -ForegroundColor Yellow
Write-Host "  1. Alle Git-Bash + Editor-Sessions auf C:\dbs schliessen"
Write-Host "  2. cd C:\"
Write-Host "  3. robocopy dbs E:\dbs /E /MOVE"
Write-Host "  4. Danach mit cd E:\dbs weiterarbeiten"
