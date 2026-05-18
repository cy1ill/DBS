-- =============================================================================
-- DBS-Projekt "Game Hype Index" — MySQL Staging-Schema (ELT Layer 1)
-- =============================================================================
-- Vier Staging-Tabellen, die die rohen Quelldateien 1:1 abbilden.
-- Datentypen sind bewusst tolerant gewaehlt (VARCHAR/TEXT fuer alle
-- nicht-eindeutig-numerischen Felder), damit LOAD DATA INFILE ohne
-- Type-Coercion gelingt. Die Transformation (Parsing, Casting, Exploding,
-- Joining) erfolgt anschliessend in sql/04_transform.sql per INSERT ... SELECT.
-- =============================================================================

USE game_hype_index;

DROP TABLE IF EXISTS stg_steam;
DROP TABLE IF EXISTS stg_twitch_month;
DROP TABLE IF EXISTS stg_twitch_global;
DROP TABLE IF EXISTS stg_metacritic;

-- -----------------------------------------------------------------------------
-- Steam (40 Spalten — Header ist fehlerhaft, wir ueberschreiben beim LOAD)
-- -----------------------------------------------------------------------------
CREATE TABLE stg_steam (
    app_id                       VARCHAR(20),
    name                         VARCHAR(500),
    release_date                 VARCHAR(40),
    estimated_owners             VARCHAR(40),
    peak_ccu                     VARCHAR(20),
    required_age                 VARCHAR(10),
    price                        VARCHAR(20),
    discount                     VARCHAR(10),
    dlc_count                    VARCHAR(10),
    about_the_game               TEXT,
    supported_languages          TEXT,
    full_audio_languages         TEXT,
    reviews                      TEXT,
    header_image                 VARCHAR(600),
    website                      VARCHAR(600),
    support_url                  VARCHAR(600),
    support_email                VARCHAR(255),
    windows                      VARCHAR(10),
    mac                          VARCHAR(10),
    linux                        VARCHAR(10),
    metacritic_score             VARCHAR(10),
    metacritic_url               VARCHAR(600),
    user_score                   VARCHAR(10),
    positive                     VARCHAR(20),
    negative                     VARCHAR(20),
    score_rank                   VARCHAR(20),
    achievements                 VARCHAR(20),
    recommendations              VARCHAR(20),
    notes                        TEXT,
    avg_playtime_forever         VARCHAR(20),
    avg_playtime_two_weeks       VARCHAR(20),
    median_playtime_forever      VARCHAR(20),
    median_playtime_two_weeks    VARCHAR(20),
    developers                   TEXT,
    publishers                   TEXT,
    categories                   TEXT,
    genres                       TEXT,
    tags                         TEXT,
    screenshots                  TEXT,
    movies                       TEXT,
    KEY idx_stg_steam_app (app_id)
) ENGINE=InnoDB
  COMMENT='Roh-Staging fuer Steam Games Dataset (games.csv, 122k Zeilen).';

-- -----------------------------------------------------------------------------
-- Twitch per Spiel pro Monat
-- -----------------------------------------------------------------------------
CREATE TABLE stg_twitch_month (
    rank_in_month   VARCHAR(10),
    game            VARCHAR(255),
    month           VARCHAR(10),
    year            VARCHAR(10),
    hours_watched   VARCHAR(20),
    hours_streamed  VARCHAR(20),
    peak_viewers    VARCHAR(20),
    peak_channels   VARCHAR(20),
    streamers       VARCHAR(20),
    avg_viewers     VARCHAR(20),
    avg_channels    VARCHAR(20),
    avg_viewer_ratio VARCHAR(20),
    KEY idx_stg_twitch_game (game)
) ENGINE=InnoDB
  COMMENT='Roh-Staging fuer Twitch monatliche Game-Statistik (21k Zeilen).';

-- -----------------------------------------------------------------------------
-- Twitch Plattform-Total pro Monat
-- -----------------------------------------------------------------------------
CREATE TABLE stg_twitch_global (
    year            VARCHAR(10),
    month           VARCHAR(10),
    hours_watched   VARCHAR(20),
    avg_viewers     VARCHAR(20),
    peak_viewers    VARCHAR(20),
    streams         VARCHAR(20),
    avg_channels    VARCHAR(20),
    games_streamed  VARCHAR(20),
    viewer_ratio    VARCHAR(20)
) ENGINE=InnoDB
  COMMENT='Roh-Staging fuer Twitch Plattform-Aggregate (105 Zeilen).';

-- -----------------------------------------------------------------------------
-- Metacritic
-- -----------------------------------------------------------------------------
CREATE TABLE stg_metacritic (
    name            VARCHAR(255),
    platform        VARCHAR(40),
    release_date    VARCHAR(40),
    summary         TEXT,
    meta_score      VARCHAR(10),
    user_review     VARCHAR(20),  -- enthaelt 'tbd' fuer noch nicht bewertet
    KEY idx_stg_meta_name (name)
) ENGINE=InnoDB
  COMMENT='Roh-Staging fuer Metacritic-Scores (18.8k Zeilen, multi-platform).';
