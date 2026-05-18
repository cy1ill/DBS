// =============================================================================
// DBS-Projekt "Game Hype Index" — MongoDB ELT-Transformation
// =============================================================================
// Voraussetzungen (vor dem Lauf):
//   1. scripts/mongo_preprocess.py wurde ausgefuehrt
//      → data/processed/{games,twitch_month,twitch_global,metacritic}.jsonl
//   2. mongo/03_mongoimport.sh hat die JSONL in Staging-Collections geladen:
//      stg_games, stg_twitch_month, stg_twitch_global, stg_metacritic
//   3. mongo/01_create_collections.js hat die Ziel-Collections
//      'games' und 'twitch_global' mit JSON-Schema-Validatoren erstellt.
//
// Dieses Script fuehrt zwei Aggregation Pipelines aus:
//   A) stg_twitch_global  →  twitch_global         (direkter $merge, 1:1)
//   B) stg_games  + $lookup(stg_twitch_month, stg_metacritic) → games
//      (denormalisiertes Game-Dokument mit eingebetteter Twitch-Zeitreihe
//      und Metacritic-Eintraegen)
//
// Ausfuehrung:
//   mongosh "<URI>/game_hype_index" --file 02_transform.js
// =============================================================================

use("game_hype_index");

// -----------------------------------------------------------------------------
// (0) Hilfs-Indexe auf Staging-Collections fuer schnelle $lookup-Joins
//     (auf der "foreignField"-Seite — hier name_normalized)
// -----------------------------------------------------------------------------
print(">>> [0] Lookup-Indexe auf Staging...");
db.stg_twitch_month.createIndex({ name_normalized: 1 });
db.stg_metacritic.createIndex({ name_normalized: 1 });

// -----------------------------------------------------------------------------
// A) Twitch Global  (105 Docs, direkter Transfer)
// -----------------------------------------------------------------------------
print(">>> [A] Twitch Global → twitch_global");
db.stg_twitch_global.aggregate([
    { $merge: {
        into: "twitch_global",
        on: "_id",
        whenMatched: "replace",
        whenNotMatched: "insert"
    } }
]);
print("    twitch_global Docs: " + db.twitch_global.countDocuments());

// -----------------------------------------------------------------------------
// B) Games (denormalisiert, mit eingebetteter Twitch- und Metacritic-Historie)
// -----------------------------------------------------------------------------
print(">>> [B] Steam + Twitch + Metacritic → games");

db.stg_games.aggregate([

    // -------------------------------------------------------------------------
    // (1) Owners-String parsen ("100000 - 200000" → {min, max})
    //     + Discount-String → Int
    //     + Tags (dict) → Array von Tag-Namen
    // -------------------------------------------------------------------------
    { $addFields: {
        _owners_parts: {
            $cond: {
                if: { $and: [
                    { $ne: ["$estimated_owners", null] },
                    { $ne: ["$estimated_owners", ""] }
                ] },
                then: { $split: ["$estimated_owners", " - "] },
                else: ["0", "0"]
            }
        },
        _discount_int: {
            $convert: { input: "$discount", to: "int", onError: 0, onNull: 0 }
        },
        _tags_array: {
            $cond: {
                if: { $eq: [{ $type: "$tags" }, "object"] },
                then: { $map: {
                    input: { $objectToArray: "$tags" },
                    as: "kv",
                    in: "$$kv.k"
                } },
                else: { $ifNull: ["$tags", []] }
            }
        }
    } },

    // -------------------------------------------------------------------------
    // (2) Twitch-Zeitreihe aus stg_twitch_month einbetten (gejoint per
    //     normalisiertem Titel). Sortiert nach Jahr/Monat.
    // -------------------------------------------------------------------------
    { $lookup: {
        from: "stg_twitch_month",
        let: { gnorm: "$name_normalized" },
        pipeline: [
            { $match: { $expr: { $eq: ["$name_normalized", "$$gnorm"] } } },
            { $project: {
                _id: 0,
                name_normalized: 0,
                game: 0
            } },
            { $sort: { year: 1, month: 1 } }
        ],
        as: "twitch_timeline"
    } },

    // -------------------------------------------------------------------------
    // (3) Metacritic-Eintraege einbetten (1 pro Plattform).
    // -------------------------------------------------------------------------
    { $lookup: {
        from: "stg_metacritic",
        let: { gnorm: "$name_normalized" },
        pipeline: [
            { $match: { $expr: { $eq: ["$name_normalized", "$$gnorm"] } } },
            { $project: {
                _id: 0,
                name_normalized: 0,
                name: 0
            } }
        ],
        as: "metacritic"
    } },

    // -------------------------------------------------------------------------
    // (4) Finales Ziel-Schema bauen (entspricht mongo/sample_game_document.json)
    // -------------------------------------------------------------------------
    { $project: {
        _id: 1,
        name: 1,
        name_normalized: 1,
        release_date: { $ifNull: ["$release_date", null] },
        required_age: { $ifNull: ["$required_age", 0] },
        price_usd:    { $convert: { input: "$price",    to: "double", onError: 0.0, onNull: 0.0 } },
        discount_pct: "$_discount_int",
        dlc_count:    { $ifNull: ["$dlc_count", 0] },
        about: {
            $cond: [{ $eq: ["$about_the_game", ""] }, null, { $ifNull: ["$about_the_game", null] }]
        },
        header_image_url: {
            $cond: [{ $eq: ["$header_image", ""] }, null, { $ifNull: ["$header_image", null] }]
        },
        owners: {
            min: { $convert: { input: { $arrayElemAt: ["$_owners_parts", 0] }, to: "long", onError: null, onNull: null } },
            max: { $convert: { input: { $arrayElemAt: ["$_owners_parts", 1] }, to: "long", onError: null, onNull: null } }
        },
        peak_ccu: { $ifNull: ["$peak_ccu", 0] },
        platforms: {
            windows: { $eq: ["$windows", true] },
            mac:     { $eq: ["$mac",     true] },
            linux:   { $eq: ["$linux",   true] }
        },
        steam_scores: {
            // 0 ist Sentinel fuer 'nicht bewertet' → null
            meta_score: { $cond: [{ $gt: ["$metacritic_score", 0] }, "$metacritic_score", null] },
            user_score: { $cond: [{ $gt: ["$user_score",       0] }, "$user_score",       null] },
            positive_reviews: { $ifNull: ["$positive", 0] },
            negative_reviews: { $ifNull: ["$negative", 0] }
        },
        playtime_min: {
            avg_forever:    { $ifNull: ["$average_playtime_forever",    0] },
            median_forever: { $ifNull: ["$median_playtime_forever",     0] }
        },
        achievements:    { $ifNull: ["$achievements",    0] },
        recommendations: { $ifNull: ["$recommendations", 0] },
        developers: { $ifNull: ["$developers", []] },
        publishers: { $ifNull: ["$publishers", []] },
        genres:     { $ifNull: ["$genres",     []] },
        categories: { $ifNull: ["$categories", []] },
        tags:       "$_tags_array",
        languages: {
            supported:  { $ifNull: ["$supported_languages",  []] },
            full_audio: { $ifNull: ["$full_audio_languages", []] }
        },
        metacritic: {
            $map: {
                input: "$metacritic",
                as: "m",
                in: {
                    platform:     { $trim: { input: { $ifNull: ["$$m.platform", ""] } } },
                    meta_score:   "$$m.meta_score",
                    user_review:  "$$m.user_review",
                    summary:      "$$m.summary",
                    release_date: "$$m.release_date"
                }
            }
        },
        twitch_timeline: 1
    } },

    // -------------------------------------------------------------------------
    // (5) In Ziel-Collection schreiben (preserves Validator + Indexes)
    // -------------------------------------------------------------------------
    { $merge: {
        into: "games",
        on: "_id",
        whenMatched: "replace",
        whenNotMatched: "insert"
    } }

], { allowDiskUse: true });

print("    games Docs:           " + db.games.countDocuments());
print("    games mit Twitch:     " + db.games.countDocuments({ "twitch_timeline.0": { $exists: true } }));
print("    games mit Metacritic: " + db.games.countDocuments({ "metacritic.0":      { $exists: true } }));

// -----------------------------------------------------------------------------
// Optional: Staging-Collections nach erfolgreicher Transformation entfernen
// (auskommentiert, damit Re-Runs nicht erneut mongoimport brauchen)
// -----------------------------------------------------------------------------
// db.stg_games.drop();
// db.stg_twitch_month.drop();
// db.stg_twitch_global.drop();
// db.stg_metacritic.drop();

print(">>> Transformation abgeschlossen.");
