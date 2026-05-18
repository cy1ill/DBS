# VM-Setup HSLU Lab Services — Game Hype Index

Dieses Dokument fuehrt Schritt fuer Schritt durch das komplette VM-Setup fuer das DBS-Projekt. Die manuellen Schritte (ILIAS-Reservierung, RDP, Passwort) sind unvermeidbar, alles andere ist scripted (PowerShell auf der VM, Bash lokal).

**Architektur-Ueberblick:**

```
                 [Internet / HSLU-VPN]
                          │
                          ▼
              ┌──────────────────────────┐
              │  Windows Server VM       │
              │  abc-XYZ.ls.eee.intern   │
              │                          │
              │  RDP :3389 (labadmin)    │
              │  MySQL :3306             │
              │  MongoDB :27017          │
              │  Metabase :3000  (HTTP)  │
              │                          │
              │  Code unter C:\dbs       │
              │  Daten unter C:\dbs\data │
              └──────────────────────────┘
                          ▲
                          │ git clone / git pull
              ┌──────────────────────────┐
              │  GitHub Private Repo     │
              └──────────────────────────┘
                          ▲
                          │ git push
                ┌─────────────────┐
                │  Mac (lokal)    │
                │  /PycharmProjects/DBS │
                └─────────────────┘
```

---

## Phase A: VM in ILIAS reservieren

1. ILIAS → Modul **Datenbanksysteme** → Ordner **Administration**
2. Link zum **Inscription-Excel** oeffnen (Sharepoint/OneDrive)
3. In einer freien Zeile eintragen:
   - **Team Name:** z.B. `Cyrill-Solo` (du machst es alleine)
   - **Projekttitel:** `Game Hype Index — Steam × Twitch × Metacritic`
4. Die zugewiesene **VM-Domain** notieren (Format: `xxx-NNN-yyyy.ls.eee.intern`)
5. **Standard-Passwort** aus der Excel-Spalte kopieren
6. Im ILIAS unter Projekt → Umfrage **die folgenden Felder vorbereiten** (Eintrag erst nach komplettem Setup):
   - VM-Domain
   - MySQL Host/Port/User/Passwort (Bewertungs-User, nicht admin/root)
   - MongoDB URI inkl. User/Passwort
   - Metabase-URL inkl. Login

> **Wichtig:** Server NIE herunterfahren. Bei Reboot-Bedarf Lab Services kontaktieren.

---

## Phase B: Erstes Login via RDP

### Mac (du)
1. App Store → **"Windows App"** installieren (frueher "Microsoft Remote Desktop")
2. Wenn off-campus: **VPN Pulse Secure** verbinden ([HSLU VPN Anleitung](https://www.hslu.ch/de-ch/hochschule-luzern/campus/bibliotheken/e-medien/))
3. In Windows App → **Add PC**:
   - PC name: `<deine-vm-domain>`
   - User account: `labadmin` / `<standard-passwort>`
4. Doppelklick auf den Eintrag → verbinden

### Passwort sofort aendern
1. Im RDP-Fenster: Bildschirm-Tastatur oeffnen
   - Start → `osk` tippen → **On Screen Keyboard**
2. **Strg+Alt** auf physischer Tastatur halten + **Del** auf der OSK klicken
3. Menue: **Change a password**
4. Altes + neues Passwort eintragen. Notiere das neue Passwort sofort an einem sicheren Ort (Passwort-Manager).

---

## Phase C: Bootstrap — Software-Installation

Auf der VM eine **PowerShell als Administrator** oeffnen (Start → "powershell" → Rechtsklick → "Als Administrator ausfuehren").

### Schritt 1: Repository per Git holen

```powershell
# Chocolatey installieren (Paket-Manager — basis fuer alles weitere)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Git installieren
choco install git -y
# PowerShell neu starten, damit git im PATH ist!

# Code holen (nach dem du dein GitHub-Repo erstellt hast, siehe Phase H)
mkdir C:\dbs
cd C:\dbs
git clone https://github.com/<dein-user>/<dein-repo>.git .
```

### Schritt 2: Alles andere per Bootstrap-Skript

```powershell
# Im Projektordner (C:\dbs)
.\scripts\vm\01_bootstrap.ps1
```

Das Skript installiert:
- Visual C++ Redistributable (Pflicht fuer MySQL)
- **MySQL Server 8.x** + **MySQL Workbench**
- **MongoDB Community Server 7.x** + **MongoDB Database Tools** (mongoimport)
- **mongosh** (MongoDB Shell)
- **Java 17** (Temurin LTS, fuer Metabase)
- **Python 3.12** (fuer Preprocessing)
- **NSSM** (Service-Wrapper fuer Metabase)
- **Metabase JAR** nach `C:\Metabase\`
- **Python-Pakete** (pandas) per pip

Laufzeit: ~15-25 Min, viele Downloads.

---

## Phase D: Services konfigurieren

```powershell
.\scripts\vm\02_configure_services.ps1
```

Macht folgendes:
- MySQL `my.ini` patchen: `local_infile=1`, `character-set-server=utf8mb4`, `secure_file_priv=""`
- MongoDB `mongod.cfg` patchen: `bindIp: 0.0.0.0`, Auth aktivieren
- Metabase als Windows-Service via NSSM einrichten und starten (Port 3000)
- **Firewall-Regeln** fuer Ports 3306 (MySQL), 27017 (MongoDB), 3000 (Metabase)
- Alle Services restarten

---

## Phase E: DB-Benutzer anlegen

Du brauchst pro DBMS zwei Accounts: einen **Admin** (du), einen **Read-Only-Grader** (fuer den Dozenten zur Einsicht).

### MySQL — via Workbench oder mysql.exe

```sql
-- Admin-User (volle Rechte, ueber Netzwerk erreichbar)
CREATE USER 'dbs_admin'@'%' IDENTIFIED BY 'WAEHLE_STARKES_PASSWORT_1';
GRANT ALL PRIVILEGES ON game_hype_index.* TO 'dbs_admin'@'%';

-- Grading-User (read-only auf die Projekt-DB)
CREATE USER 'grader'@'%' IDENTIFIED BY 'WAEHLE_STARKES_PASSWORT_2';
GRANT SELECT, SHOW VIEW ON game_hype_index.* TO 'grader'@'%';

FLUSH PRIVILEGES;
```

Snippets liegen unter `sql/99_users.sql` (anpassen vor Ausfuehrung).

### MongoDB — via mongosh

```javascript
use admin

db.createUser({
    user: "dbs_admin",
    pwd: "WAEHLE_STARKES_PASSWORT_3",
    roles: [{ role: "root", db: "admin" }]
})

db.createUser({
    user: "grader",
    pwd: "WAEHLE_STARKES_PASSWORT_4",
    roles: [{ role: "read", db: "game_hype_index" }]
})
```

Snippets liegen unter `mongo/99_users.js`.

> Nach dem Anlegen der MongoDB-Users **`mongod.cfg` Authentication aktivieren** (macht das Configure-Skript bereits — danach ist Anmeldung Pflicht).

---

## Phase F: Daten auf die VM bringen

Drei Optionen, ich empfehle Option 2:

**Option 1 — Re-Download via Kaggle CLI auf der VM** (schnell wenn Kaggle-Account vorhanden):
```powershell
pip install kaggle
# kaggle.json nach %USERPROFILE%\.kaggle\ legen
kaggle datasets download -d fronkongames/steam-games-dataset -p C:\dbs\data\raw --unzip
kaggle datasets download -d rankirsh/evolution-of-top-games-on-twitch -p C:\dbs\data\raw --unzip
kaggle datasets download -d deepcontractor/top-video-games-19952021-metacritic -p C:\dbs\data\raw --unzip
```

**Option 2 — OneDrive-Upload (empfohlen, einfach)**:
Du laedst die 4 Roh-Dateien (~415 MB) auf dein OneDrive hoch (HSLU-Account), oeffnest dann auf der VM den Edge-Browser, laedst sie nach `C:\dbs\data\raw\` herunter.

**Option 3 — git-lfs**: zu komplex fuer 800 MB JSON, ueberspringen.

---

## Phase G: ELT ausfuehren

```powershell
# Git Bash oeffnen (nicht PowerShell — die .sh-Skripte brauchen bash)
cd /c/dbs

# MySQL ELT
MYSQL_HOST=localhost MYSQL_USER=dbs_admin MYSQL_PASS='dein_pwd' \
    ./scripts/run_elt_mysql.sh

# MongoDB ELT
MONGO_URI="mongodb://dbs_admin:dein_pwd@localhost:27017" \
    ./scripts/run_elt_mongo.sh
```

Beide Skripte loggen jeden Schritt mit Row-Counts. Erwartete End-Counts:
- MySQL: 122k games, ~21k twitch_month, ~5k metacritic_entry
- MongoDB: 122k Docs in games, davon ~1.4k mit Twitch-Timeline

---

## Phase H: Code-Transfer per Git

### Lokal (Mac) — einmalig
1. GitHub-Account: privates Repo `dbs-game-hype-index` anlegen
2. Im Mac-Terminal:
   ```bash
   cd /Users/cyrill/PycharmProjects/DBS
   git remote add origin git@github.com:<dein-user>/dbs-game-hype-index.git
   git branch -M main
   git push -u origin main
   ```

### Pro Aenderung lokal
```bash
git add -A
git commit -m "..."
git push
```

### Auf der VM — neue Version holen
```powershell
cd C:\dbs
git pull
```

### Wichtig: `.gitignore` (liegt bereits im Repo)
- `data/raw/`, `data/processed/`, `.venv/` werden nicht committed (zu gross)
- Die Roh-Dateien werden via OneDrive-Upload (Phase F) auf die VM gebracht

---

## Phase I: Metabase initial einrichten

1. Im Browser: `http://localhost:3000` (auf der VM) oder `http://<vm-domain>:3000` (von extern via VPN)
2. Initialer Setup-Wizard:
   - Sprache: Deutsch
   - Account: vorname.name + dein Passwort
   - Datenbank-Anbindung #1: **MySQL**
     - Host: `localhost`
     - Port: `3306`
     - Database: `game_hype_index`
     - User: `dbs_admin`
     - Pass: <dein Pwd>
   - Datenbank-Anbindung #2: **MongoDB** (Add Database nach dem Wizard)
     - Host: `localhost`
     - Port: `27017`
     - Database: `game_hype_index`
     - User: `dbs_admin`
     - Auth-DB: `admin`

> Metabase laeuft als Windows-Service ("Metabase") — startet automatisch nach Reboot.

---

## Phase J: Test-Verbindung von extern (deine Bewertungs-Probe)

Von deinem Mac (mit aktiver HSLU-VPN):

```bash
# MySQL
mysql -h <vm-domain> -P 3306 -u grader -p
# erwartet: SELECT COUNT(*) FROM game_hype_index.game;

# MongoDB
mongosh "mongodb://grader:<pwd>@<vm-domain>:27017/game_hype_index?authSource=admin"
# erwartet: db.games.countDocuments()

# Metabase
open "http://<vm-domain>:3000"
# Login mit deinem Account
```

---

## Phase K: Credentials in ILIAS-Umfrage eintragen

Endgueltige Werte in die ILIAS-Umfrage (Ordner Projekt) eintragen:

| Feld | Wert |
|---|---|
| VM-Domain | `xxx-NNN-yyyy.ls.eee.intern` |
| Windows User (RDP) | `labadmin` (Passwort nur fuer dich) |
| MySQL Host | `<vm-domain>` |
| MySQL Port | `3306` |
| MySQL User | `grader` |
| MySQL Pass | `<grader-mysql-pwd>` |
| MySQL DB | `game_hype_index` |
| MongoDB URI | `mongodb://grader:<pwd>@<vm-domain>:27017/game_hype_index?authSource=admin` |
| Metabase URL | `http://<vm-domain>:3000` |
| Metabase Login | `prof@hslu.ch` / `<pwd>` (separater Read-Only-Account in Metabase) |

---

## Troubleshooting

| Symptom | Loesung |
|---|---|
| Kann VM nicht pingen | VPN-Verbindung prüfen (Pulse Secure aktiv?) |
| MySQL ERROR 2003 (Connection refused) | Firewall-Port 3306 offen? Service "MySQL80" laeuft? |
| MySQL ERROR 1148 (local_infile) | In `my.ini` `local_infile=1`, Server restarten |
| MongoDB Auth-Fehler | URI muss `?authSource=admin` enthalten |
| Metabase startet nicht | Logs unter `C:\Metabase\metabase.log`; Java 17 installiert? |
| RDP "max users" | Lab Services hat 2-User-Limit; andere Session schliessen |

---

## Reihenfolge zusammengefasst

1. **Phase A** — ILIAS-Reservierung (5 min)
2. **Phase B** — RDP-Login + Passwort aendern (10 min)
3. **Phase H** vorziehen — GitHub-Repo erstellen + lokal pushen (10 min)
4. **Phase C** — Git clone + Bootstrap-Skript (20 min, viele Downloads)
5. **Phase D** — Services konfigurieren (5 min)
6. **Phase E** — DB-User anlegen (10 min)
7. **Phase F** — Roh-Daten hochladen (10 min)
8. **Phase G** — ELT ausfuehren (5-15 min je nach VM)
9. **Phase I** — Metabase Setup (10 min)
10. **Phase J** — Externer Test (5 min)
11. **Phase K** — ILIAS-Eintraege (5 min)

**Total ~2 Stunden** wenn alles glatt laeuft.
