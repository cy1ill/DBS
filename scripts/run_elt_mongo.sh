#!/usr/bin/env bash
# =============================================================================
# DBS-Projekt "Game Hype Index" — MongoDB ELT Orchestrator
# =============================================================================
# Fuehrt die vier MongoDB-Phasen in Reihe aus:
#   1. Preprocessing (Python): nested JSON → JSONL, CSV → JSONL,
#      mit name_normalized als Join-Schluessel.
#   2. mongoimport in vier Staging-Collections (stg_*).
#   3. Ziel-Collections erstellen mit JSON-Schema-Validatoren.
#   4. Aggregation Pipeline mit $lookup + $merge → finale Collections.
#
# Konfiguration via Umgebungsvariablen:
#   MONGO_URI       (default: mongodb://localhost:27017)
#   DB_NAME         (default: game_hype_index)
#   PYTHON          (default: <repo>/.venv/bin/python)
#   MONGOIMPORT     (default: mongoimport im PATH)
#   MONGOSH         (default: mongosh im PATH)
#
# Voraussetzungen auf der VM:
#   * MongoDB 6.x oder neuer
#   * mongosh und mongoimport (Database Tools) im PATH
#   * Python 3 + json/csv (Standardbibliothek reicht — kein pandas noetig)
#
# Beispiel:
#   MONGO_URI="mongodb://cyrill:pass@vm.hslu.ch:27017" ./scripts/run_elt_mongo.sh
# =============================================================================

set -euo pipefail

PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MONGO_URI="${MONGO_URI:-mongodb://localhost:27017}"
DB_NAME="${DB_NAME:-game_hype_index}"
# Python-Pfad finden: erst venv (lokale Entwicklung), dann python3 / python im PATH
if [[ -n "${PYTHON:-}" ]]; then
    :  # User-Override respektieren
elif [[ -x "$PROJ_ROOT/.venv/bin/python" ]]; then
    PYTHON="$PROJ_ROOT/.venv/bin/python"
elif command -v python3 > /dev/null 2>&1; then
    PYTHON="python3"
elif command -v python > /dev/null 2>&1; then
    PYTHON="python"
else
    echo "FEHLER: Kein Python gefunden. Setze PYTHON=<pfad> als env var." >&2
    exit 1
fi
MONGOIMPORT="${MONGOIMPORT:-mongoimport}"
MONGOSH="${MONGOSH:-mongosh}"

DATA_DIR_RAW="${DATA_DIR_RAW:-$PROJ_ROOT/data/raw}"
PROCESSED_DIR="${DATA_DIR_PROCESSED:-$PROJ_ROOT/data/processed}"
export DATA_DIR_RAW
export DATA_DIR_PROCESSED="$PROCESSED_DIR"

echo "=== Game Hype Index - MongoDB ELT ==="
echo "    URI       : $MONGO_URI"
echo "    DB        : $DB_NAME"
echo "    Python    : $PYTHON"
echo "    Raw data  : $DATA_DIR_RAW"
echo "    Processed : $PROCESSED_DIR"
echo ""

echo ">>> [1/4] Preprocessing (Python) → data/processed/*.jsonl ..."
"$PYTHON" "$PROJ_ROOT/scripts/mongo_preprocess.py"

# Konstruiere Target-URI fuer game_hype_index (mit authSource=admin).
# MONGO_URI kann mit /admin oder /db enden -- wir strippen das und bauen sauber neu.
BASE_URI=$(echo "$MONGO_URI" | sed -E 's|^(mongodb(\+srv)?://[^/?]+).*|\1|')
TARGET_URI="${BASE_URI}/${DB_NAME}?authSource=admin"
echo "    Target URI: $TARGET_URI"

echo ">>> [2/4] mongoimport in Staging-Collections..."
"$MONGOIMPORT" --uri "$TARGET_URI" \
    --collection stg_games --file "$PROCESSED_DIR/games.jsonl" \
    --type json --drop
"$MONGOIMPORT" --uri "$TARGET_URI" \
    --collection stg_twitch_month --file "$PROCESSED_DIR/twitch_month.jsonl" \
    --type json --drop
"$MONGOIMPORT" --uri "$TARGET_URI" \
    --collection stg_twitch_global --file "$PROCESSED_DIR/twitch_global.jsonl" \
    --type json --drop
"$MONGOIMPORT" --uri "$TARGET_URI" \
    --collection stg_metacritic --file "$PROCESSED_DIR/metacritic.jsonl" \
    --type json --drop

echo ">>> [3/4] Ziel-Collections mit JSON-Schema-Validator anlegen..."
"$MONGOSH" "$TARGET_URI" --quiet \
    --file "$PROJ_ROOT/mongo/01_create_collections.js"

echo ">>> [4/4] Aggregation Pipeline: stg_* → games / twitch_global ..."
"$MONGOSH" "$TARGET_URI" --quiet \
    --file "$PROJ_ROOT/mongo/02_transform.js"

echo ""
echo "=== Fertig. ==="
