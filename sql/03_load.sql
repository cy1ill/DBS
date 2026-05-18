-- =============================================================================
-- DBS-Projekt "Game Hype Index" — MySQL LOAD DATA INFILE (ELT Layer 2)
-- =============================================================================
-- Laedt die vier Roh-Dateien in die Staging-Tabellen.
--
-- Hinweise:
--  * Pfade enthalten den Platzhalter {{DATA_DIR}}. Wird vom Orchestrator-Script
--    (scripts/run_elt_mysql.sh) via sed durch den tatsaechlichen Pfad ersetzt.
--  * --local-infile=1 muss client-seitig AKTIV sein, server-seitig
--    local_infile=ON gesetzt (siehe scripts/run_elt_mysql.sh).
--  * Steam-CSV-Header hat 39 statt 40 Spalten (siehe Reports). Wir IGNOREn
--    1 LINE und geben explizit alle 40 Spaltennamen an.
--  * Twitch-CSV ist cp1252 codiert -- in MySQL nennt sich das 'latin1'
--    (MySQL-Doku: "latin1 is the cp1252 West European character set, not the
--    ISO-8859-1 character set"). Konvertierung auf utf8mb4 erfolgt automatisch.
--  * Alle Tabellen werden vorher TRUNCATEd fuer idempotente Reruns.
-- =============================================================================

USE game_hype_index;

TRUNCATE TABLE stg_steam;
TRUNCATE TABLE stg_twitch_month;
TRUNCATE TABLE stg_twitch_global;
TRUNCATE TABLE stg_metacritic;

-- -----------------------------------------------------------------------------
-- 1. Steam Games Dataset (122'611 Zeilen)
-- -----------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '{{DATA_DIR}}/games.csv'
INTO TABLE stg_steam
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '\\'
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES
    (app_id, name, release_date, estimated_owners, peak_ccu,
     required_age, price, discount, dlc_count, about_the_game,
     supported_languages, full_audio_languages, reviews, header_image,
     website, support_url, support_email, windows, mac, linux,
     metacritic_score, metacritic_url, user_score, positive, negative,
     score_rank, achievements, recommendations, notes,
     avg_playtime_forever, avg_playtime_two_weeks,
     median_playtime_forever, median_playtime_two_weeks,
     developers, publishers, categories, genres, tags,
     screenshots, movies);

-- -----------------------------------------------------------------------------
-- 2. Twitch monatliche Game-Statistik (21'000 Zeilen)
-- -----------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '{{DATA_DIR}}/Twitch_game_data.csv'
INTO TABLE stg_twitch_month
    CHARACTER SET latin1
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES
    (rank_in_month, game, month, year, hours_watched, hours_streamed,
     peak_viewers, peak_channels, streamers, avg_viewers, avg_channels,
     avg_viewer_ratio);

-- -----------------------------------------------------------------------------
-- 3. Twitch Global (105 Zeilen)
-- -----------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '{{DATA_DIR}}/Twitch_global_data.csv'
INTO TABLE stg_twitch_global
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES
    (year, month, hours_watched, avg_viewers, peak_viewers, streams,
     avg_channels, games_streamed, viewer_ratio);

-- -----------------------------------------------------------------------------
-- 4. Metacritic (18'800 Zeilen)
-- -----------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '{{DATA_DIR}}/all_games.csv'
INTO TABLE stg_metacritic
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES
    (name, platform, release_date, summary, meta_score, user_review);

-- -----------------------------------------------------------------------------
-- Sanity-Check (wird vom Orchestrator geloggt)
-- -----------------------------------------------------------------------------
SELECT 'stg_steam'         AS table_name, COUNT(*) AS rows_loaded FROM stg_steam
UNION ALL SELECT 'stg_twitch_month',  COUNT(*) FROM stg_twitch_month
UNION ALL SELECT 'stg_twitch_global', COUNT(*) FROM stg_twitch_global
UNION ALL SELECT 'stg_metacritic',    COUNT(*) FROM stg_metacritic;
