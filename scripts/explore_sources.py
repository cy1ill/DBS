"""
Quelldatenanalyse fuer DBS-Projekt "Game Hype Index".

Profiliert die drei Rohquellen unter data/raw/ und schreibt einen
Markdown-Report nach reports/source_exploration.md.

Zweck: Grundlage fuer das konzeptionelle ER-Modell (Schritt 2 des Auftrags).
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pandas as pd

RAW = Path("/Users/cyrill/PycharmProjects/DBS/data/raw")
REPORT = Path("/Users/cyrill/PycharmProjects/DBS/reports/source_exploration.md")

STEAM_CSV = RAW / "games.csv"
TWITCH_GAMES_CSV = RAW / "Twitch_game_data.csv"
TWITCH_GLOBAL_CSV = RAW / "Twitch_global_data.csv"
METACRITIC_CSV = RAW / "all_games.csv"

# Steam-CSV-Header ist fehlerhaft: "DiscountDLC count" steht im Header als
# eine Spalte, in den Daten sind es zwei. Wir erzwingen die korrekte 40-Spalten-
# Struktur (siehe games.json fuer die kanonischen Feldnamen).
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


def normalize_title(s: str) -> str:
    """Lowercased, stripped, punctuation-reduced title for fuzzy joins."""
    if not isinstance(s, str):
        return ""
    s = s.lower().strip()
    s = re.sub(r"[™®©]", "", s)  # tm, r, c
    s = re.sub(r"[^a-z0-9]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def file_size_mb(p: Path) -> float:
    return p.stat().st_size / (1024 * 1024)


def count_lines(p: Path) -> int:
    with p.open("rb") as f:
        return sum(1 for _ in f) - 1  # minus header


def read_csv_robust(path: Path, **kwargs) -> tuple[pd.DataFrame, str]:
    """Try common encodings until one works. Returns (df, used_encoding)."""
    last_err: Exception | None = None
    for enc in ("utf-8", "utf-8-sig", "cp1252", "latin-1"):
        try:
            return pd.read_csv(path, encoding=enc, **kwargs), enc
        except UnicodeDecodeError as e:
            last_err = e
    raise RuntimeError(f"Could not decode {path}: {last_err}")


def profile_dataframe(df: pd.DataFrame, name: str) -> list[str]:
    lines = [f"### Spalten ({len(df.columns)})\n"]
    lines.append("| # | Spalte | Dtype | Nulls | Beispiel |")
    lines.append("|---|---|---|---|---|")
    for i, col in enumerate(df.columns, 1):
        dtype = str(df[col].dtype)
        nulls = int(df[col].isna().sum())
        sample = df[col].dropna().head(1).tolist()
        sample_str = str(sample[0]) if sample else ""
        if len(sample_str) > 60:
            sample_str = sample_str[:57] + "..."
        sample_str = sample_str.replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {i} | `{col}` | {dtype} | {nulls} | {sample_str} |")
    return lines


def main() -> None:
    out: list[str] = []
    out.append("# Quelldaten-Exploration — Game Hype Index\n")
    out.append("Automatisch generiert von `scripts/explore_sources.py`.\n")

    # ---- STEAM (CSV) ----
    out.append("## 1. Steam Games Dataset (`games.csv`)\n")
    out.append(f"- Dateigroesse: **{file_size_mb(STEAM_CSV):.1f} MB**")
    steam_rows = count_lines(STEAM_CSV)
    out.append(f"- Datensaetze: **{steam_rows:,}**")
    out.append(f"- Es existiert zusaetzlich `games.json` ({file_size_mb(RAW / 'games.json'):.0f} MB) — selber Inhalt als verschachteltes JSON, ideal fuer mongoimport.\n")
    steam, steam_enc = read_csv_robust(
        STEAM_CSV, low_memory=False, header=0, names=STEAM_COLUMNS,
    )
    out.append(f"- Encoding: `{steam_enc}`")
    out.append("- **Hinweis Datenqualitaet:** Der mitgelieferte CSV-Header hat 39 Spalten, die Daten 40 — `DiscountDLC count` wurde im Header nicht durch Komma getrennt. Beim Laden ueberschreibe ich die Spaltennamen mit 40 korrekten Namen.\n")
    out.append("**Sample (erste Zeile):**\n")
    out.append("```")
    sample_row = steam.iloc[0].to_dict()
    for k, v in list(sample_row.items())[:10]:
        vs = str(v)
        if len(vs) > 80:
            vs = vs[:77] + "..."
        out.append(f"{k}: {vs}")
    out.append("... (weitere Spalten ausgelassen)")
    out.append("```\n")
    out.extend(profile_dataframe(steam, "steam"))
    out.append("")

    # ---- METACRITIC ----
    out.append("## 2. Metacritic Top Video Games (`all_games.csv`)\n")
    out.append(f"- Dateigroesse: **{file_size_mb(METACRITIC_CSV):.1f} MB**")
    meta_rows = count_lines(METACRITIC_CSV)
    out.append(f"- Datensaetze: **{meta_rows:,}**\n")
    meta, meta_enc = read_csv_robust(METACRITIC_CSV)
    meta.columns = [c.strip() for c in meta.columns]
    out.append(f"- Encoding: `{meta_enc}`\n")
    out.extend(profile_dataframe(meta, "meta"))
    out.append("")
    out.append("**Plattform-Verteilung (Top 10):**\n")
    out.append("```")
    for p, c in meta["platform"].astype(str).str.strip().value_counts().head(10).items():
        out.append(f"  {p}: {c}")
    out.append("```\n")

    # ---- TWITCH GAME ----
    out.append("## 3. Twitch Game Data (`Twitch_game_data.csv`)\n")
    out.append(f"- Dateigroesse: **{file_size_mb(TWITCH_GAMES_CSV):.2f} MB**")
    tw_rows = count_lines(TWITCH_GAMES_CSV)
    out.append(f"- Datensaetze: **{tw_rows:,}** (monatliche Eintraege)\n")
    twitch, twitch_enc = read_csv_robust(TWITCH_GAMES_CSV)
    out.append(f"- Encoding: `{twitch_enc}`\n")
    out.extend(profile_dataframe(twitch, "twitch"))
    out.append("")
    out.append(f"**Zeitraum:** {int(twitch['Year'].min())}-{int(twitch['Month'].min()):02d} bis {int(twitch['Year'].max())}-{int(twitch['Month'].max()):02d}")
    out.append(f"**Anzahl distinkte Spiele in Twitch-Top:** {twitch['Game'].nunique():,}\n")

    # ---- TWITCH GLOBAL ----
    out.append("## 4. Twitch Global Data (`Twitch_global_data.csv`)\n")
    out.append(f"- Dateigroesse: **{file_size_mb(TWITCH_GLOBAL_CSV):.2f} MB**")
    twg_rows = count_lines(TWITCH_GLOBAL_CSV)
    out.append(f"- Datensaetze: **{twg_rows:,}** (Plattform-Monatsaggregate)")
    out.append("- Nutzen: Normalisierung — Anteil eines Spiels an der gesamten Twitch-Aufmerksamkeit pro Monat.\n")
    twg, twg_enc = read_csv_robust(TWITCH_GLOBAL_CSV)
    out.append(f"- Encoding: `{twg_enc}`\n")
    out.extend(profile_dataframe(twg, "twitch_global"))
    out.append("")

    # ---- JOIN-ANALYSE ----
    out.append("## 5. Join-Analyse / Integrierbarkeit\n")
    out.append("Schluessel: normalisierter Titel (`lower`, Sonderzeichen entfernt). Steam fungiert als Hub.\n")

    steam_titles = set(steam["Name"].dropna().map(normalize_title))
    steam_titles.discard("")
    twitch_titles = set(twitch["Game"].dropna().map(normalize_title))
    twitch_titles.discard("")
    meta_titles = set(meta["name"].dropna().map(normalize_title))
    meta_titles.discard("")

    s_t = steam_titles & twitch_titles
    s_m = steam_titles & meta_titles
    all_three = steam_titles & twitch_titles & meta_titles

    out.append("| Schnittmenge | Anzahl distinkter Titel |")
    out.append("|---|---|")
    out.append(f"| Steam (distinkte Titel) | {len(steam_titles):,} |")
    out.append(f"| Twitch (distinkte Titel) | {len(twitch_titles):,} |")
    out.append(f"| Metacritic (distinkte Titel, inkl. Konsolen) | {len(meta_titles):,} |")
    out.append(f"| **Steam ∩ Twitch** | **{len(s_t):,}** ({len(s_t) / max(len(twitch_titles), 1) * 100:.1f}% der Twitch-Titel) |")
    out.append(f"| **Steam ∩ Metacritic** | **{len(s_m):,}** ({len(s_m) / max(len(meta_titles), 1) * 100:.1f}% der Metacritic-Titel) |")
    out.append(f"| **Steam ∩ Twitch ∩ Metacritic** | **{len(all_three):,}** (Kern-Universum fuer Analyse) |")
    out.append("")

    out.append("**Beispiel-Matches in allen drei Quellen (Top 15 alphabetisch):**\n")
    out.append("```")
    for t in sorted(all_three)[:15]:
        out.append(f"  {t}")
    out.append("```\n")

    # ---- SCHLUSSFOLGERUNG ----
    out.append("## 6. Erkenntnisse fuer das Datenmodell\n")
    out.append("- **Steam** liefert Stammdaten (AppID, Preis, Genres, Owners-Range, Tags, Plattform-Flags) — eindeutiger Primaerschluessel `AppID`.")
    out.append("- **Twitch** liefert Zeitreihe pro Spiel + Monat — natuerlicher zusammengesetzter Schluessel (Game, Year, Month).")
    out.append("- **Metacritic** liefert qualitative Bewertung pro (Name, Plattform) — Multiplattform-Eintraege, fuer PC-Join Plattform=PC filtern.")
    out.append("- **Twitch Global** ist Platform-Aggregat (Year, Month) → ideal als Referenz-Tabelle fuer Normalisierung.")
    out.append("- Steam enthaelt bereits einen `Metacritic score`, aber nur einen einzigen Wert pro AppID. Die externe Metacritic-Quelle bringt Mehrwert: User-Review-Score + Summary-Text + Konsolen-Eintraege fuer historischen Kontext.")
    out.append("- Join-Strategie: Titel normalisieren, fuer 1:n-Matches (gleicher Titel mehrfach in Metacritic ueber Plattformen) entweder Plattform=PC waehlen oder Max-Score je Titel aggregieren.")
    out.append("")

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(out), encoding="utf-8")
    print(f"Report geschrieben: {REPORT}")
    print(f"Steam rows: {steam_rows:,}, Metacritic rows: {meta_rows:,}, Twitch rows: {tw_rows:,}")
    print(f"Triple-Join Universum: {len(all_three):,} Spiele")


if __name__ == "__main__":
    main()
