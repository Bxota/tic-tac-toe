package main

import (
	"database/sql"
	"time"
)

type gameRecord struct {
	RoomCode     string
	StartedAt    int64
	EndedAt      int64
	WinnerSymbol string
	IsDraw       bool
	PlayerXID    int64
	PlayerOID    int64
	PlayerXName  string
	PlayerOName  string
}

type historyItem struct {
	ID           int64  `json:"id"`
	RoomCode     string `json:"room_code"`
	StartedAt    int64  `json:"started_at"`
	EndedAt      int64  `json:"ended_at"`
	Result       string `json:"result"`
	WinnerSymbol string `json:"winner_symbol"`
	YourSymbol   string `json:"your_symbol"`
	OpponentName string `json:"opponent_name"`
}

type statsResponse struct {
	Total  int `json:"total"`
	Wins   int `json:"wins"`
	Losses int `json:"losses"`
	Draws  int `json:"draws"`
}

func (s *Server) recordGame(record gameRecord) error {
	_, err := s.db.Exec(
		`INSERT INTO games (room_code, started_at, ended_at, winner_symbol, is_draw, player_x_user_id, player_o_user_id, player_x_name, player_o_name)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		record.RoomCode,
		record.StartedAt,
		record.EndedAt,
		record.WinnerSymbol,
		boolToInt(record.IsDraw),
		nullIfZero(record.PlayerXID),
		nullIfZero(record.PlayerOID),
		record.PlayerXName,
		record.PlayerOName,
	)
	return err
}

func nullIfZero(id int64) any {
	if id == 0 {
		return nil
	}
	return id
}

func (s *Server) loadHistory(userID int64, limit int) ([]historyItem, error) {
	rows, err := s.db.Query(
		`SELECT id, room_code, started_at, ended_at, winner_symbol, is_draw, player_x_user_id, player_o_user_id, player_x_name, player_o_name
		 FROM games
		 WHERE player_x_user_id = ? OR player_o_user_id = ?
		 ORDER BY ended_at DESC
		 LIMIT ?`,
		userID, userID, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []historyItem{}
	for rows.Next() {
		var item historyItem
		var winnerSymbol sql.NullString
		var isDraw int
		var playerXID, playerOID sql.NullInt64
		var playerXName, playerOName sql.NullString
		if err := rows.Scan(&item.ID, &item.RoomCode, &item.StartedAt, &item.EndedAt, &winnerSymbol, &isDraw, &playerXID, &playerOID, &playerXName, &playerOName); err != nil {
			return nil, err
		}
		item.WinnerSymbol = winnerSymbol.String
		if playerXID.Valid && playerXID.Int64 == userID {
			item.YourSymbol = symbolX
			item.OpponentName = playerOName.String
		} else {
			item.YourSymbol = symbolO
			item.OpponentName = playerXName.String
		}
		if isDraw == 1 {
			item.Result = "draw"
		} else if item.WinnerSymbol == item.YourSymbol {
			item.Result = "win"
		} else {
			item.Result = "loss"
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Server) loadStats(userID int64) (statsResponse, error) {
	var stats statsResponse
	row := s.db.QueryRow(
		`SELECT
		 COUNT(*) as total,
		 SUM(CASE WHEN is_draw = 1 THEN 1 ELSE 0 END) as draws,
		 SUM(CASE
			 WHEN winner_symbol = ? AND player_x_user_id = ? THEN 1
			 WHEN winner_symbol = ? AND player_o_user_id = ? THEN 1
			 ELSE 0
		 END) as wins,
		 SUM(CASE
			 WHEN winner_symbol = ? AND player_o_user_id = ? THEN 1
			 WHEN winner_symbol = ? AND player_x_user_id = ? THEN 1
			 ELSE 0
		 END) as losses
		 FROM games
		 WHERE player_x_user_id = ? OR player_o_user_id = ?`,
		symbolX, userID, symbolO, userID, symbolX, userID, symbolO, userID, userID, userID,
	)
	var draws sql.NullInt64
	var wins sql.NullInt64
	var losses sql.NullInt64
	if err := row.Scan(&stats.Total, &draws, &wins, &losses); err != nil {
		return statsResponse{}, err
	}
	stats.Draws = int(nullInt(draws))
	stats.Wins = int(nullInt(wins))
	stats.Losses = int(nullInt(losses))
	return stats, nil
}

func nullInt(value sql.NullInt64) int64 {
	if value.Valid {
		return value.Int64
	}
	return 0
}

func buildGameRecord(room *Room, endedAt time.Time) gameRecord {
	record := gameRecord{
		RoomCode:  room.code,
		StartedAt: room.startedAt.Unix(),
		EndedAt:   endedAt.Unix(),
		IsDraw:    room.draw,
	}
	if room.winner != "" {
		record.WinnerSymbol = room.winner
	}
	if room.playerX != nil {
		record.PlayerXID = room.playerX.userID
		record.PlayerXName = room.playerX.name
	}
	if room.playerO != nil {
		record.PlayerOID = room.playerO.userID
		record.PlayerOName = room.playerO.name
	}
	return record
}
