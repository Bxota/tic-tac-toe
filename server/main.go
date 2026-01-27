package main

import (
	"crypto/rand"
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

type createRoomPayload struct{}

type joinRoomPayload struct {
  RoomCode string `json:"room_code"`
  PlayerID string `json:"player_id,omitempty"`
}

type movePayload struct {
  RoomCode string `json:"room_code"`
  PlayerID string `json:"player_id"`
  Cell     int    `json:"cell"`
}

type errorPayload struct {
  Message string `json:"message"`
}

type roomResponsePayload struct {
  RoomCode    string       `json:"room_code"`
  PlayerID    string       `json:"player_id"`
  Symbol      string       `json:"symbol"`
  Reconnected bool         `json:"reconnected"`
  State       statePayload `json:"state"`
}

type playerInfo struct {
  ID        string `json:"id"`
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
  symbol           string
  conn             *websocket.Conn
  connected        bool
  sendMu           sync.Mutex
  disconnectTimer  *time.Timer
  disconnectReason string
}

type Room struct {
  code   string
  board  [9]string
  turn   string
  winner string
  draw   bool

  playerX *Player
  playerO *Player

  closed bool
  mu     sync.Mutex
}

type Server struct {
  rooms map[string]*Room
  mu    sync.RWMutex
}

type Session struct {
	room   *Room
	player *Player
	mu     sync.RWMutex
}

func main() {
  addr := envOr("ADDR", ":8080")
  webDir := resolveWebDir()

  srv := NewServer()
  mux := http.NewServeMux()
  mux.HandleFunc("/ws", srv.handleWS)
  mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    _, _ = w.Write([]byte("ok"))
  })

  if webDir != "" {
    mux.Handle("/", spaHandler(webDir))
    log.Printf("serving web from %s", webDir)
  } else {
    log.Printf("no web directory found, only websocket available")
  }

  log.Printf("listening on %s", addr)
  if err := http.ListenAndServe(addr, mux); err != nil {
    log.Fatal(err)
  }
}

func NewServer() *Server {
  return &Server{rooms: make(map[string]*Room)}
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	session := &Session{}

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
		room, player := s.createRoom(conn)
		session.set(room, player)

		payload := roomResponsePayload{
			RoomCode:    room.code,
			PlayerID:    player.id,
        Symbol:      player.symbol,
        Reconnected: false,
        State:       room.snapshot(),
      }
      _ = player.send(newMessage("room_created", payload))

	case "join_room":
      var payload joinRoomPayload
      if err := json.Unmarshal(msg.Payload, &payload); err != nil {
        sendError(conn, "invalid join_room payload")
        continue
      }

      room, player, reconnected, err := s.joinRoom(conn, payload.RoomCode, payload.PlayerID)
      if err != nil {
        sendError(conn, err.Error())
        continue
      }

		session.set(room, player)

      response := roomResponsePayload{
        RoomCode:    room.code,
        PlayerID:    player.id,
        Symbol:      player.symbol,
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
    default:
      sendError(conn, "unknown message type")
    }
  }

	room, player := session.get()
	if room != nil && player != nil {
		s.handleDisconnect(room, player)
	}
}

func (s *Server) createRoom(conn *websocket.Conn) (*Room, *Player) {
  code := s.uniqueRoomCode()
  player := &Player{
    id:        randomID(),
    symbol:    symbolX,
    conn:      conn,
    connected: true,
  }

  room := &Room{
    code:    code,
    turn:    symbolX,
    playerX: player,
  }

  s.mu.Lock()
  s.rooms[code] = room
  s.mu.Unlock()

  return room, player
}

func (s *Server) joinRoom(conn *websocket.Conn, code, playerID string) (*Room, *Player, bool, error) {
  room := s.getRoom(code)
  if room == nil {
    return nil, nil, false, errors.New("room not found")
  }

  room.mu.Lock()
  defer room.mu.Unlock()

  if room.closed {
    return nil, nil, false, errors.New("room is closed")
  }

  if playerID != "" {
    if room.playerX != nil && room.playerX.id == playerID {
      if room.playerX.connected {
        return nil, nil, false, errors.New("player already connected")
      }
      attachPlayer(room.playerX, conn)
      return room, room.playerX, true, nil
    }

    if room.playerO != nil && room.playerO.id == playerID {
      if room.playerO.connected {
        return nil, nil, false, errors.New("player already connected")
      }
      attachPlayer(room.playerO, conn)
      return room, room.playerO, true, nil
    }
  }

  if room.playerO != nil {
    return nil, nil, false, errors.New("room already full")
  }

  player := &Player{
    id:        randomID(),
    symbol:    symbolO,
    conn:      conn,
    connected: true,
  }
  room.playerO = player

  return room, player, false, nil
}

func (s *Server) applyMove(payload movePayload) error {
  room := s.getRoom(payload.RoomCode)
  if room == nil {
    return errors.New("room not found")
  }

  state, players, err := room.applyMove(payload)
  if err != nil {
    return err
  }

  msg := newMessage("state", state)
  for _, player := range players {
    _ = player.send(msg)
  }

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
  state, players := room.snapshotWithPlayers()
  _ = state
  for _, player := range players {
    _ = player.send(msg)
  }
}

func (s *Server) broadcastState(room *Room) {
  state, players := room.snapshotWithPlayers()
  msg := newMessage("state", state)
  for _, player := range players {
    _ = player.send(msg)
  }
}

func (r *Room) applyMove(payload movePayload) (statePayload, []*Player, error) {
  r.mu.Lock()
  defer r.mu.Unlock()

  if r.closed {
    return statePayload{}, nil, errors.New("room is closed")
  }

  if payload.Cell < 0 || payload.Cell > 8 {
    return statePayload{}, nil, errors.New("invalid cell")
  }

  player := r.playerByID(payload.PlayerID)
  if player == nil {
    return statePayload{}, nil, errors.New("player not found in room")
  }

  if !player.connected {
    return statePayload{}, nil, errors.New("player disconnected")
  }

  if !playerConnected(r.playerX) || !playerConnected(r.playerO) {
    return statePayload{}, nil, errors.New("waiting for opponent")
  }

  if r.winner != "" || r.draw {
    return statePayload{}, nil, errors.New("game already finished")
  }

  if r.turn != player.symbol {
    return statePayload{}, nil, errors.New("not your turn")
  }

  if r.board[payload.Cell] != "" {
    return statePayload{}, nil, errors.New("cell already taken")
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
  players := r.connectedPlayersLocked()

  return state, players, nil
}

func (r *Room) snapshot() statePayload {
  r.mu.Lock()
  defer r.mu.Unlock()
  return r.snapshotLocked()
}

func (r *Room) snapshotWithPlayers() (statePayload, []*Player) {
  r.mu.Lock()
  defer r.mu.Unlock()
  return r.snapshotLocked(), r.connectedPlayersLocked()
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
    players[symbolX] = playerInfo{ID: r.playerX.id, Connected: r.playerX.connected}
  }
  if r.playerO != nil {
    players[symbolO] = playerInfo{ID: r.playerO.id, Connected: r.playerO.connected}
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

func (r *Room) connectedPlayersLocked() []*Player {
  players := []*Player{}
  if playerConnected(r.playerX) {
    players = append(players, r.playerX)
  }
  if playerConnected(r.playerO) {
    players = append(players, r.playerO)
  }
  return players
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

func (s *Session) set(room *Room, player *Player) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.room = room
	s.player = player
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
