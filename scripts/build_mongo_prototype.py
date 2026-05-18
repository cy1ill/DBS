"""
Erzeugt einen MongoDB-Beispiel-Dokumentprototyp aus echten Quelldaten.

Strategie: Waehle ein Spiel, das in allen drei Quellen (Steam, Twitch, Metacritic)
vorhanden ist und gut bekannt sowie reichhaltig befuellt ist. Baue daraus das
denormalisierte Game-Dokument, wie es spaeter in der games-Collection landen wird.

Zweck: Belegt den JSON-Prototyp im Bericht mit echten Werten und zeigt, dass die
Struktur tatsaechlich aus den Quellen ableitbar ist.
"""

from __future__ import annotations

import ast
import json
import os
import re
from datetime import datetime
from pathlib import Path

import pandas as pd

_PROJ_ROOT = Path(__file__).resolve().parent.parent
RAW = Path(os.environ.get("DATA_DIR_RAW") or (_PROJ_ROOT / "data" / "raw"))
OUT_DIR = Path(os.environ.get("MONGO_PROTOTYPE_OUT") or (_PROJ_ROOT / "mongo"))

STEAM_COLUMNS = [
    "AppID", "Name", "Release date", "Estimated owners", "Peak CCU",
    "Required age", "Price", "Discount", "DLC count", "About the game",
    "Supported languages", "Full audio languages", "Reviews", "Header image",
    "Website", "Support url", "Support email", "Windows", "Mac", "Linux",
    "Metacritic score", "Metacritic url", "User score", "Positive", "Negative",
    "Score rank", "Achievements", "Recommendations", "Notes",
    "Average playtime forever", "Average playtime two weeks",
    "Median playtime forever", "Median playtime two weeks",
    "Developers", "Publishers", "Categories", "Genres", "Tags",
    "Screenshots", "Movies",
]

# Spiel, das in allen drei Quellen prominent vertreten ist
TARGET_TITLES = [
    "Counter-Strike: Global Offensive",
    "Dota 2",
    "Cyberpunk 2077",
    "The Witcher 3: Wild Hunt",
    "Hades",
]


def norm(s: str) -> str:
    if not isinstance(s, str):
        return ""
    s = s.lower().strip()
    s = re.sub(r"[™®©]", "", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def parse_owners_range(s: str) -> tuple[int | None, int | None]:
    if not isinstance(s, str) or " - " not in s:
        return None, None
    a, b = s.split(" - ", 1)
    try:
        return int(a), int(b)
    except ValueError:
        return None, None


def parse_release_date(s) -> str | None:
    if not isinstance(s, str):
        return None
    for fmt in ("%b %d, %Y", "%d %b, %Y", "%B %d, %Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s.strip(), fmt).date().isoformat()
        except ValueError:
            continue
    return None


def split_csv_list(s) -> list[str]:
    if not isinstance(s, str) or not s.strip():
        return []
    return [x.strip() for x in s.split(",") if x.strip()]


def parse_lang_list(s) -> list[str]:
    """Steam-Sprachen sind Python-Listen-Strings: "['English','German']"."""
    if not isinstance(s, str) or s.strip() in ("", "[]"):
        return []
    try:
        v = ast.literal_eval(s)
        if isinstance(v, list):
            return [str(x).strip() for x in v if str(x).strip()]
    except (ValueError, SyntaxError):
        pass
    return []


def parse_user_review(v) -> float | None:
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    s = str(v).strip().lower()
    if s in ("", "tbd", "nan"):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def main() -> None:
    print("Lade Quelldaten...")
    steam = pd.read_csv(RAW / "games.csv", low_memory=False, header=0, names=STEAM_COLUMNS)
    twitch = pd.read_csv(RAW / "Twitch_game_data.csv", encoding="cp1252")
    meta = pd.read_csv(RAW / "all_games.csv")
    meta.columns = [c.strip() for c in meta.columns]
    twg = pd.read_csv(RAW / "Twitch_global_data.csv")

    steam["_norm"] = steam["Name"].map(norm)
    twitch["_norm"] = twitch["Game"].map(norm)
    meta["_norm"] = meta["name"].map(norm)

    twitch_norms = set(twitch["_norm"]) - {""}
    meta_norms = set(meta["_norm"]) - {""}

    chosen = None
    for title in TARGET_TITLES:
        n = norm(title)
        if n in twitch_norms and n in meta_norms:
            row = steam[steam["_norm"] == n]
            if not row.empty:
                chosen = (title, n, row.iloc[0])
                break
    if chosen is None:
        raise SystemExit("Kein Zielspiel in allen drei Quellen gefunden.")

    title, ntitle, srow = chosen
    print(f"Gewaehlt: {title!r} (normalisiert: {ntitle!r}, AppID {int(srow['AppID'])})")

    # ---- Aufbau Game-Dokument ----
    owners_min, owners_max = parse_owners_range(srow["Estimated owners"])

    languages_supported = parse_lang_list(srow["Supported languages"])
    languages_audio = parse_lang_list(srow["Full audio languages"])

    metacritic_rows = meta[meta["_norm"] == ntitle][
        ["platform", "meta_score", "user_review", "summary", "release_date"]
    ]
    metacritic = []
    for _, mr in metacritic_rows.iterrows():
        metacritic.append({
            "platform": str(mr["platform"]).strip(),
            "meta_score": int(mr["meta_score"]) if pd.notna(mr["meta_score"]) else None,
            "user_review": parse_user_review(mr["user_review"]),
            "summary": (str(mr["summary"]).strip() if pd.notna(mr["summary"]) else None),
            "release_date": parse_release_date(mr["release_date"]),
        })

    twitch_rows = (
        twitch[twitch["_norm"] == ntitle]
        .sort_values(["Year", "Month"])
        .head(60)  # erstes Fuenfjahres-Fenster, Beispiel-Doku reicht
    )
    timeline = []
    for _, tr in twitch_rows.iterrows():
        timeline.append({
            "year": int(tr["Year"]),
            "month": int(tr["Month"]),
            "rank": int(tr["Rank"]),
            "hours_watched": int(tr["Hours_watched"]),
            "hours_streamed": int(tr["Hours_streamed"]),
            "peak_viewers": int(tr["Peak_viewers"]),
            "peak_channels": int(tr["Peak_channels"]),
            "streamers": int(tr["Streamers"]),
            "avg_viewers": int(tr["Avg_viewers"]),
            "avg_channels": int(tr["Avg_channels"]),
            "avg_viewer_ratio": float(tr["Avg_viewer_ratio"]),
        })

    doc = {
        "_id": int(srow["AppID"]),
        "name": srow["Name"],
        "name_normalized": ntitle,
        "release_date": parse_release_date(srow["Release date"]),
        "required_age": int(srow["Required age"]) if pd.notna(srow["Required age"]) else 0,
        "price_usd": float(srow["Price"]) if pd.notna(srow["Price"]) else 0.0,
        "discount_pct": int(srow["Discount"]) if pd.notna(srow["Discount"]) else 0,
        "dlc_count": int(srow["DLC count"]) if pd.notna(srow["DLC count"]) else 0,
        "about": srow["About the game"] if isinstance(srow["About the game"], str) else None,
        "header_image_url": srow["Header image"] if isinstance(srow["Header image"], str) else None,
        "owners": {"min": owners_min, "max": owners_max},
        "peak_ccu": int(srow["Peak CCU"]) if pd.notna(srow["Peak CCU"]) else 0,
        "platforms": {
            "windows": bool(srow["Windows"]),
            "mac": bool(srow["Mac"]),
            "linux": bool(srow["Linux"]),
        },
        "steam_scores": {
            "meta_score": int(srow["Metacritic score"]) if pd.notna(srow["Metacritic score"]) and srow["Metacritic score"] > 0 else None,
            "user_score": int(srow["User score"]) if pd.notna(srow["User score"]) and srow["User score"] > 0 else None,
            "positive_reviews": int(srow["Positive"]) if pd.notna(srow["Positive"]) else 0,
            "negative_reviews": int(srow["Negative"]) if pd.notna(srow["Negative"]) else 0,
        },
        "playtime_min": {
            "avg_forever": int(srow["Average playtime forever"]) if pd.notna(srow["Average playtime forever"]) else 0,
            "median_forever": int(srow["Median playtime forever"]) if pd.notna(srow["Median playtime forever"]) else 0,
        },
        "achievements": int(srow["Achievements"]) if pd.notna(srow["Achievements"]) else 0,
        "recommendations": int(srow["Recommendations"]) if pd.notna(srow["Recommendations"]) else 0,
        "developers": split_csv_list(srow["Developers"]),
        "publishers": split_csv_list(srow["Publishers"]),
        "genres": split_csv_list(srow["Genres"]),
        "categories": split_csv_list(srow["Categories"]),
        "tags": split_csv_list(srow["Tags"]),
        "languages": {
            "supported": languages_supported,
            "full_audio": languages_audio,
        },
        "metacritic": metacritic,
        "twitch_timeline": timeline,
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    game_out = OUT_DIR / "sample_game_document.json"
    game_out.write_text(json.dumps(doc, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Game-Beispiel geschrieben: {game_out} ({game_out.stat().st_size:,} bytes)")

    # ---- Twitch-Global-Beispiel ----
    tg_doc = {
        "_id": {"year": int(twg.iloc[0]["year"]), "month": int(twg.iloc[0]["Month"])},
        "total_hours_watched": int(twg.iloc[0]["Hours_watched"]),
        "total_avg_viewers": int(twg.iloc[0]["Avg_viewers"]),
        "total_peak_viewers": int(twg.iloc[0]["Peak_viewers"]),
        "total_streams": int(twg.iloc[0]["Streams"]),
        "total_avg_channels": int(twg.iloc[0]["Avg_channels"]),
        "games_streamed": int(twg.iloc[0]["Games_streamed"]),
        "viewer_ratio": float(twg.iloc[0]["Viewer_ratio"]),
    }
    tg_out = OUT_DIR / "sample_twitch_global_document.json"
    tg_out.write_text(json.dumps(tg_doc, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Twitch-Global-Beispiel geschrieben: {tg_out}")

    print()
    print(f"Statistik Game-Dokument:")
    print(f"  - developers: {len(doc['developers'])}")
    print(f"  - genres: {len(doc['genres'])}")
    print(f"  - categories: {len(doc['categories'])}")
    print(f"  - tags: {len(doc['tags'])}")
    print(f"  - languages.supported: {len(doc['languages']['supported'])}")
    print(f"  - languages.full_audio: {len(doc['languages']['full_audio'])}")
    print(f"  - metacritic entries: {len(doc['metacritic'])}")
    print(f"  - twitch_timeline months: {len(doc['twitch_timeline'])}")


if __name__ == "__main__":
    main()
