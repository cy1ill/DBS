// =============================================================================
// DBS-Projekt "Game Hype Index" — MongoDB Collections + JSON-Schema-Validator
// =============================================================================
// Ausfuehrbar via:
//   mongosh "mongodb://<user>:<pass>@<vm-host>:27017/game_hype_index" \
//     --file 01_create_collections.js
//
// Erzeugt die Datenbank, beide Collections und JSON-Schema-Validatoren analog
// zum MySQL-DDL. Das Schema ist denormalisiert: Spielstammdaten + alle
// abhaengigen Multivalue-Attribute (Genres, Tags, Languages, Metacritic-
// Eintraege, Twitch-Zeitreihe) eingebettet im games-Dokument.
//
// Separat: twitch_global (Plattform-Aggregate, kleine Referenz-Collection),
// per (year, month) zur Normalisierung der Spiel-Anteile.
// =============================================================================

use("game_hype_index");

// Sauberes Re-Setup: Collections droppen, falls vorhanden
db.games.drop();
db.twitch_global.drop();

// -----------------------------------------------------------------------------
// Collection: games
// -----------------------------------------------------------------------------
db.createCollection("games", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: [
                "_id", "name", "name_normalized", "price_usd",
                "platforms", "steam_scores"
            ],
            properties: {
                _id: {
                    bsonType: "int",
                    description: "Steam-AppID, eindeutig"
                },
                name: { bsonType: "string", maxLength: 500 },
                name_normalized: {
                    bsonType: "string",
                    maxLength: 500,
                    description: "Lowercase, sonderzeichen-frei (Join-Key)"
                },
                release_date: {
                    bsonType: ["string", "null"],
                    description: "ISO-Date 'YYYY-MM-DD' oder null"
                },
                required_age: { bsonType: "int", minimum: 0, maximum: 21 },
                price_usd:    { bsonType: "double", minimum: 0 },
                discount_pct: { bsonType: "int", minimum: 0, maximum: 100 },
                dlc_count:    { bsonType: "int", minimum: 0 },
                about:        { bsonType: ["string", "null"] },
                header_image_url: { bsonType: ["string", "null"] },
                owners: {
                    bsonType: "object",
                    properties: {
                        min: { bsonType: ["long", "int", "null"] },
                        max: { bsonType: ["long", "int", "null"] }
                    }
                },
                peak_ccu: { bsonType: "int", minimum: 0 },
                platforms: {
                    bsonType: "object",
                    required: ["windows", "mac", "linux"],
                    properties: {
                        windows: { bsonType: "bool" },
                        mac:     { bsonType: "bool" },
                        linux:   { bsonType: "bool" }
                    }
                },
                steam_scores: {
                    bsonType: "object",
                    properties: {
                        meta_score:       { bsonType: ["int", "null"], minimum: 0, maximum: 100 },
                        user_score:       { bsonType: ["int", "null"], minimum: 0, maximum: 100 },
                        positive_reviews: { bsonType: "int", minimum: 0 },
                        negative_reviews: { bsonType: "int", minimum: 0 }
                    }
                },
                playtime_min: {
                    bsonType: "object",
                    properties: {
                        avg_forever:    { bsonType: "int", minimum: 0 },
                        median_forever: { bsonType: "int", minimum: 0 }
                    }
                },
                achievements:    { bsonType: "int", minimum: 0 },
                recommendations: { bsonType: "int", minimum: 0 },
                developers: { bsonType: "array", items: { bsonType: "string" } },
                publishers: { bsonType: "array", items: { bsonType: "string" } },
                genres:     { bsonType: "array", items: { bsonType: "string" } },
                categories: { bsonType: "array", items: { bsonType: "string" } },
                tags:       { bsonType: "array", items: { bsonType: "string" } },
                languages: {
                    bsonType: "object",
                    properties: {
                        supported:  { bsonType: "array", items: { bsonType: "string" } },
                        full_audio: { bsonType: "array", items: { bsonType: "string" } }
                    }
                },
                metacritic: {
                    bsonType: "array",
                    description: "Pro Plattform ein Eintrag",
                    items: {
                        bsonType: "object",
                        required: ["platform"],
                        properties: {
                            platform:        { bsonType: "string" },
                            meta_score:      { bsonType: ["int", "null"], minimum: 0, maximum: 100 },
                            user_review:     { bsonType: ["double", "null"], minimum: 0, maximum: 10 },
                            summary:         { bsonType: ["string", "null"] },
                            release_date:    { bsonType: ["string", "null"] }
                        }
                    }
                },
                twitch_timeline: {
                    bsonType: "array",
                    description: "Monatliche Streaming-Snapshots",
                    items: {
                        bsonType: "object",
                        required: ["year", "month"],
                        properties: {
                            year:             { bsonType: "int", minimum: 2000, maximum: 2100 },
                            month:            { bsonType: "int", minimum: 1, maximum: 12 },
                            rank:             { bsonType: "int", minimum: 0 },
                            hours_watched:    { bsonType: ["long", "int"], minimum: 0 },
                            hours_streamed:   { bsonType: ["long", "int"], minimum: 0 },
                            peak_viewers:     { bsonType: "int", minimum: 0 },
                            peak_channels:    { bsonType: "int", minimum: 0 },
                            streamers:        { bsonType: "int", minimum: 0 },
                            avg_viewers:      { bsonType: "int", minimum: 0 },
                            avg_channels:     { bsonType: "int", minimum: 0 },
                            avg_viewer_ratio: { bsonType: "double", minimum: 0 }
                        }
                    }
                }
            }
        }
    },
    validationLevel: "moderate",
    validationAction: "warn"
});

// Indexe (Performance kommt im Schritt 5; Basisindex auf name_normalized
// fuer Joins und auf timeline-Felder fuer Aggregationen)
db.games.createIndex({ name_normalized: 1 });
db.games.createIndex({ "twitch_timeline.year": 1, "twitch_timeline.month": 1 });
db.games.createIndex({ genres: 1 });

// -----------------------------------------------------------------------------
// Collection: twitch_global
// -----------------------------------------------------------------------------
db.createCollection("twitch_global", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["_id", "total_hours_watched", "games_streamed"],
            properties: {
                _id: {
                    bsonType: "object",
                    required: ["year", "month"],
                    properties: {
                        year:  { bsonType: "int", minimum: 2000, maximum: 2100 },
                        month: { bsonType: "int", minimum: 1, maximum: 12 }
                    }
                },
                total_hours_watched: { bsonType: ["long", "int"], minimum: 0 },
                total_avg_viewers:   { bsonType: "int", minimum: 0 },
                total_peak_viewers:  { bsonType: "int", minimum: 0 },
                total_streams:       { bsonType: ["long", "int"], minimum: 0 },
                total_avg_channels:  { bsonType: "int", minimum: 0 },
                games_streamed:      { bsonType: "int", minimum: 0 },
                viewer_ratio:        { bsonType: "double", minimum: 0 }
            }
        }
    },
    validationLevel: "strict",
    validationAction: "error"
});

print("✔ Collections 'games' und 'twitch_global' angelegt mit JSON-Schema-Validatoren und Basisindexen.");
