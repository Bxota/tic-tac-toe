package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

const (
	accessTokenTTL  = 15 * time.Minute
	refreshTokenTTL = 30 * 24 * time.Hour
	wsTicketTTL     = 30 * time.Second
)

var (
	errNoUser = errors.New("user not found")
)

func openDB(path string) (*sql.DB, error) {
	if path == "" {
		return nil, errors.New("DB_PATH is empty")
	}
	if path != ":memory:" {
		dir := filepath.Dir(path)
		if dir != "." {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				return nil, fmt.Errorf("create db dir: %w", err)
			}
		}
	}
	conn, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	if err := applyPragmas(conn); err != nil {
		_ = conn.Close()
		return nil, err
	}
	if err := migrateDB(conn); err != nil {
		_ = conn.Close()
		return nil, err
	}
	return conn, nil
}

func applyPragmas(db *sql.DB) error {
	statements := []string{
		"PRAGMA journal_mode=WAL;",
		"PRAGMA foreign_keys=ON;",
		"PRAGMA busy_timeout=5000;",
	}
	for _, stmt := range statements {
		if _, err := db.Exec(stmt); err != nil {
			return fmt.Errorf("pragma failed: %w", err)
		}
	}
	return nil
}

func migrateDB(db *sql.DB) error {
	migrations := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			discord_id TEXT UNIQUE,
			guest_id TEXT UNIQUE,
			username TEXT NOT NULL,
			avatar TEXT,
			is_guest INTEGER NOT NULL DEFAULT 1,
			created_at INTEGER NOT NULL
		);`,
		`CREATE TABLE IF NOT EXISTS sessions (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id INTEGER NOT NULL,
			access_token_hash TEXT NOT NULL,
			access_expires_at INTEGER NOT NULL,
			refresh_token_hash TEXT NOT NULL,
			refresh_expires_at INTEGER NOT NULL,
			created_at INTEGER NOT NULL,
			FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
		);`,
		`CREATE TABLE IF NOT EXISTS ws_tickets (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id INTEGER NOT NULL,
			ticket_hash TEXT NOT NULL,
			expires_at INTEGER NOT NULL,
			used INTEGER NOT NULL DEFAULT 0,
			created_at INTEGER NOT NULL,
			FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
		);`,
		`CREATE TABLE IF NOT EXISTS games (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			room_code TEXT NOT NULL,
			started_at INTEGER NOT NULL,
			ended_at INTEGER NOT NULL,
			winner_symbol TEXT,
			is_draw INTEGER NOT NULL DEFAULT 0,
			player_x_user_id INTEGER,
			player_o_user_id INTEGER,
			player_x_name TEXT,
			player_o_name TEXT,
			FOREIGN KEY(player_x_user_id) REFERENCES users(id),
			FOREIGN KEY(player_o_user_id) REFERENCES users(id)
		);`,
		"CREATE INDEX IF NOT EXISTS idx_sessions_access ON sessions(access_token_hash);",
		"CREATE INDEX IF NOT EXISTS idx_sessions_refresh ON sessions(refresh_token_hash);",
		"CREATE INDEX IF NOT EXISTS idx_ws_ticket_hash ON ws_tickets(ticket_hash);",
		"CREATE INDEX IF NOT EXISTS idx_games_player_x ON games(player_x_user_id);",
		"CREATE INDEX IF NOT EXISTS idx_games_player_o ON games(player_o_user_id);",
	}
	for _, stmt := range migrations {
		if _, err := db.Exec(stmt); err != nil {
			return fmt.Errorf("migration failed: %w", err)
		}
	}
	return nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func normalizeGuestID(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	if len(trimmed) > 64 {
		return ""
	}
	for _, r := range trimmed {
		if !(r == '-' || r == '_' || r == ':' || r >= '0' && r <= '9' || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z') {
			return ""
		}
	}
	return trimmed
}

func nowUnix() int64 {
	return time.Now().UTC().Unix()
}

func boolToInt(value bool) int {
	if value {
		return 1
	}
	return 0
}
