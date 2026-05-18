#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Smoke-Tests: prueft, ob alle DBS-Services auf der VM laufen und erreichbar sind.

.DESCRIPTION
    Geht durch:
      1. Service-Status fuer MySQL80, MongoDB, Metabase
      2. Lokale Port-Connectivity (3306, 27017, 3000)
      3. mysql.exe SELECT 1 (anonymer Versuch -- sollte mit Auth-Fehler scheitern,
         was bestaetigt dass der Server antwortet)
      4. mongosh ping
      5. HTTP GET auf Metabase Healthcheck

    Liefert farbliche PASS/FAIL fuer jeden Test.
#>

$ErrorActionPreference = "Continue"

function PassFail($label, $ok, $detail = "") {
    $tag = if ($ok) { "  PASS" } else { "  FAIL" }
    $col = if ($ok) { "Green" } else { "Red" }
    Write-Host -NoNewline $tag -ForegroundColor $col
    Write-Host "  $label" -NoNewline
    if ($detail) { Write-Host "  ($detail)" -ForegroundColor DarkGray } else { Write-Host "" }
}

Write-Host ""
Write-Host "=== DBS VM-Validierung ===" -ForegroundColor Cyan

# ---- (1) Service-Status --------------------------------------------------
Write-Host ""
Write-Host "Service-Status:" -ForegroundColor Yellow
$mysqlSvc = (Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "MySQL*" } | Select-Object -First 1).Name
if (-not $mysqlSvc) { $mysqlSvc = "MySQL80" }
foreach ($svcName in @($mysqlSvc, "MongoDB", "Metabase")) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        PassFail "Service $svcName" ($svc.Status -eq "Running") $svc.Status
    } else {
        PassFail "Service $svcName" $false "nicht installiert"
    }
}

# ---- (2) Port-Connectivity (localhost) ------------------------------------
Write-Host ""
Write-Host "Lokale Port-Connectivity:" -ForegroundColor Yellow
foreach ($p in @(@{Name="MySQL"; Port=3306}, @{Name="MongoDB"; Port=27017}, @{Name="Metabase"; Port=3000})) {
    $tcp = Test-NetConnection -ComputerName localhost -Port $p.Port -WarningAction SilentlyContinue
    PassFail "Port $($p.Port) ($($p.Name))" $tcp.TcpTestSucceeded
}

# ---- (3) MySQL: SELECT 1 (mit root) ---------------------------------------
Write-Host ""
Write-Host "MySQL-Antwort:" -ForegroundColor Yellow
if (Get-Command mysql -ErrorAction SilentlyContinue) {
    # versuche mit root ohne Passwort -- wir erwarten entweder Erfolg oder Auth-Fehler
    $out = & mysql -h 127.0.0.1 -u root -e "SELECT 1 AS ok;" 2>&1
    $reachable = $LASTEXITCODE -eq 0 -or ($out -match "Access denied")
    PassFail "MySQL antwortet auf 127.0.0.1:3306" $reachable
} else {
    PassFail "mysql.exe im PATH" $false "Client fehlt"
}

# ---- (4) MongoDB-Ping -----------------------------------------------------
Write-Host ""
Write-Host "MongoDB-Antwort:" -ForegroundColor Yellow
if (Get-Command mongosh -ErrorAction SilentlyContinue) {
    $out = & mongosh "mongodb://127.0.0.1:27017" --eval "db.runCommand({ping:1})" --quiet 2>&1
    $ok = ($out -match "ok") -or ($out -match "Authentication")
    PassFail "MongoDB antwortet auf 127.0.0.1:27017" $ok
} else {
    PassFail "mongosh im PATH" $false "Client fehlt"
}

# ---- (5) Metabase Healthcheck --------------------------------------------
Write-Host ""
Write-Host "Metabase-HTTP:" -ForegroundColor Yellow
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing -TimeoutSec 5
    PassFail "GET http://localhost:3000/api/health" ($resp.StatusCode -eq 200) $resp.Content
} catch {
    PassFail "GET http://localhost:3000/api/health" $false $_.Exception.Message
}

# ---- (6) Firewall-Regeln --------------------------------------------------
Write-Host ""
Write-Host "Firewall-Regeln:" -ForegroundColor Yellow
foreach ($rule in @("DBS MySQL", "DBS MongoDB", "DBS Metabase")) {
    $fw = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    PassFail "Firewall-Rule: $rule" ($null -ne $fw -and $fw.Enabled -eq "True")
}

Write-Host ""
Write-Host "=== Fertig. ===" -ForegroundColor Cyan
Write-Host "Bei Fehlern: Log unter C:\Metabase\metabase-error.log oder Event Viewer pruefen."
