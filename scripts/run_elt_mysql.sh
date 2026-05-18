#!/usr/bin/env bash
# =============================================================================
# DBS-Projekt "Game Hype Index" — MySQL ELT Orchestrator
# =============================================================================
# Fuehrt die vier MySQL-Phasen in Reihe aus:
#   1. Zielschema (sql/01_schema.sql)
#   2. Staging-Schema (sql/02_staging_schema.sql)
#   3. LOAD DATA INFILE (sql/03_load.sql)  — mit Pfad-Substitution
#   4. Transform via INSERT ... SELECT (sql/04_transform.sql)
#
# Konfiguration via Umgebungsvariablen (alle optional, mit Defaults):
#   MYSQL_HOST   (default: localhost)
#   MYSQL_PORT   (default: 3306)
#   MYSQL_USER   (default: root)
#   MYSQL_PASS   (default: leer — empfohlen: per ~/.my.cnf statt env setzen)
#   DATA_DIR     (default: <repo>/data/raw)
#
# Voraussetzungen auf der VM:
#   * MySQL Server 8.x mit local_infile=ON (server-seitig)
#     SET GLOBAL local_infile = 1;
#   * mysql Client im PATH
#
# Beispiel:
#   MYSQL_HOST=vm.hslu.ch MYSQL_USER=cyrill MYSQL_PASS=xxx ./scripts/run_elt_mysql.sh
# =============================================================================

set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-}"
DATA_DIR="${DATA_DIR:-$PROJ_ROOT/data/raw}"

mysql_args=(--local-infile=1 -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER")
if [[ -n "$MYSQL_PASS" ]]; then
    mysql_args+=("-p$MYSQL_PASS")
fi

if [[ ! -d "$DATA_DIR" ]]; then
    echo "FEHLER: DATA_DIR existiert nicht: $DATA_DIR" >&2
    exit 1
fi

# Auf Git Bash / MSYS: Unix-Pfad (/e/...) in Windows-Pfad (E:/...) umwandeln,
# weil mysql.exe ein Windows-Binary ist und Unix-Pfade nicht versteht.
# Forward-Slashes sind unter Windows-MySQL OK.
if command -v cygpath > /dev/null 2>&1; then
    DATA_DIR_MYSQL=$(cygpath -m "$DATA_DIR")
else
    DATA_DIR_MYSQL="$DATA_DIR"
fi

echo "=== Game Hype Index - MySQL ELT ==="
echo "    Host       : $MYSQL_HOST:$MYSQL_PORT"
echo "    User       : $MYSQL_USER"
echo "    Data (sh)  : $DATA_DIR"
echo "    Data (sql) : $DATA_DIR_MYSQL"
echo ""

echo ">>> [1/4] Zielschema (DROP + CREATE)..."
mysql "${mysql_args[@]}" < "$PROJ_ROOT/sql/01_schema.sql"

echo ">>> [2/4] Staging-Schema..."
mysql "${mysql_args[@]}" game_hype_index < "$PROJ_ROOT/sql/02_staging_schema.sql"

echo ">>> [3/4] LOAD DATA INFILE (gross -- kann mehrere Minuten dauern)..."
sed "s|{{DATA_DIR}}|$DATA_DIR_MYSQL|g" "$PROJ_ROOT/sql/03_load.sql" \
    | mysql "${mysql_args[@]}" game_hype_index

echo ">>> [4/4] Transformation ins Zielschema..."
mysql "${mysql_args[@]}" game_hype_index < "$PROJ_ROOT/sql/04_transform.sql"

echo ""
echo "=== Fertig. ==="
