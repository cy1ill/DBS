-- =============================================================================
-- DBS-Projekt "Game Hype Index" — MySQL-Zielschema (3. Normalform)
-- =============================================================================
-- Quellen integriert:
--   * Steam Games Dataset      → game + Dimensionen (developer, publisher, ...)
--   * Twitch Game Data         → twitch_month (Faktentabelle Zeitreihe)
--   * Twitch Global Data       → twitch_global_month (Plattform-Aggregat)
--   * Metacritic Top Games     → metacritic_entry (pro Plattform)
--
-- Konventionen:
--   * Engine InnoDB (Transaktionen, FK), utf8mb4 (multi-script Titel: ja, viele!)
--   * snake_case fuer Tabellen und Spalten
--   * Surrogat-IDs (INT UNSIGNED AUTO_INCREMENT) fuer alle Dimensionen mit
--     natuerlichem String-Schluessel; natuerliche IDs (AppID, year/month) wo
--     sinnvoll
--   * Foreign Keys mit ON DELETE RESTRICT (Daten sind unveraenderlich nach Load)
--   * Spaltengroessen sind auf reale Max-Werte der Quelldaten abgestimmt
--     (siehe reports/source_exploration.md)
-- =============================================================================

DROP DATABASE IF EXISTS game_hype_index;
CREATE DATABASE game_hype_index
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;
USE game_hype_index;

-- -----------------------------------------------------------------------------
-- DIMENSIONEN (Stammdaten, ohne FK-Abhaengigkeit)
-- -----------------------------------------------------------------------------

CREATE TABLE developer (
    developer_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    developer_name VARCHAR(255) NOT NULL,
    PRIMARY KEY (developer_id),
    UNIQUE KEY uk_developer_name (developer_name)
) ENGINE=InnoDB
  COMMENT='Spielentwickler-Studios (1 Eintrag pro distinktem Namen aus Steam).';

CREATE TABLE publisher (
    publisher_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    publisher_name VARCHAR(255) NOT NULL,
    PRIMARY KEY (publisher_id),
    UNIQUE KEY uk_publisher_name (publisher_name)
) ENGINE=InnoDB
  COMMENT='Publisher (Vertrieb), aus Steam-Spalte "Publishers".';

CREATE TABLE genre (
    genre_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    genre_name VARCHAR(100) NOT NULL,
    PRIMARY KEY (genre_id),
    UNIQUE KEY uk_genre_name (genre_name)
) ENGINE=InnoDB
  COMMENT='Steam-Hauptgenres ("Action", "RPG", ...).';

CREATE TABLE category (
    category_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    category_name VARCHAR(100) NOT NULL,
    PRIMARY KEY (category_id),
    UNIQUE KEY uk_category_name (category_name)
) ENGINE=InnoDB
  COMMENT='Steam-Features ("Single-player", "VR Support", "Co-op", ...).';

CREATE TABLE tag (
    tag_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    tag_name VARCHAR(100) NOT NULL,
    PRIMARY KEY (tag_id),
    UNIQUE KEY uk_tag_name (tag_name)
) ENGINE=InnoDB
  COMMENT='Community-Tags von Steam (10-20 pro Spiel typisch).';

CREATE TABLE language (
    language_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    language_name VARCHAR(100) NOT NULL,
    PRIMARY KEY (language_id),
    UNIQUE KEY uk_language_name (language_name)
) ENGINE=InnoDB
  COMMENT='Sprachen (z.B. English, German, Japanese).';

CREATE TABLE platform (
    platform_name VARCHAR(20) NOT NULL,
    PRIMARY KEY (platform_name)
) ENGINE=InnoDB
  COMMENT='Betriebssystem-Plattformen Windows/Mac/Linux (statisch 3 Eintraege).';

-- Twitch Global wird vor twitch_month angelegt, weil twitch_month
-- per FK darauf verweist (Normalisierungs-Referenz pro Jahr/Monat).
CREATE TABLE twitch_global_month (
    year                SMALLINT UNSIGNED NOT NULL,
    month               TINYINT UNSIGNED NOT NULL,
    total_hours_watched BIGINT UNSIGNED NOT NULL,
    total_avg_viewers   INT UNSIGNED NOT NULL,
    total_peak_viewers  INT UNSIGNED NOT NULL,
    total_streams       BIGINT UNSIGNED NOT NULL,
    total_avg_channels  INT UNSIGNED NOT NULL,
    games_streamed      INT UNSIGNED NOT NULL,
    viewer_ratio        DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (year, month),
    CHECK (month BETWEEN 1 AND 12)
) ENGINE=InnoDB
  COMMENT='Plattform-Aggregate Twitch pro Monat (~105 Zeilen 2016-2024).';

-- -----------------------------------------------------------------------------
-- HAUPT-ENTITAET: GAME
-- -----------------------------------------------------------------------------

CREATE TABLE game (
    app_id                       INT UNSIGNED NOT NULL,
    name                         VARCHAR(500) NOT NULL,
    name_normalized              VARCHAR(500) NOT NULL,
    release_date                 DATE NULL,
    required_age                 TINYINT UNSIGNED NOT NULL DEFAULT 0,
    price_usd                    DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    discount_pct                 TINYINT UNSIGNED NOT NULL DEFAULT 0,
    dlc_count                    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    about                        TEXT NULL,
    header_image_url             VARCHAR(500) NULL,
    owners_min                   BIGINT UNSIGNED NULL,
    owners_max                   BIGINT UNSIGNED NULL,
    peak_ccu                     INT UNSIGNED NOT NULL DEFAULT 0,
    steam_meta_score             TINYINT UNSIGNED NULL,
    steam_user_score             TINYINT UNSIGNED NULL,
    steam_positive_reviews       INT UNSIGNED NOT NULL DEFAULT 0,
    steam_negative_reviews       INT UNSIGNED NOT NULL DEFAULT 0,
    achievements                 SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    recommendations              INT UNSIGNED NOT NULL DEFAULT 0,
    avg_playtime_forever_min     INT UNSIGNED NOT NULL DEFAULT 0,
    median_playtime_forever_min  INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (app_id),
    KEY idx_game_name_normalized (name_normalized),
    KEY idx_game_release_date    (release_date),
    CHECK (discount_pct     <= 100),
    CHECK (steam_meta_score IS NULL OR steam_meta_score <= 100),
    CHECK (steam_user_score IS NULL OR steam_user_score <= 100),
    CHECK (owners_min       IS NULL OR owners_max IS NULL OR owners_min <= owners_max)
) ENGINE=InnoDB
  COMMENT='Spiele-Stammdaten aus Steam; AppID ist eindeutiger Primaerschluessel.';

-- -----------------------------------------------------------------------------
-- JUNCTIONS (M:N Beziehungen)
-- -----------------------------------------------------------------------------

CREATE TABLE game_developer (
    app_id       INT UNSIGNED NOT NULL,
    developer_id INT UNSIGNED NOT NULL,
    PRIMARY KEY (app_id, developer_id),
    KEY idx_gd_developer (developer_id),
    CONSTRAINT fk_gd_game      FOREIGN KEY (app_id)       REFERENCES game(app_id)            ON DELETE RESTRICT,
    CONSTRAINT fk_gd_developer FOREIGN KEY (developer_id) REFERENCES developer(developer_id) ON DELETE RESTRICT
) ENGINE=InnoDB
  COMMENT='M:N Spiel <-> Entwickler (Co-Developer moeglich).';

CREATE TABLE game_publisher (
    app_id       INT UNSIGNED NOT NULL,
    publisher_id INT UNSIGNED NOT NULL,
    PRIMARY KEY (app_id, publisher_id),
    KEY idx_gp_publisher (publisher_id),
    CONSTRAINT fk_gp_game      FOREIGN KEY (app_id)       REFERENCES game(app_id)            ON DELETE RESTRICT,
    CONSTRAINT fk_gp_publisher FOREIGN KEY (publisher_id) REFERENCES publisher(publisher_id) ON DELETE RESTRICT
) ENGINE=InnoDB
  COMMENT='M:N Spiel <-> Publisher.';

CREATE TABLE game_genre (
    app_id   INT UNSIGNED NOT NULL,
    genre_id INT UNSIGNED NOT NULL,
    PRIMARY KEY (app_id, genre_id),
    KEY idx_gg_genre (genre_id),
    CONSTRAINT fk_gg_game  FOREIGN KEY (app_id)   REFERENCES game(app_id)    ON DELETE RESTRICT,
    CONSTRAINT fk_gg_genre FOREIGN KEY (genre_id) REFERENCES genre(genre_id) ON DELETE RESTRICT
) ENGINE=InnoDB
  COMMENT='M:N Spiel <-> Genre (mehrere Genres pro Spiel moeglich).';

CREATE TABLE game_category (
    app_id      INT UNSIGNED NOT NULL,
    category_id INT UNSIGNED NOT NULL,
    PRIMARY KEY (app_id, category_id),
    KEY idx_gc_category (category_id),
    CONSTRAINT fk_gc_game     FOREIGN KEY (app_id)      REFERENCES game(app_id)          ON DELETE RESTRICT,
    CONSTRAINT fk_gc_category FOREIGN KEY (category_id) REFERENCES category(category_id) ON DELETE RESTRICT
) ENGINE=InnoDB
  COMMENT='M:N Spiel <-> Steam-Feature.';

CREATE TABLE game_tag (
    app_id INT UNSIGNED NOT NULL,
    tag_id INT UNSIGNED NOT NULL,
    PRIMARY KEY (app_id, tag_id),
    KEY idx_gt_tag (tag_id),
    CONSTRAINT fk_gt_game FOREIGN KEY (app_id) REFERENCES game(app_id) ON DELETE RESTRICT,
    CONSTRAINT fk_gt_tag  FOREIGN KEY (tag_id) REFERENCES tag(tag_id)  ON DELETE RESTRICT
) ENGINE=InnoDB
  COMMENT='M:N Spiel <-> Community-Tag.';

CREATE TABLE game_platform (
    app_id        INT UNSIGNED NOT NULL,
    platform_name VARCHAR(20) NOT NULL,
    PRIMARY KEY (app_id, platform_name),
    KEY idx_gpl_platform (platform_name),
    CONSTRAINT fk_gpl_game     FOREIGN KEY (app_id)        REFERENCES game(app_id)              ON DELETE RESTRICT,
    CONSTRAINT fk_gpl_platform FOREIGN KEY (platform_name) REFERENCES platform(platform_name)   ON DELETE RESTRICT
) ENGINE=InnoDB
  COMMENT='M:N Spiel <-> OS (Win/Mac/Linux).';

CREATE TABLE game_language (
    app_id      INT UNSIGNED NOT NULL,
    language_id INT UNSIGNED NOT NULL,
    role        ENUM('supported','full_audio') NOT NULL,
    PRIMARY KEY (app_id, language_id, role),
    KEY idx_gl_language (language_id),
    CONSTRAINT fk_gl_game     FOREIGN KEY (app_id)      REFERENCES game(app_id)         ON DELETE RESTRICT,
    CONSTRAINT fk_gl_language FOREIGN KEY (language_id) REFERENCES language(language_id) ON DELETE RESTRICT
) ENGINE=InnoDB
  COMMENT='M:N Spiel <-> Sprache mit Rolle (Untertitel oder Full-Audio).';

-- -----------------------------------------------------------------------------
-- 1:N BEZIEHUNGEN
-- -----------------------------------------------------------------------------

CREATE TABLE metacritic_entry (
    app_id          INT UNSIGNED NOT NULL,
    platform        VARCHAR(40)  NOT NULL,
    meta_score      TINYINT UNSIGNED NULL,
    user_review     DECIMAL(3,1) NULL,
    summary         TEXT NULL,
    mc_release_date DATE NULL,
    PRIMARY KEY (app_id, platform),
    KEY idx_me_platform (platform),
    CONSTRAINT fk_me_game FOREIGN KEY (app_id) REFERENCES game(app_id) ON DELETE RESTRICT,
    CHECK (meta_score  IS NULL OR meta_score  <= 100),
    CHECK (user_review IS NULL OR (user_review >= 0 AND user_review <= 10))
) ENGINE=InnoDB
  COMMENT='Metacritic-Bewertung pro Spiel pro Plattform (1:N zu game).';

CREATE TABLE twitch_month (
    app_id            INT UNSIGNED NOT NULL,
    year              SMALLINT UNSIGNED NOT NULL,
    month             TINYINT UNSIGNED NOT NULL,
    rank_in_month     SMALLINT UNSIGNED NOT NULL,
    hours_watched     BIGINT UNSIGNED NOT NULL,
    hours_streamed    BIGINT UNSIGNED NOT NULL,
    peak_viewers      INT UNSIGNED NOT NULL,
    peak_channels     INT UNSIGNED NOT NULL,
    streamers         INT UNSIGNED NOT NULL,
    avg_viewers       INT UNSIGNED NOT NULL,
    avg_channels      INT UNSIGNED NOT NULL,
    avg_viewer_ratio  DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (app_id, year, month),
    KEY idx_tm_year_month (year, month),
    CONSTRAINT fk_tm_game   FOREIGN KEY (app_id)       REFERENCES game(app_id)                          ON DELETE RESTRICT,
    CONSTRAINT fk_tm_global FOREIGN KEY (year, month)  REFERENCES twitch_global_month(year, month)      ON DELETE RESTRICT,
    CHECK (month BETWEEN 1 AND 12)
) ENGINE=InnoDB
  COMMENT='Twitch-Kennzahlen pro Spiel pro Monat (Zeitreihen-Faktentabelle).';

-- -----------------------------------------------------------------------------
-- STAMMDATEN-SEED: Plattformen
-- -----------------------------------------------------------------------------

INSERT INTO platform (platform_name) VALUES
    ('Windows'), ('Mac'), ('Linux');

-- -----------------------------------------------------------------------------
-- Schema-Uebersicht / Doku-Query
-- -----------------------------------------------------------------------------

-- SELECT TABLE_NAME, TABLE_COMMENT
--   FROM information_schema.TABLES
--  WHERE TABLE_SCHEMA = 'game_hype_index'
--  ORDER BY TABLE_NAME;
