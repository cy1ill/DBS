// =============================================================================
// DBS-Projekt — MongoDB-User anlegen
// =============================================================================
// VOR Ausfuehrung:
//   1. Beide Passwoerter unten durch eigene starke ersetzen.
//   2. mongosh "mongodb://localhost:27017" --file mongo/99_users.js
//   3. ERST DANACH in mongod.cfg Authentication aktivieren:
//        security:
//          authorization: enabled
//      Dann: Restart-Service MongoDB
//
// Erzeugt:
//   * dbs_admin  — root-Rolle auf admin-DB
//   * grader     — read-only auf game_hype_index (fuer Bewertung)
// =============================================================================

use("admin");

db.createUser({
    user: "dbs_admin",
    pwd:  "CHANGE_ME_admin_pwd_!2026",
    roles: [
        { role: "root", db: "admin" }
    ]
});

db.createUser({
    user: "grader",
    pwd:  "CHANGE_ME_grader_pwd_!2026",
    roles: [
        { role: "read", db: "game_hype_index" }
    ]
});

// Verifikation
db.getUsers().forEach(u => printjson({ user: u.user, roles: u.roles }));
