#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Konfiguriert MySQL, MongoDB, Metabase und Firewall fuer den DBS-Use-Case.

.DESCRIPTION
    Macht das Folgende:
      1. MySQL my.ini patchen: local_infile=1, utf8mb4, kein secure_file_priv
      2. MongoDB mongod.cfg patchen: bindIp=0.0.0.0 (extern erreichbar)
      3. Metabase als Windows-Service via NSSM einrichten + starten
      4. Firewall-Inbound-Regeln fuer Ports 3306 / 27017 / 3000
      5. Alle Services restarten und Status zeigen

    Die Auth-Aktivierung fuer MongoDB erfolgt SEPARAT, nachdem ein
    admin-User mit mongosh angelegt wurde (siehe mongo/99_users.js).

.NOTES
    Falls die Pfade abweichen: oben in den Variablen anpassen.
#>

$ErrorActionPreference = "Stop"

function Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

# -----------------------------------------------------------------------------
# Pfade (Chocolatey-Standard-Installation)
# -----------------------------------------------------------------------------
$mysqlIni    = "C:\ProgramData\MySQL\MySQL Server 8.0\my.ini"
$mongoConfig = "C:\Program Files\MongoDB\Server\7.0\bin\mongod.cfg"
if (-not (Test-Path $mongoConfig)) {
    # Fallback: in 8.0-Pfad suchen
    $mongoConfig = (Get-ChildItem "C:\Program Files\MongoDB\Server\" -Recurse -Filter "mongod.cfg" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
$metabaseDir = "C:\Metabase"
$metabaseJar = Join-Path $metabaseDir "metabase.jar"
$javaExe     = (Get-Command java -ErrorAction SilentlyContinue).Source

# -----------------------------------------------------------------------------
# (1) MySQL my.ini patchen
# -----------------------------------------------------------------------------
Step "MySQL my.ini patchen"
if (-not (Test-Path $mysqlIni)) {
    throw "MySQL my.ini nicht gefunden unter $mysqlIni. Pfad pruefen."
}
Write-Host "Patch: $mysqlIni"
Copy-Item $mysqlIni "$mysqlIni.bak" -Force

$ini = Get-Content $mysqlIni -Raw

function Set-IniValue {
    param([string]$Body, [string]$Section, [string]$Key, [string]$Value)
    $line = "$Key=$Value"
    if ($Body -match "(?m)^\s*$Key\s*=") {
        return $Body -replace "(?m)^\s*$Key\s*=.*", $line
    } else {
        # Section finden und Zeile anhaengen
        return $Body -replace "(?ms)(\[$Section\][^\[]*)", "`$1$line`r`n"
    }
}

$ini = Set-IniValue -Body $ini -Section "mysqld" -Key "local_infile"          -Value "1"
$ini = Set-IniValue -Body $ini -Section "mysqld" -Key "character-set-server" -Value "utf8mb4"
$ini = Set-IniValue -Body $ini -Section "mysqld" -Key "collation-server"     -Value "utf8mb4_unicode_ci"
$ini = Set-IniValue -Body $ini -Section "mysqld" -Key "secure_file_priv"     -Value '""'

Set-Content -Path $mysqlIni -Value $ini -Encoding UTF8
Write-Host "my.ini gepatcht."

# -----------------------------------------------------------------------------
# (2) MongoDB mongod.cfg patchen
# -----------------------------------------------------------------------------
Step "MongoDB mongod.cfg patchen"
if (-not $mongoConfig -or -not (Test-Path $mongoConfig)) {
    throw "mongod.cfg nicht gefunden. MongoDB Server installiert?"
}
Write-Host "Patch: $mongoConfig"
Copy-Item $mongoConfig "$mongoConfig.bak" -Force

$cfg = Get-Content $mongoConfig -Raw
# bindIp auf 0.0.0.0 (extern erreichbar) -- KEINE Auth bis User angelegt sind
$cfg = $cfg -replace "(?m)^\s*bindIp:.*$", "  bindIp: 0.0.0.0"
Set-Content -Path $mongoConfig -Value $cfg -Encoding UTF8
Write-Host "mongod.cfg gepatcht (bindIp 0.0.0.0)."
Write-Host "HINWEIS: Auth erst NACH dem Anlegen des admin-Users aktivieren (Phase E)."

# -----------------------------------------------------------------------------
# (3) Metabase als Windows-Service einrichten
# -----------------------------------------------------------------------------
Step "Metabase Service via NSSM"
if (-not $javaExe) {
    throw "java.exe nicht im PATH. Java 17 installiert?"
}
if (-not (Test-Path $metabaseJar)) {
    throw "Metabase JAR nicht gefunden unter $metabaseJar. Bootstrap nochmal laufen lassen?"
}

# Falls Service existiert: erst entfernen
$existing = & nssm status Metabase 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Existierender Metabase-Service: $existing -- wird entfernt..."
    & nssm stop Metabase confirm 2>$null | Out-Null
    & nssm remove Metabase confirm | Out-Null
}

& nssm install Metabase $javaExe "-jar `"$metabaseJar`""
& nssm set Metabase AppDirectory $metabaseDir
& nssm set Metabase AppEnvironmentExtra "MB_DB_FILE=$metabaseDir\metabase.db"
& nssm set Metabase Start SERVICE_AUTO_START
& nssm set Metabase AppStdout "$metabaseDir\metabase.log"
& nssm set Metabase AppStderr "$metabaseDir\metabase-error.log"
& nssm set Metabase AppRotateFiles 1
& nssm set Metabase AppRotateBytes 10485760  # 10MB
& nssm start Metabase
Write-Host "Metabase-Service eingerichtet und gestartet. Log: $metabaseDir\metabase.log"

# -----------------------------------------------------------------------------
# (4) Firewall-Regeln
# -----------------------------------------------------------------------------
Step "Windows-Firewall: Inbound-Regeln fuer 3306 / 27017 / 3000"

function Set-FwRule {
    param([string]$Name, [int]$Port, [string]$Desc)
    Get-NetFirewallRule -DisplayName $Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $Name -Direction Inbound -Protocol TCP `
        -LocalPort $Port -Action Allow -Profile Any -Description $Desc | Out-Null
    Write-Host "  + $Name (Port $Port)"
}

Set-FwRule -Name "DBS MySQL"    -Port 3306  -Desc "DBS-Projekt MySQL Server"
Set-FwRule -Name "DBS MongoDB"  -Port 27017 -Desc "DBS-Projekt MongoDB Server"
Set-FwRule -Name "DBS Metabase" -Port 3000  -Desc "DBS-Projekt Metabase Web UI"

# -----------------------------------------------------------------------------
# (5) Services restarten
# -----------------------------------------------------------------------------
Step "Services restarten"

function Restart-IfRunning {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        Restart-Service -Name $Name -Force
        Write-Host "  $Name restarted -> $((Get-Service $Name).Status)"
    } else {
        Write-Warning "Service '$Name' nicht gefunden."
    }
}

Restart-IfRunning "MySQL80"
Restart-IfRunning "MongoDB"
# Metabase wurde oben schon gestartet; hier nur Status
$mb = Get-Service Metabase -ErrorAction SilentlyContinue
if ($mb) { Write-Host "  Metabase status -> $($mb.Status)" }

# -----------------------------------------------------------------------------
# (6) Zusammenfassung
# -----------------------------------------------------------------------------
Step "Status"
Get-Service MySQL80, MongoDB, Metabase -ErrorAction SilentlyContinue | Format-Table -AutoSize

Write-Host ""
Write-Host "Konfiguration abgeschlossen." -ForegroundColor Green
Write-Host ""
Write-Host "Naechste Schritte:" -ForegroundColor Yellow
Write-Host "  1. MySQL root-Passwort aus Chocolatey-Log holen:"
Write-Host "     Get-Content 'C:\ProgramData\chocolatey\logs\chocolatey.log' | Select-String 'root password'"
Write-Host "  2. DB-Benutzer anlegen: sql\99_users.sql und mongo\99_users.js (Passwoerter anpassen!)"
Write-Host "  3. Anschliessend MongoDB-Auth aktivieren (in mongod.cfg: 'security: authorization: enabled')"
Write-Host "  4. Metabase im Browser oeffnen: http://localhost:3000"
