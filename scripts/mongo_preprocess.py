"""
MongoDB-Preprocessing — bereitet die vier Quelldateien fuer mongoimport vor.

Hintergrund: mongoimport kann zwar JSON und CSV, aber:
  * games.json ist ein VERSCHACHTELTES Dict ({"570": {...}, "730": {...}}),
    nicht JSONL/JSON-Array → muss umgewandelt werden.
  * Twitch_game_data.csv ist cp1252-codiert → mongoimport hat kein
    --encoding-Flag, also auf UTF-8 konvertieren.
  * Wir berechnen name_normalized hier, weil die Aggregation in MongoDB
    sonst sehr umstaendlich waere (Regex-Replace im Pipeline ist clunky).
  * user_review in Metacritic enthaelt literal 'tbd' → in JSONL als null.

Output: data/processed/*.jsonl
Diese werden anschliessend von mongo/03_mongoimport.sh in die Staging-
Collections geladen (stg_games, stg_twitch_month, stg_twitch_global,
stg_metacritic).

Die TATSAECHLICHE Transformation (Lookup, Reshape, $merge in Ziel-Collection)
laeuft in MongoDB via mongo/02_transform.js — dies hier ist nur die
Aufbereitung der Roh-Daten (vergleichbar mit "Laden ins Staging" bei SQL).
"""

from __future__ import annotations

import csv
import json
import os
import re
import sys
from pathlib import Path

# Pfade per Env-Var konfigurierbar (DATA_DIR_RAW / DATA_DIR_PROCESSED),
# Fallback auf Mac-Default fuer lokale Tests.
RAW = Path(os.environ.get("DATA_DIR_RAW") or "/Users/cyrill/PycharmProjects/DBS/data/raw")
OUT = Path(os.environ.get("DATA_DIR_PROCESSED") or "/Users/cyrill/PycharmProjects/DBS/data/processed")


def normalize_title(s: str) -> str:
    if not isinstance(s, str):
        return ""
    s = s.lower().strip()
    s = re.sub(r"[™®©]", "", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def parse_user_review(v) -> float | None:
    if v is None:
        return None
    s = str(v).strip().lower()
    if s in ("", "tbd", "nan"):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def to_int(v) -> int | None:
    if v is None:
        return None
    s = str(v).strip()
    if s == "":
        return None
    try:
        return int(s)
    except ValueError:
        return None


def preprocess_steam_json() -> int:
    """games.json (nested dict) → games.jsonl (one doc per line)."""
    src = RAW / "games.json"
    dst = OUT / "games.jsonl"
    print(f"[steam]  {src.name}  →  {dst.name}")

    with src.open(encoding="utf-8") as f:
        data = json.load(f)

    count = 0
    with dst.open("w", encoding="utf-8") as out:
        for app_id_str, game in data.items():
            try:
                app_id = int(app_id_str)
            except ValueError:
                continue
            game["_id"] = app_id
            game["name_normalized"] = normalize_title(game.get("name", ""))
            out.write(json.dumps(game, ensure_ascii=False) + "\n")
            count += 1
    return count


def preprocess_twitch_month() -> int:
    """Twitch_game_data.csv (cp1252) → twitch_month.jsonl (utf-8, normalized)."""
    src = RAW / "Twitch_game_data.csv"
    dst = OUT / "twitch_month.jsonl"
    print(f"[twitch] {src.name}  →  {dst.name}")

    count = 0
    with src.open(encoding="cp1252") as f, dst.open("w", encoding="utf-8") as out:
        reader = csv.DictReader(f)
        for row in reader:
            game = (row.get("Game") or "").strip()
            if not game:
                continue
            doc = {
                "game":              game,
                "name_normalized":   normalize_title(game),
                "year":              to_int(row.get("Year")),
                "month":             to_int(row.get("Month")),
                "rank":              to_int(row.get("Rank")),
                "hours_watched":     to_int(row.get("Hours_watched")),
                "hours_streamed":    to_int(row.get("Hours_streamed")),
                "peak_viewers":      to_int(row.get("Peak_viewers")),
                "peak_channels":     to_int(row.get("Peak_channels")),
                "streamers":         to_int(row.get("Streamers")),
                "avg_viewers":       to_int(row.get("Avg_viewers")),
                "avg_channels":      to_int(row.get("Avg_channels")),
                "avg_viewer_ratio":  float(row.get("Avg_viewer_ratio") or 0),
            }
            out.write(json.dumps(doc, ensure_ascii=False) + "\n")
            count += 1
    return count


def preprocess_twitch_global() -> int:
    """Twitch_global_data.csv → twitch_global.jsonl mit _id: {year, month}."""
    src = RAW / "Twitch_global_data.csv"
    dst = OUT / "twitch_global.jsonl"
    print(f"[twitch] {src.name} →  {dst.name}")

    count = 0
    with src.open(encoding="utf-8") as f, dst.open("w", encoding="utf-8") as out:
        reader = csv.DictReader(f)
        for row in reader:
            year, month = to_int(row.get("year")), to_int(row.get("Month"))
            if year is None or month is None:
                continue
            doc = {
                "_id": {"year": year, "month": month},
                "total_hours_watched": to_int(row.get("Hours_watched")) or 0,
                "total_avg_viewers":   to_int(row.get("Avg_viewers"))   or 0,
                "total_peak_viewers":  to_int(row.get("Peak_viewers"))  or 0,
                "total_streams":       to_int(row.get("Streams"))       or 0,
                "total_avg_channels":  to_int(row.get("Avg_channels"))  or 0,
                "games_streamed":      to_int(row.get("Games_streamed"))or 0,
                "viewer_ratio":        float(row.get("Viewer_ratio") or 0),
            }
            out.write(json.dumps(doc, ensure_ascii=False) + "\n")
            count += 1
    return count


def preprocess_metacritic() -> int:
    """all_games.csv → metacritic.jsonl mit normalisiertem Titel und tbd→null."""
    src = RAW / "all_games.csv"
    dst = OUT / "metacritic.jsonl"
    print(f"[meta]   {src.name}        →  {dst.name}")

    count = 0
    with src.open(encoding="utf-8") as f, dst.open("w", encoding="utf-8") as out:
        reader = csv.DictReader(f)
        for row in reader:
            name = (row.get("name") or "").strip()
            if not name:
                continue
            doc = {
                "name":              name,
                "name_normalized":   normalize_title(name),
                "platform":          (row.get("platform") or "").strip(),
                "release_date":      (row.get("release_date") or "").strip() or None,
                "summary":           (row.get("summary") or "").strip() or None,
                "meta_score":        to_int(row.get("meta_score")),
                "user_review":       parse_user_review(row.get("user_review")),
            }
            out.write(json.dumps(doc, ensure_ascii=False) + "\n")
            count += 1
    return count


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"Schreibe nach: {OUT}")
    n_steam  = preprocess_steam_json()
    n_twitch = preprocess_twitch_month()
    n_twg    = preprocess_twitch_global()
    n_meta   = preprocess_metacritic()
    print()
    print("Fertig:")
    print(f"  steam   : {n_steam:>7,} Docs")
    print(f"  twitch  : {n_twitch:>7,} Docs")
    print(f"  twg     : {n_twg:>7,} Docs")
    print(f"  meta    : {n_meta:>7,} Docs")


if __name__ == "__main__":
    try:
        main()
    except FileNotFoundError as e:
        print(f"FEHLER: Eingabedatei fehlt: {e}", file=sys.stderr)
        sys.exit(1)
