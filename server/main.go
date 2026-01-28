package main

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	symbolX = "X"
	symbolO = "O"
)

const (
	statusWaiting    = "waiting"
	statusInProgress = "in_progress"
	statusPaused     = "paused"
	statusWin        = "win"
	statusDraw       = "draw"
)

const (
	roomCodeLength = 6
	maxMessageSize = 4 * 1024
	pongWait       = 60 * time.Second
	pingPeriod     = 50 * time.Second
	writeWait      = 10 * time.Second
)

var winPatterns = [][]int{
	{0, 1, 2},
	{3, 4, 5},
	{6, 7, 8},
	{0, 3, 6},
	{1, 4, 7},
	{2, 5, 8},
	{0, 4, 8},
	{2, 4, 6},
}

var allowedOrigins = loadAllowedOrigins()

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return isOriginAllowed(r.Header.Get("Origin"))
	},
}

type incomingMessage struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

type outgoingMessage struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type createRoomPayload struct {
	Name    string `json:"name"`
	GuestID string `json:"guest_id,omitempty"`
}

type joinRoomPayload struct {
	RoomCode  string `json:"room_code"`
	PlayerID  string `json:"player_id,omitempty"`
	Name      string `json:"name,omitempty"`
	Spectator bool   `json:"spectator,omitempty"`
	GuestID   string `json:"guest_id,omitempty"`
}

type movePayload struct {
	RoomCode string `json:"room_code"`
	PlayerID string `json:"player_id"`
	Cell     int    `json:"cell"`
}

type rematchPayload struct {
	RoomCode string `json:"room_code"`
	PlayerID string `json:"player_id"`
}

type errorPayload struct {
	Message string `json:"message"`
}

type roomResponsePayload struct {
	RoomCode    string       `json:"room_code"`
	PlayerID    string       `json:"player_id"`
	Symbol      string       `json:"symbol"`
	Role        string       `json:"role"`
	Reconnected bool         `json:"reconnected"`
	State       statePayload `json:"state"`
}

type playerInfo struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Connected bool   `json:"connected"`
}

type statePayload struct {
	RoomCode string                `json:"room_code"`
	Board    []string              `json:"board"`
	Turn     string                `json:"turn"`
	Status   string                `json:"status"`
	Winner   string                `json:"winner"`
	Players  map[string]playerInfo `json:"players"`
}

type playerLeftPayload struct {
	PlayerID string `json:"player_id"`
}

type roomClosedPayload struct {
	Reason string `json:"reason"`
}

type Player struct {
	id               string
	name             string
	symbol           string
	spectator        bool
	userID           int64
	conn             *websocket.Conn
	connected        bool
	sendMu           sync.Mutex
	disconnectTimer  *time.Timer
	disconnectReason string
}

type Room struct {
	code           string
	board          [9]string
	turn           string
	startingSymbol string
	winner         string
	draw           bool
	startedAt      time.Time
	recorded       bool

	playerX    *Player
	playerO    *Player
	spectators map[string]*Player

	closed bool
	mu     sync.Mutex
}

type Server struct {
	rooms   map[string]*Room
	mu      sync.RWMutex
	db      *sql.DB
	discord discordConfig
}

type Session struct {
	room   *Room
	player *Player
	userID *int64
	mu     sync.RWMutex
}

func main() {
	addr := envOr("ADDR", ":8080")
	webDir := resolveWebDir()
	dbPath := envOr("DB_PATH", "./data/tictactoe.db")

	db, err := openDB(dbPath)
	if err != nil {
		log.Fatalf("db init failed: %v", err)
	}

	discordConfig, err := loadDiscordConfig()
	if err != nil {
		log.Printf("discord oauth disabled: %v", err)
	}

	srv := NewServer(db, discordConfig)
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", srv.handleWS)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/auth/discord/login", srv.handleDiscordLogin)
	mux.HandleFunc("/auth/discord/callback", srv.handleDiscordCallback)
	mux.HandleFunc("/auth/refresh", srv.handleRefresh)
	mux.HandleFunc("/auth/me", srv.handleMe)
	mux.HandleFunc("/auth/logout", srv.handleLogout)
	mux.HandleFunc("/auth/ws-ticket", srv.handleWSTicket)
	mux.HandleFunc("/api/history", srv.handleHistory)
	mux.HandleFunc("/api/stats", srv.handleStats)

	if webDir != "" {
		mux.Handle("/", spaHandler(webDir))
		log.Printf("serving web from %s", webDir)
	} else {
		log.Printf("no web directory found, only websocket available")
	}

	log.Printf("listening on %s", addr)
	handler := withCORS(mux)
	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Fatal(err)
	}
}

func NewServer(db *sql.DB, discord discordConfig) *Server {
	return &Server{rooms: make(map[string]*Room), db: db, discord: discord}
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	var userID *int64
	if ticket := strings.TrimSpace(r.URL.Query().Get("ticket")); ticket != "" {
		id, err := s.consumeWSTicket(ticket)
		if err != nil {
			http.Error(w, "invalid ws ticket", http.StatusUnauthorized)
			return
		}
		userID = &id
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	session := &Session{userID: userID}

	conn.SetReadLimit(maxMessageSize)
	_ = conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(pongWait))
	})

	pingTicker := time.NewTicker(pingPeriod)
	defer pingTicker.Stop()

	done := make(chan struct{})
	defer close(done)

	go func() {
		for {
			select {
			case <-pingTicker.C:
				player := session.getPlayer()
				if player != nil {
					_ = player.sendPing()
				}
			case <-done:
				return
			}
		}
	}()

	for {
		var msg incomingMessage
		if err := conn.ReadJSON(&msg); err != nil {
			break
		}

		switch msg.Type {
		case "create_room":
			var payload createRoomPayload
			_ = json.Unmarshal(msg.Payload, &payload)
			room, player, err := s.createRoom(conn, payload.Name, session.getUserID(), payload.GuestID)
			if err != nil {
				sendError(conn, err.Error())
				continue
			}
			session.set(room, player)

			response := roomResponsePayload{
				RoomCode:    room.code,
				PlayerID:    player.id,
				Symbol:      player.symbol,
				Role:        roleLabel(player),
				Reconnected: false,
				State:       room.snapshot(),
			}
			_ = player.send(newMessage("room_created", response))

		case "join_room":
			var payload joinRoomPayload
			if err := json.Unmarshal(msg.Payload, &payload); err != nil {
				sendError(conn, "invalid join_room payload")
				continue
			}

			room, player, reconnected, err := s.joinRoom(conn, payload.RoomCode, payload.PlayerID, payload.Name, payload.Spectator, session.getUserID(), payload.GuestID)
			if err != nil {
				sendError(conn, err.Error())
				continue
			}

			session.set(room, player)

			response := roomResponsePayload{
				RoomCode:    room.code,
				PlayerID:    player.id,
				Symbol:      player.symbol,
				Role:        roleLabel(player),
				Reconnected: reconnected,
				State:       room.snapshot(),
			}
			_ = player.send(newMessage("room_joined", response))

			s.broadcastState(room)

		case "move":
			var payload movePayload
			if err := json.Unmarshal(msg.Payload, &payload); err != nil {
				sendError(conn, "invalid move payload")
				continue
			}

			if err := s.applyMove(payload); err != nil {
				sendError(conn, err.Error())
				continue
			}
		case "rematch":
			var payload rematchPayload
			if err := json.Unmarshal(msg.Payload, &payload); err != nil {
				sendError(conn, "invalid rematch payload")
				continue
			}
			if err := s.rematch(payload); err != nil {
				sendError(conn, err.Error())
				continue
			}
		default:
			sendError(conn, "unknown message type")
		}
	}

	room, player := session.get()
	if room != nil && player != nil {
		s.handleDisconnect(room, player)
	}
}

func (s *Server) createRoom(conn *websocket.Conn, name string, sessionUserID *int64, guestID string) (*Room, *Player, error) {
	code := s.uniqueRoomCode()
	userID, err := s.resolveUserID(sessionUserID, guestID, sanitizeName(name, "Joueur X"))
	if err != nil {
		return nil, nil, err
	}
	player := &Player{
		id:        randomID(),
		name:      sanitizeName(name, "Joueur X"),
		symbol:    symbolX,
		userID:    userID,
		conn:      conn,
		connected: true,
	}

	room := &Room{
		code:           code,
		turn:           symbolX,
		startingSymbol: symbolX,
		startedAt:      time.Now().UTC(),
		playerX:        player,
		spectators:     make(map[string]*Player),
	}

	s.mu.Lock()
	s.rooms[code] = room
	s.mu.Unlock()

	return room, player, nil
}

func (s *Server) joinRoom(conn *websocket.Conn, code, playerID, name string, spectator bool, sessionUserID *int64, guestID string) (*Room, *Player, bool, error) {
	room := s.getRoom(code)
	if room == nil {
		return nil, nil, false, errors.New("room not found")
	}

	resolvedUserID, err := s.resolveUserID(sessionUserID, guestID, sanitizeName(name, "Joueur"))
	if err != nil {
		return nil, nil, false, err
	}

	room.mu.Lock()
	defer room.mu.Unlock()

	if room.closed {
		return nil, nil, false, errors.New("room is closed")
	}

	if spectator {
		return joinSpectator(room, conn, playerID, name, resolvedUserID)
	}

	if playerID != "" {
		if room.playerX != nil && room.playerX.id == playerID {
			if room.playerX.connected {
				return nil, nil, false, errors.New("player already connected")
			}
			attachPlayer(room.playerX, conn)
			if name != "" {
				room.playerX.name = sanitizeName(name, room.playerX.name)
			}
			if room.playerX.userID == 0 && resolvedUserID != 0 {
				room.playerX.userID = resolvedUserID
			}
			return room, room.playerX, true, nil
		}

		if room.playerO != nil && room.playerO.id == playerID {
			if room.playerO.connected {
				return nil, nil, false, errors.New("player already connected")
			}
			attachPlayer(room.playerO, conn)
			if name != "" {
				room.playerO.name = sanitizeName(name, room.playerO.name)
			}
			if room.playerO.userID == 0 && resolvedUserID != 0 {
				room.playerO.userID = resolvedUserID
			}
			return room, room.playerO, true, nil
		}
	}

	if room.playerO != nil {
		return nil, nil, false, errors.New("room already full")
	}

	player := &Player{
		id:        randomID(),
		name:      sanitizeName(name, "Joueur O"),
		symbol:    symbolO,
		userID:    resolvedUserID,
		conn:      conn,
		connected: true,
	}
	room.playerO = player

	return room, player, false, nil
}

func joinSpectator(room *Room, conn *websocket.Conn, spectatorID, name string, userID int64) (*Room, *Player, bool, error) {
	if room.spectators == nil {
		room.spectators = make(map[string]*Player)
	}

	if spectatorID != "" {
		if spectator, ok := room.spectators[spectatorID]; ok {
			if spectator.connected {
				return nil, nil, false, errors.New("spectator already connected")
			}
			attachPlayer(spectator, conn)
			if name != "" {
				spectator.name = sanitizeName(name, spectator.name)
			}
			if spectator.userID == 0 && userID != 0 {
				spectator.userID = userID
			}
			return room, spectator, true, nil
		}
	}

	spectator := &Player{
		id:        randomID(),
		name:      sanitizeName(name, "Spectateur"),
		spectator: true,
		userID:    userID,
		conn:      conn,
		connected: true,
	}
	room.spectators[spectator.id] = spectator

	return room, spectator, false, nil
}

func (s *Server) applyMove(payload movePayload) error {
	room := s.getRoom(payload.RoomCode)
	if room == nil {
		return errors.New("room not found")
	}

	state, recipients, record, err := room.applyMove(payload)
	if err != nil {
		return err
	}

	msg := newMessage("state", state)
	for _, client := range recipients {
		_ = client.send(msg)
	}

	if record != nil {
		if err := s.recordGame(*record); err != nil {
			log.Printf("game record failed: %v", err)
		}
	}

	return nil
}

func (s *Server) rematch(payload rematchPayload) error {
	room := s.getRoom(payload.RoomCode)
	if room == nil {
		return errors.New("room not found")
	}

	room.mu.Lock()
	if room.closed {
		room.mu.Unlock()
		return errors.New("room is closed")
	}

	player := room.playerByID(payload.PlayerID)
	if player == nil {
		room.mu.Unlock()
		return errors.New("player not found in room")
	}

	if !playerConnected(room.playerX) || !playerConnected(room.playerO) {
		room.mu.Unlock()
		return errors.New("waiting for opponent")
	}

	if room.winner == "" && !room.draw {
		room.mu.Unlock()
		return errors.New("game not finished")
	}

	room.resetGameLocked()
	room.mu.Unlock()

	s.broadcastState(room)
	return nil
}

func (s *Server) handleDisconnect(room *Room, player *Player) {
	room.mu.Lock()
	if room.closed {
		room.mu.Unlock()
		return
	}

	if !player.connected {
		room.mu.Unlock()
		return
	}

	player.connected = false
	if player.conn != nil {
		_ = player.conn.Close()
		player.conn = nil
	}

	if player.spectator {
		if room.spectators != nil {
			delete(room.spectators, player.id)
		}
		room.mu.Unlock()
		s.broadcastState(room)
		return
	}

	if player.disconnectTimer == nil {
		player.disconnectTimer = time.AfterFunc(time.Minute, func() {
			s.closeRoom(room, "timeout")
		})
	}

	bothDisconnected := !playerConnected(room.playerX) && !playerConnected(room.playerO)
	room.mu.Unlock()

	if bothDisconnected {
		s.closeRoom(room, "both_left")
		return
	}

	s.sendToRoom(room, newMessage("player_left", playerLeftPayload{PlayerID: player.id}))
	s.broadcastState(room)
}

func (s *Server) closeRoom(room *Room, reason string) {
	room.mu.Lock()
	if room.closed {
		room.mu.Unlock()
		return
	}
	room.closed = true

	players := []*Player{room.playerX, room.playerO}
	for _, spectator := range room.spectators {
		players = append(players, spectator)
	}
	room.mu.Unlock()

	msg := newMessage("room_closed", roomClosedPayload{Reason: reason})
	for _, player := range players {
		if player == nil {
			continue
		}
		if player.disconnectTimer != nil {
			player.disconnectTimer.Stop()
			player.disconnectTimer = nil
		}
		if player.connected {
			_ = player.send(msg)
			if player.conn != nil {
				_ = player.conn.Close()
			}
			player.connected = false
		}
	}

	s.mu.Lock()
	delete(s.rooms, room.code)
	s.mu.Unlock()
}

func (s *Server) sendToRoom(room *Room, msg outgoingMessage) {
	state, recipients := room.snapshotWithPlayers()
	_ = state
	for _, client := range recipients {
		_ = client.send(msg)
	}
}

func (s *Server) broadcastState(room *Room) {
	state, recipients := room.snapshotWithPlayers()
	msg := newMessage("state", state)
	for _, client := range recipients {
		_ = client.send(msg)
	}
}

func (r *Room) applyMove(payload movePayload) (statePayload, []*Player, *gameRecord, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.closed {
		return statePayload{}, nil, nil, errors.New("room is closed")
	}

	if payload.Cell < 0 || payload.Cell > 8 {
		return statePayload{}, nil, nil, errors.New("invalid cell")
	}

	player := r.playerByID(payload.PlayerID)
	if player == nil {
		return statePayload{}, nil, nil, errors.New("player not found in room")
	}

	if !player.connected {
		return statePayload{}, nil, nil, errors.New("player disconnected")
	}

	if !playerConnected(r.playerX) || !playerConnected(r.playerO) {
		return statePayload{}, nil, nil, errors.New("waiting for opponent")
	}

	if r.winner != "" || r.draw {
		return statePayload{}, nil, nil, errors.New("game already finished")
	}

	if r.turn != player.symbol {
		return statePayload{}, nil, nil, errors.New("not your turn")
	}

	if r.board[payload.Cell] != "" {
		return statePayload{}, nil, nil, errors.New("cell already taken")
	}

	r.board[payload.Cell] = player.symbol

	if winner := r.checkWinner(); winner != "" {
		r.winner = winner
	} else if r.checkDraw() {
		r.draw = true
	} else {
		r.turn = otherSymbol(r.turn)
	}

	state := r.snapshotLocked()
	recipients := r.connectedClientsLocked()

	var record *gameRecord
	if (r.winner != "" || r.draw) && !r.recorded {
		r.recorded = true
		endedAt := time.Now().UTC()
		game := buildGameRecord(r, endedAt)
		record = &game
	}

	return state, recipients, record, nil
}

func (r *Room) snapshot() statePayload {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.snapshotLocked()
}

func (r *Room) snapshotWithPlayers() (statePayload, []*Player) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.snapshotLocked(), r.connectedClientsLocked()
}

func (r *Room) snapshotLocked() statePayload {
	board := make([]string, 9)
	copy(board, r.board[:])

	status := statusWaiting
	if r.winner != "" {
		status = statusWin
	} else if r.draw {
		status = statusDraw
	} else if r.playerX == nil || r.playerO == nil {
		status = statusWaiting
	} else if !playerConnected(r.playerX) || !playerConnected(r.playerO) {
		status = statusPaused
	} else {
		status = statusInProgress
	}

	players := make(map[string]playerInfo)
	if r.playerX != nil {
		players[symbolX] = playerInfo{ID: r.playerX.id, Name: r.playerX.name, Connected: r.playerX.connected}
	}
	if r.playerO != nil {
		players[symbolO] = playerInfo{ID: r.playerO.id, Name: r.playerO.name, Connected: r.playerO.connected}
	}

	return statePayload{
		RoomCode: r.code,
		Board:    board,
		Turn:     r.turn,
		Status:   status,
		Winner:   r.winner,
		Players:  players,
	}
}

func (r *Room) connectedClientsLocked() []*Player {
	clients := []*Player{}
	if playerConnected(r.playerX) {
		clients = append(clients, r.playerX)
	}
	if playerConnected(r.playerO) {
		clients = append(clients, r.playerO)
	}
	for _, spectator := range r.spectators {
		if playerConnected(spectator) {
			clients = append(clients, spectator)
		}
	}
	return clients
}

func (r *Room) playerByID(id string) *Player {
	if r.playerX != nil && r.playerX.id == id {
		return r.playerX
	}
	if r.playerO != nil && r.playerO.id == id {
		return r.playerO
	}
	return nil
}

func (r *Room) checkWinner() string {
	for _, pattern := range winPatterns {
		first := r.board[pattern[0]]
		if first == "" {
			continue
		}
		if first == r.board[pattern[1]] && first == r.board[pattern[2]] {
			return first
		}
	}
	return ""
}

func (r *Room) checkDraw() bool {
	for _, cell := range r.board {
		if cell == "" {
			return false
		}
	}
	return true
}

func (r *Room) resetGameLocked() {
	for i := range r.board {
		r.board[i] = ""
	}
	if r.startingSymbol == "" {
		r.startingSymbol = symbolX
	} else {
		r.startingSymbol = otherSymbol(r.startingSymbol)
	}
	r.turn = r.startingSymbol
	r.winner = ""
	r.draw = false
	r.recorded = false
	r.startedAt = time.Now().UTC()
}

func attachPlayer(player *Player, conn *websocket.Conn) {
	player.conn = conn
	player.connected = true
	if player.disconnectTimer != nil {
		player.disconnectTimer.Stop()
		player.disconnectTimer = nil
	}
}

func playerConnected(player *Player) bool {
	return player != nil && player.connected && player.conn != nil
}

func (s *Server) uniqueRoomCode() string {
	for {
		code := randomRoomCode()
		s.mu.RLock()
		_, exists := s.rooms[code]
		s.mu.RUnlock()
		if !exists {
			return code
		}
	}
}

func (s *Server) getRoom(code string) *Room {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.rooms[strings.ToUpper(code)]
}

func (p *Player) send(msg outgoingMessage) error {
	if p == nil || !p.connected || p.conn == nil {
		return nil
	}
	p.sendMu.Lock()
	defer p.sendMu.Unlock()
	_ = p.conn.SetWriteDeadline(time.Now().Add(writeWait))
	return p.conn.WriteJSON(msg)
}

func (p *Player) sendPing() error {
	if p == nil || !p.connected || p.conn == nil {
		return nil
	}
	p.sendMu.Lock()
	defer p.sendMu.Unlock()
	_ = p.conn.SetWriteDeadline(time.Now().Add(writeWait))
	return p.conn.WriteMessage(websocket.PingMessage, []byte("ping"))
}

func newMessage(msgType string, payload any) outgoingMessage {
	if payload == nil {
		return outgoingMessage{Type: msgType}
	}
	data, _ := json.Marshal(payload)
	return outgoingMessage{Type: msgType, Payload: data}
}

func sendError(conn *websocket.Conn, msg string) {
	_ = conn.WriteJSON(newMessage("error", errorPayload{Message: msg}))
}

func otherSymbol(symbol string) string {
	if symbol == symbolX {
		return symbolO
	}
	return symbolX
}

func roleLabel(player *Player) string {
	if player == nil {
		return ""
	}
	if player.spectator {
		return "spectator"
	}
	return "player"
}

func sanitizeName(name, fallback string) string {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return fallback
	}
	const maxRunes = 20
	runes := []rune(trimmed)
	if len(runes) > maxRunes {
		return string(runes[:maxRunes])
	}
	return trimmed
}

func randomRoomCode() string {
	const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	bytes := make([]byte, roomCodeLength)
	if _, err := rand.Read(bytes); err != nil {
		return "ROOMXX"
	}
	for i := 0; i < roomCodeLength; i++ {
		bytes[i] = letters[int(bytes[i])%len(letters)]
	}
	return string(bytes)
}

func randomID() string {
	bytes := make([]byte, 8)
	if _, err := rand.Read(bytes); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(bytes)
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func resolveWebDir() string {
	if custom := os.Getenv("WEB_DIR"); custom != "" {
		if dirExists(custom) {
			return custom
		}
	}

	candidates := []string{
		"../build/web",
		"../webapp/dist",
		"./web",
	}
	for _, candidate := range candidates {
		if dirExists(candidate) {
			return candidate
		}
	}
	return ""
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func spaHandler(staticPath string) http.Handler {
	fileServer := http.FileServer(http.Dir(staticPath))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := filepath.Join(staticPath, filepath.Clean(r.URL.Path))
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			fileServer.ServeHTTP(w, r)
			return
		}
		r.URL.Path = "/"
		fileServer.ServeHTTP(w, r)
	})
}

func loadAllowedOrigins() map[string]struct{} {
	result := make(map[string]struct{})
	raw := strings.TrimSpace(os.Getenv("ALLOWED_ORIGINS"))
	if raw == "" {
		return result
	}
	for _, entry := range strings.Split(raw, ",") {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		entryLower := strings.ToLower(entry)
		result[entryLower] = struct{}{}
		if strings.Contains(entryLower, "://") {
			if parsed, err := url.Parse(entryLower); err == nil && parsed.Host != "" {
				result[parsed.Host] = struct{}{}
			}
		} else {
			result[entryLower] = struct{}{}
		}
	}
	return result
}

func isOriginAllowed(origin string) bool {
	if len(allowedOrigins) == 0 {
		return true
	}
	originLower := strings.ToLower(origin)
	if originLower == "" {
		// Allow non-browser clients (mobile) that don't send an Origin header.
		return true
	}
	if _, ok := allowedOrigins[originLower]; ok {
		return true
	}
	parsed, err := url.Parse(originLower)
	if err != nil || parsed.Host == "" {
		return false
	}
	_, ok := allowedOrigins[parsed.Host]
	return ok
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" {
			if !isOriginAllowed(origin) {
				http.Error(w, "origin not allowed", http.StatusForbidden)
				return
			}
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Add("Vary", "Origin")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func (s *Session) set(room *Room, player *Player) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.room = room
	s.player = player
}

func (s *Session) getUserID() *int64 {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.userID
}

func (s *Session) getPlayer() *Player {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.player
}

func (s *Session) get() (*Room, *Player) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.room, s.player
}
