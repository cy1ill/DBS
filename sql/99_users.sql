-- =============================================================================
-- DBS-Projekt — MySQL-User anlegen
-- =============================================================================
-- VOR Ausfuehrung:
--   1. Die beiden Passwoerter unten durch eigene starke Passwoerter ersetzen
--      (mind. 16 Zeichen, Mix aus Buchstaben/Zahlen/Sonderzeichen).
--   2. Als root ausfuehren:
--      mysql -h localhost -u root -p < sql/99_users.sql
--
-- Erzeugt:
--   * dbs_admin  — voller Zugriff auf game_hype_index, ueber Netzwerk erreichbar
--   * grader     — read-only fuer den Dozenten (Bewertung)
-- =============================================================================

-- Admin-User
CREATE USER IF NOT EXISTS 'dbs_admin'@'%' IDENTIFIED BY 'CHANGE_ME_admin_pwd_!2026';
GRANT ALL PRIVILEGES ON game_hype_index.* TO 'dbs_admin'@'%';

-- Grading-User (read-only)
CREATE USER IF NOT EXISTS 'grader'@'%' IDENTIFIED BY 'CHANGE_ME_grader_pwd_!2026';
GRANT SELECT, SHOW VIEW ON game_hype_index.* TO 'grader'@'%';

FLUSH PRIVILEGES;

-- Verifikation
SELECT User, Host FROM mysql.user WHERE User IN ('dbs_admin', 'grader');
SHOW GRANTS FOR 'dbs_admin'@'%';
SHOW GRANTS FOR 'grader'@'%';
