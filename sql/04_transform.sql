-- =============================================================================
-- DBS-Projekt "Game Hype Index" — MySQL ELT-Transformation (Layer 3)
-- =============================================================================
-- Befuellt das 3NF-Zielschema (game, developer, ..., twitch_month, ...) aus
-- den Staging-Tabellen via INSERT ... SELECT. Reihenfolge:
--   1. Hilfs-Sequenz (helper_numbers) fuer das Aufspalten von CSV-Strings
--   2. Game (Hub) — mit Parsing von Datum, Owners-Range, etc.
--   3. Dimensionen + Junctions (Developer, Publisher, Genre, Category, Tag)
--      → INSERT IGNORE INTO dim, dann INSERT IGNORE INTO junction
--   4. Sprachen (Sonderfall: Python-Listen-String + Rolle supported/full_audio)
--   5. Plattformen (aus Boolean-Spalten Windows/Mac/Linux)
--   6. Twitch Global (1:1)
--   7. Twitch monatlich (JOIN ueber normalisiertem Titel)
--   8. Metacritic (JOIN ueber normalisiertem Titel, pro Plattform ein Eintrag)
--   9. Sanity-Counts
--
-- Pattern fuer das Aufspalten von komma-separierten Strings:
--   SUBSTRING_INDEX(SUBSTRING_INDEX(s.list, ',', n), ',', -1)  → n-tes Element
--   helper_numbers liefert die Sequenz 1..100, gejoint per Komma-Zahl im String.
-- =============================================================================

USE game_hype_index;

-- Idempotenz: Zielschema zuruecksetzen (Reihenfolge: Junctions/Facts vor Stamm)
SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE twitch_month;
TRUNCATE TABLE twitch_global_month;
TRUNCATE TABLE metacritic_entry;
TRUNCATE TABLE game_developer;
TRUNCATE TABLE game_publisher;
TRUNCATE TABLE game_genre;
TRUNCATE TABLE game_category;
TRUNCATE TABLE game_tag;
TRUNCATE TABLE game_platform;
TRUNCATE TABLE game_language;
TRUNCATE TABLE game;
TRUNCATE TABLE developer;
TRUNCATE TABLE publisher;
TRUNCATE TABLE genre;
TRUNCATE TABLE category;
TRUNCATE TABLE tag;
TRUNCATE TABLE language;
-- platform behaelt den Seed (Windows/Mac/Linux)

SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
-- 1. Hilfs-Sequenz 1..100 fuer String-Splitting
-- -----------------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS helper_numbers;
CREATE TEMPORARY TABLE helper_numbers (n INT NOT NULL PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO helper_numbers (n)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM seq WHERE n < 100)
SELECT n FROM seq;

-- -----------------------------------------------------------------------------
-- 2. Game (Hub) — Stammdaten mit Parsing
-- -----------------------------------------------------------------------------
INSERT INTO game (
    app_id, name, name_normalized, release_date, required_age,
    price_usd, discount_pct, dlc_count, about, header_image_url,
    owners_min, owners_max, peak_ccu,
    steam_meta_score, steam_user_score,
    steam_positive_reviews, steam_negative_reviews,
    achievements, recommendations,
    avg_playtime_forever_min, median_playtime_forever_min
)
SELECT
    CAST(app_id AS UNSIGNED) AS app_id,
    name,
    TRIM(REGEXP_REPLACE(LOWER(name), '[^a-z0-9]+', ' ')) AS name_normalized,
    -- Datum parsen, NULL bei Misslingen ("Coming soon", "2023" etc.)
    COALESCE(
        STR_TO_DATE(release_date, '%b %e, %Y'),
        STR_TO_DATE(release_date, '%e %b, %Y'),
        STR_TO_DATE(release_date, '%M %e, %Y')
    ) AS release_date,
    CAST(NULLIF(required_age, '') AS UNSIGNED) AS required_age,
    CAST(NULLIF(price, '') AS DECIMAL(8,2)) AS price_usd,
    CAST(NULLIF(discount, '') AS UNSIGNED) AS discount_pct,
    CAST(NULLIF(dlc_count, '') AS UNSIGNED) AS dlc_count,
    NULLIF(about_the_game, '') AS about,
    NULLIF(header_image, '') AS header_image_url,
    -- "Estimated owners" = "100000 - 200000"  → min/max
    CAST(NULLIF(TRIM(SUBSTRING_INDEX(estimated_owners, ' - ',  1)), '') AS UNSIGNED) AS owners_min,
    CAST(NULLIF(TRIM(SUBSTRING_INDEX(estimated_owners, ' - ', -1)), '') AS UNSIGNED) AS owners_max,
    CAST(NULLIF(peak_ccu, '') AS UNSIGNED) AS peak_ccu,
    -- Score-Spalten: gueltig ist 1-100; 0 = "nicht bewertet" → NULL,
    -- Werte > 100 sind Daten-Noise (kommt in Steam vereinzelt vor) → ebenfalls NULL.
    -- Damit bleibt der CHECK (<=100) erfuellt und TINYINT laeuft nicht ueber.
    CASE WHEN CAST(NULLIF(metacritic_score, '') AS UNSIGNED) BETWEEN 1 AND 100
         THEN CAST(metacritic_score AS UNSIGNED) ELSE NULL END AS steam_meta_score,
    CASE WHEN CAST(NULLIF(user_score, '')        AS UNSIGNED) BETWEEN 1 AND 100
         THEN CAST(user_score        AS UNSIGNED) ELSE NULL END AS steam_user_score,
    CAST(NULLIF(positive,        '') AS UNSIGNED) AS steam_positive_reviews,
    CAST(NULLIF(negative,        '') AS UNSIGNED) AS steam_negative_reviews,
    CAST(NULLIF(achievements,    '') AS UNSIGNED) AS achievements,
    CAST(NULLIF(recommendations, '') AS UNSIGNED) AS recommendations,
    CAST(NULLIF(avg_playtime_forever,    '') AS UNSIGNED) AS avg_playtime_forever_min,
    CAST(NULLIF(median_playtime_forever, '') AS UNSIGNED) AS median_playtime_forever_min
FROM stg_steam
WHERE app_id REGEXP '^[0-9]+$';  -- Sicherheit gegen kaputte Zeilen

-- -----------------------------------------------------------------------------
-- 3a. Developer + game_developer
-- -----------------------------------------------------------------------------
INSERT IGNORE INTO developer (developer_name)
SELECT DISTINCT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.developers, ',', n.n), ',', -1)) AS dev_name
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.developers) - LENGTH(REPLACE(s.developers, ',', ''))
WHERE s.developers IS NOT NULL AND s.developers <> ''
HAVING dev_name <> '';

INSERT IGNORE INTO game_developer (app_id, developer_id)
SELECT CAST(s.app_id AS UNSIGNED), d.developer_id
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.developers) - LENGTH(REPLACE(s.developers, ',', ''))
JOIN developer d
  ON d.developer_name = TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.developers, ',', n.n), ',', -1))
WHERE s.developers IS NOT NULL AND s.developers <> '';

-- -----------------------------------------------------------------------------
-- 3b. Publisher + game_publisher
-- -----------------------------------------------------------------------------
INSERT IGNORE INTO publisher (publisher_name)
SELECT DISTINCT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.publishers, ',', n.n), ',', -1)) AS pub_name
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.publishers) - LENGTH(REPLACE(s.publishers, ',', ''))
WHERE s.publishers IS NOT NULL AND s.publishers <> ''
HAVING pub_name <> '';

INSERT IGNORE INTO game_publisher (app_id, publisher_id)
SELECT CAST(s.app_id AS UNSIGNED), p.publisher_id
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.publishers) - LENGTH(REPLACE(s.publishers, ',', ''))
JOIN publisher p
  ON p.publisher_name = TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.publishers, ',', n.n), ',', -1))
WHERE s.publishers IS NOT NULL AND s.publishers <> '';

-- -----------------------------------------------------------------------------
-- 3c. Genre + game_genre
-- -----------------------------------------------------------------------------
INSERT IGNORE INTO genre (genre_name)
SELECT DISTINCT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.genres, ',', n.n), ',', -1)) AS g_name
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.genres) - LENGTH(REPLACE(s.genres, ',', ''))
WHERE s.genres IS NOT NULL AND s.genres <> ''
HAVING g_name <> '';

INSERT IGNORE INTO game_genre (app_id, genre_id)
SELECT CAST(s.app_id AS UNSIGNED), g.genre_id
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.genres) - LENGTH(REPLACE(s.genres, ',', ''))
JOIN genre g
  ON g.genre_name = TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.genres, ',', n.n), ',', -1))
WHERE s.genres IS NOT NULL AND s.genres <> '';

-- -----------------------------------------------------------------------------
-- 3d. Category + game_category
-- -----------------------------------------------------------------------------
INSERT IGNORE INTO category (category_name)
SELECT DISTINCT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.categories, ',', n.n), ',', -1)) AS c_name
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.categories) - LENGTH(REPLACE(s.categories, ',', ''))
WHERE s.categories IS NOT NULL AND s.categories <> ''
HAVING c_name <> '';

INSERT IGNORE INTO game_category (app_id, category_id)
SELECT CAST(s.app_id AS UNSIGNED), c.category_id
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.categories) - LENGTH(REPLACE(s.categories, ',', ''))
JOIN category c
  ON c.category_name = TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.categories, ',', n.n), ',', -1))
WHERE s.categories IS NOT NULL AND s.categories <> '';

-- -----------------------------------------------------------------------------
-- 3e. Tag + game_tag
-- -----------------------------------------------------------------------------
INSERT IGNORE INTO tag (tag_name)
SELECT DISTINCT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.tags, ',', n.n), ',', -1)) AS t_name
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.tags) - LENGTH(REPLACE(s.tags, ',', ''))
WHERE s.tags IS NOT NULL AND s.tags <> ''
HAVING t_name <> '';

INSERT IGNORE INTO game_tag (app_id, tag_id)
SELECT CAST(s.app_id AS UNSIGNED), t.tag_id
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.tags) - LENGTH(REPLACE(s.tags, ',', ''))
JOIN tag t
  ON t.tag_name = TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(s.tags, ',', n.n), ',', -1))
WHERE s.tags IS NOT NULL AND s.tags <> '';

-- -----------------------------------------------------------------------------
-- 4. Sprachen (Sonderfall: Python-Listen-String "['English','German']")
-- -----------------------------------------------------------------------------
-- Helper-Expression: aus dem Python-Listen-String einen sauberen CSV-String machen
--   ['English', 'German']  → English,German
-- Anschliessend wieder ueber SUBSTRING_INDEX splitten.

-- 4a. Distinkte Sprachen ueber beide Spalten (supported + full_audio)
INSERT IGNORE INTO language (language_name)
SELECT DISTINCT lang FROM (
    SELECT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(
               REPLACE(REPLACE(REPLACE(REPLACE(s.supported_languages, '[', ''), ']', ''), '''', ''), '"', ''),
               ',', n.n), ',', -1)) AS lang
    FROM stg_steam s
    JOIN helper_numbers n
      ON n.n <= 1 + LENGTH(s.supported_languages) - LENGTH(REPLACE(s.supported_languages, ',', ''))
    WHERE s.supported_languages IS NOT NULL
      AND s.supported_languages NOT IN ('', '[]')
    UNION
    SELECT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(
               REPLACE(REPLACE(REPLACE(REPLACE(s.full_audio_languages, '[', ''), ']', ''), '''', ''), '"', ''),
               ',', n.n), ',', -1)) AS lang
    FROM stg_steam s
    JOIN helper_numbers n
      ON n.n <= 1 + LENGTH(s.full_audio_languages) - LENGTH(REPLACE(s.full_audio_languages, ',', ''))
    WHERE s.full_audio_languages IS NOT NULL
      AND s.full_audio_languages NOT IN ('', '[]')
) langs
WHERE lang <> '';

-- 4b. game_language mit role='supported'
INSERT IGNORE INTO game_language (app_id, language_id, role)
SELECT CAST(s.app_id AS UNSIGNED), l.language_id, 'supported'
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.supported_languages) - LENGTH(REPLACE(s.supported_languages, ',', ''))
JOIN language l
  ON l.language_name = TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(
       REPLACE(REPLACE(REPLACE(REPLACE(s.supported_languages, '[', ''), ']', ''), '''', ''), '"', ''),
       ',', n.n), ',', -1))
WHERE s.supported_languages IS NOT NULL
  AND s.supported_languages NOT IN ('', '[]');

-- 4c. game_language mit role='full_audio'
INSERT IGNORE INTO game_language (app_id, language_id, role)
SELECT CAST(s.app_id AS UNSIGNED), l.language_id, 'full_audio'
FROM stg_steam s
JOIN helper_numbers n
  ON n.n <= 1 + LENGTH(s.full_audio_languages) - LENGTH(REPLACE(s.full_audio_languages, ',', ''))
JOIN language l
  ON l.language_name = TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(
       REPLACE(REPLACE(REPLACE(REPLACE(s.full_audio_languages, '[', ''), ']', ''), '''', ''), '"', ''),
       ',', n.n), ',', -1))
WHERE s.full_audio_languages IS NOT NULL
  AND s.full_audio_languages NOT IN ('', '[]');

-- -----------------------------------------------------------------------------
-- 5. Plattform-Junctions aus Boolean-Spalten
-- -----------------------------------------------------------------------------
INSERT IGNORE INTO game_platform (app_id, platform_name)
SELECT CAST(app_id AS UNSIGNED), 'Windows' FROM stg_steam WHERE windows = 'True'
UNION ALL
SELECT CAST(app_id AS UNSIGNED), 'Mac'     FROM stg_steam WHERE mac     = 'True'
UNION ALL
SELECT CAST(app_id AS UNSIGNED), 'Linux'   FROM stg_steam WHERE linux   = 'True';

-- -----------------------------------------------------------------------------
-- 6. Twitch Global Monatswerte (1:1, nur Casts)
-- -----------------------------------------------------------------------------
INSERT INTO twitch_global_month (
    year, month, total_hours_watched, total_avg_viewers, total_peak_viewers,
    total_streams, total_avg_channels, games_streamed, viewer_ratio
)
SELECT
    CAST(year  AS UNSIGNED),
    CAST(month AS UNSIGNED),
    CAST(hours_watched  AS UNSIGNED),
    CAST(avg_viewers    AS UNSIGNED),
    CAST(peak_viewers   AS UNSIGNED),
    CAST(streams        AS UNSIGNED),
    CAST(avg_channels   AS UNSIGNED),
    CAST(games_streamed AS UNSIGNED),
    CAST(viewer_ratio   AS DECIMAL(10,2))
FROM stg_twitch_global
WHERE year REGEXP '^[0-9]+$' AND month REGEXP '^[0-9]+$';

-- -----------------------------------------------------------------------------
-- 7. Twitch monatlich pro Spiel — JOIN ueber normalisierten Titel
-- -----------------------------------------------------------------------------
-- Nur Spiele aufnehmen, die als Steam-Spiel existieren UND deren globaler
-- Monatswert existiert (FK auf twitch_global_month).
INSERT IGNORE INTO twitch_month (
    app_id, year, month, rank_in_month,
    hours_watched, hours_streamed, peak_viewers, peak_channels,
    streamers, avg_viewers, avg_channels, avg_viewer_ratio
)
SELECT
    g.app_id,
    CAST(t.year  AS UNSIGNED),
    CAST(t.month AS UNSIGNED),
    CAST(t.rank_in_month AS UNSIGNED),
    CAST(t.hours_watched  AS UNSIGNED),
    CAST(t.hours_streamed AS UNSIGNED),
    CAST(t.peak_viewers   AS UNSIGNED),
    CAST(t.peak_channels  AS UNSIGNED),
    CAST(t.streamers      AS UNSIGNED),
    CAST(t.avg_viewers    AS UNSIGNED),
    CAST(t.avg_channels   AS UNSIGNED),
    CAST(t.avg_viewer_ratio AS DECIMAL(10,2))
FROM stg_twitch_month t
JOIN game g
  ON g.name_normalized = TRIM(REGEXP_REPLACE(LOWER(t.game), '[^a-z0-9]+', ' '))
JOIN twitch_global_month tg
  ON tg.year = CAST(t.year AS UNSIGNED) AND tg.month = CAST(t.month AS UNSIGNED);

-- -----------------------------------------------------------------------------
-- 8. Metacritic Entries — JOIN ueber normalisierten Titel (1:n per Plattform)
-- -----------------------------------------------------------------------------
INSERT IGNORE INTO metacritic_entry (
    app_id, platform, meta_score, user_review, summary, mc_release_date
)
SELECT
    g.app_id,
    TRIM(m.platform),
    CAST(NULLIF(m.meta_score, '') AS UNSIGNED),
    CASE WHEN m.user_review IN ('tbd', '') OR m.user_review IS NULL
         THEN NULL
         ELSE CAST(m.user_review AS DECIMAL(3,1))
    END,
    NULLIF(m.summary, ''),
    STR_TO_DATE(m.release_date, '%M %e, %Y')
FROM stg_metacritic m
JOIN game g
  ON g.name_normalized = TRIM(REGEXP_REPLACE(LOWER(m.name), '[^a-z0-9]+', ' '));

-- -----------------------------------------------------------------------------
-- 9. Statistiken aktualisieren + Sanity-Counts
-- -----------------------------------------------------------------------------
ANALYZE TABLE game, developer, publisher, genre, category, tag, language,
              game_developer, game_publisher, game_genre, game_category,
              game_tag, game_platform, game_language,
              metacritic_entry, twitch_month, twitch_global_month;

SELECT 'game'             AS tbl, COUNT(*) AS n FROM game
UNION ALL SELECT 'developer',       COUNT(*) FROM developer
UNION ALL SELECT 'publisher',       COUNT(*) FROM publisher
UNION ALL SELECT 'genre',           COUNT(*) FROM genre
UNION ALL SELECT 'category',        COUNT(*) FROM category
UNION ALL SELECT 'tag',             COUNT(*) FROM tag
UNION ALL SELECT 'language',        COUNT(*) FROM language
UNION ALL SELECT 'game_developer',  COUNT(*) FROM game_developer
UNION ALL SELECT 'game_publisher',  COUNT(*) FROM game_publisher
UNION ALL SELECT 'game_genre',      COUNT(*) FROM game_genre
UNION ALL SELECT 'game_category',   COUNT(*) FROM game_category
UNION ALL SELECT 'game_tag',        COUNT(*) FROM game_tag
UNION ALL SELECT 'game_platform',   COUNT(*) FROM game_platform
UNION ALL SELECT 'game_language',   COUNT(*) FROM game_language
UNION ALL SELECT 'metacritic_entry',COUNT(*) FROM metacritic_entry
UNION ALL SELECT 'twitch_global_month', COUNT(*) FROM twitch_global_month
UNION ALL SELECT 'twitch_month',    COUNT(*) FROM twitch_month;
