# Quelldaten-Exploration — Game Hype Index

Automatisch generiert von `scripts/explore_sources.py`.

## 1. Steam Games Dataset (`games.csv`)

- Dateigroesse: **371.1 MB**
- Datensaetze: **122,611**
- Es existiert zusaetzlich `games.json` (767 MB) — selber Inhalt als verschachteltes JSON, ideal fuer mongoimport.

- Encoding: `utf-8`
- **Hinweis Datenqualitaet:** Der mitgelieferte CSV-Header hat 39 Spalten, die Daten 40 — `DiscountDLC count` wurde im Header nicht durch Komma getrennt. Beim Laden ueberschreibe ich die Spaltennamen mit 40 korrekten Namen.

**Sample (erste Zeile):**

```
AppID: 2539430
Name: Black Dragon Mage Playtest
Release date: Aug 1, 2023
Estimated owners: 0 - 0
Peak CCU: 0
Required age: 0
Price: 0.0
Discount: 0
DLC count: 0
About the game: nan
... (weitere Spalten ausgelassen)
```

### Spalten (40)

| # | Spalte | Dtype | Nulls | Beispiel |
|---|---|---|---|---|
| 1 | `AppID` | int64 | 0 | 2539430 |
| 2 | `Name` | str | 1 | Black Dragon Mage Playtest |
| 3 | `Release date` | str | 0 | Aug 1, 2023 |
| 4 | `Estimated owners` | str | 0 | 0 - 0 |
| 5 | `Peak CCU` | int64 | 0 | 0 |
| 6 | `Required age` | int64 | 0 | 0 |
| 7 | `Price` | float64 | 0 | 0.0 |
| 8 | `Discount` | int64 | 0 | 0 |
| 9 | `DLC count` | int64 | 0 | 0 |
| 10 | `About the game` | str | 8449 | Springtime, April: when the cherry trees come into full b... |
| 11 | `Supported languages` | str | 0 | [] |
| 12 | `Full audio languages` | str | 0 | [] |
| 13 | `Reviews` | str | 110541 | “And this is the very reason why I believe Fantasy Genera... |
| 14 | `Header image` | str | 81 | https://shared.akamai.steamstatic.com/store_item_assets/s... |
| 15 | `Website` | str | 72935 | http://mangagamer.org/supipara |
| 16 | `Support url` | str | 68469 | http://mangagamer.com |
| 17 | `Support email` | str | 22263 | support@mangagamer.com |
| 18 | `Windows` | bool | 0 | True |
| 19 | `Mac` | bool | 0 | False |
| 20 | `Linux` | bool | 0 | False |
| 21 | `Metacritic score` | int64 | 0 | 0 |
| 22 | `Metacritic url` | str | 118355 | https://www.metacritic.com/game/pc/fantasy-general-ii?fta... |
| 23 | `User score` | int64 | 0 | 0 |
| 24 | `Positive` | int64 | 0 | 0 |
| 25 | `Negative` | int64 | 0 | 0 |
| 26 | `Score rank` | float64 | 122571 | 99.0 |
| 27 | `Achievements` | int64 | 0 | 0 |
| 28 | `Recommendations` | int64 | 0 | 0 |
| 29 | `Notes` | str | 100153 | The game includes the following elements. 1. General Matu... |
| 30 | `Average playtime forever` | int64 | 0 | 0 |
| 31 | `Average playtime two weeks` | int64 | 0 | 0 |
| 32 | `Median playtime forever` | int64 | 0 | 0 |
| 33 | `Median playtime two weeks` | int64 | 0 | 0 |
| 34 | `Developers` | str | 8437 | minori |
| 35 | `Publishers` | str | 8909 | MangaGamer |
| 36 | `Categories` | str | 8953 | Single-player,Steam Trading Cards,Steam Cloud,Family Sharing |
| 37 | `Genres` | str | 8413 | Adventure |
| 38 | `Tags` | str | 39265 | Adventure,Visual Novel,Anime,Cute |
| 39 | `Screenshots` | str | 6018 | https://shared.akamai.steamstatic.com/store_item_assets/s... |
| 40 | `Movies` | float64 | 122611 |  |

## 2. Metacritic Top Video Games (`all_games.csv`)

- Dateigroesse: **11.5 MB**
- Datensaetze: **18,800**

- Encoding: `utf-8`

### Spalten (6)

| # | Spalte | Dtype | Nulls | Beispiel |
|---|---|---|---|---|
| 1 | `name` | str | 0 | The Legend of Zelda: Ocarina of Time |
| 2 | `platform` | str | 0 |  Nintendo 64 |
| 3 | `release_date` | str | 0 | November 23, 1998 |
| 4 | `summary` | str | 114 | As a young boy, Link is tricked by Ganondorf, the King of... |
| 5 | `meta_score` | int64 | 0 | 99 |
| 6 | `user_review` | str | 0 | 9.1 |

**Plattform-Verteilung (Top 10):**

```
  PC: 4864
  PlayStation 4: 2056
  Xbox 360: 1644
  PlayStation 2: 1414
  Switch: 1399
  PlayStation 3: 1256
  Xbox One: 1179
  Xbox: 789
  DS: 720
  Wii: 655
```

## 3. Twitch Game Data (`Twitch_game_data.csv`)

- Dateigroesse: **1.56 MB**
- Datensaetze: **21,000** (monatliche Eintraege)

- Encoding: `cp1252`

### Spalten (12)

| # | Spalte | Dtype | Nulls | Beispiel |
|---|---|---|---|---|
| 1 | `Rank` | int64 | 0 | 1 |
| 2 | `Game` | str | 1 | League of Legends |
| 3 | `Month` | int64 | 0 | 1 |
| 4 | `Year` | int64 | 0 | 2016 |
| 5 | `Hours_watched` | int64 | 0 | 94377226 |
| 6 | `Hours_streamed` | int64 | 0 | 1362044 |
| 7 | `Peak_viewers` | int64 | 0 | 530270 |
| 8 | `Peak_channels` | int64 | 0 | 2903 |
| 9 | `Streamers` | int64 | 0 | 129172 |
| 10 | `Avg_viewers` | int64 | 0 | 127021 |
| 11 | `Avg_channels` | int64 | 0 | 1833 |
| 12 | `Avg_viewer_ratio` | float64 | 0 | 69.29 |

**Zeitraum:** 2016-01 bis 2024-12
**Anzahl distinkte Spiele in Twitch-Top:** 2,359

## 4. Twitch Global Data (`Twitch_global_data.csv`)

- Dateigroesse: **0.01 MB**
- Datensaetze: **105** (Plattform-Monatsaggregate)
- Nutzen: Normalisierung — Anteil eines Spiels an der gesamten Twitch-Aufmerksamkeit pro Monat.

- Encoding: `utf-8`

### Spalten (9)

| # | Spalte | Dtype | Nulls | Beispiel |
|---|---|---|---|---|
| 1 | `year` | int64 | 0 | 2016 |
| 2 | `Month` | int64 | 0 | 1 |
| 3 | `Hours_watched` | int64 | 0 | 480241904 |
| 4 | `Avg_viewers` | int64 | 0 | 646355 |
| 5 | `Peak_viewers` | int64 | 0 | 1275257 |
| 6 | `Streams` | int64 | 0 | 7701675 |
| 7 | `Avg_channels` | int64 | 0 | 20076 |
| 8 | `Games_streamed` | int64 | 0 | 12149 |
| 9 | `Viewer_ratio` | float64 | 0 | 29.08 |

## 5. Join-Analyse / Integrierbarkeit

Schluessel: normalisierter Titel (`lower`, Sonderzeichen entfernt). Steam fungiert als Hub.

| Schnittmenge | Anzahl distinkter Titel |
|---|---|
| Steam (distinkte Titel) | 118,229 |
| Twitch (distinkte Titel) | 2,331 |
| Metacritic (distinkte Titel, inkl. Konsolen) | 12,178 |
| **Steam ∩ Twitch** | **1,392** (59.7% der Twitch-Titel) |
| **Steam ∩ Metacritic** | **4,086** (33.6% der Metacritic-Titel) |
| **Steam ∩ Twitch ∩ Metacritic** | **693** (Kern-Universum fuer Analyse) |

**Beispiel-Matches in allen drei Quellen (Top 15 alphabetisch):**

```
  60 parsecs
  7 days to die
  a hat in time
  a plague tale innocence
  a total war saga troy
  a way out
  absolver
  ace combat 7 skies unknown
  age of empires definitive edition
  age of empires ii definitive edition
  age of wonders planetfall
  agents of mayhem
  agony
  ai the somnium files
  albion online
```

## 6. Erkenntnisse fuer das Datenmodell

- **Steam** liefert Stammdaten (AppID, Preis, Genres, Owners-Range, Tags, Plattform-Flags) — eindeutiger Primaerschluessel `AppID`.
- **Twitch** liefert Zeitreihe pro Spiel + Monat — natuerlicher zusammengesetzter Schluessel (Game, Year, Month).
- **Metacritic** liefert qualitative Bewertung pro (Name, Plattform) — Multiplattform-Eintraege, fuer PC-Join Plattform=PC filtern.
- **Twitch Global** ist Platform-Aggregat (Year, Month) → ideal als Referenz-Tabelle fuer Normalisierung.
- Steam enthaelt bereits einen `Metacritic score`, aber nur einen einzigen Wert pro AppID. Die externe Metacritic-Quelle bringt Mehrwert: User-Review-Score + Summary-Text + Konsolen-Eintraege fuer historischen Kontext.
- Join-Strategie: Titel normalisieren, fuer 1:n-Matches (gleicher Titel mehrfach in Metacritic ueber Plattformen) entweder Plattform=PC waehlen oder Max-Score je Titel aggregieren.
