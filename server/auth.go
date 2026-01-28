package main

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

type discordConfig struct {
	ClientID     string
	ClientSecret string
	RedirectURI  string
}

type User struct {
	ID        int64  `json:"id"`
	DiscordID string `json:"discord_id,omitempty"`
	Username  string `json:"username"`
	Avatar    string `json:"avatar,omitempty"`
	IsGuest   bool   `json:"is_guest"`
}

type authResponse struct {
	User         User   `json:"user"`
	AccessToken  string `json:"access_token"`
	ExpiresIn    int64  `json:"expires_in"`
	RefreshToken string `json:"refresh_token,omitempty"`
}

type wsTicketResponse struct {
	Ticket    string `json:"ticket"`
	ExpiresIn int64  `json:"expires_in"`
}

type discordTokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int64  `json:"expires_in"`
	Scope       string `json:"scope"`
}

type discordUser struct {
	ID         string `json:"id"`
	Username   string `json:"username"`
	GlobalName string `json:"global_name"`
	Avatar     string `json:"avatar"`
}

func loadDiscordConfig() (discordConfig, error) {
	config := discordConfig{
		ClientID:     strings.TrimSpace(os.Getenv("DISCORD_CLIENT_ID")),
		ClientSecret: strings.TrimSpace(os.Getenv("DISCORD_CLIENT_SECRET")),
		RedirectURI:  strings.TrimSpace(os.Getenv("DISCORD_REDIRECT_URL")),
	}
	if config.ClientID == "" || config.ClientSecret == "" || config.RedirectURI == "" {
		return config, errors.New("discord oauth not configured")
	}
	return config, nil
}

func (s *Server) handleDiscordLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if s.discord.ClientID == "" {
		http.Error(w, "discord oauth not configured", http.StatusServiceUnavailable)
		return
	}

	state := randomToken(18)
	setCookie(w, "oauth_state", state, 10*time.Minute, true, r)

	guestID := normalizeGuestID(r.URL.Query().Get("guest_id"))
	if guestID != "" {
		setCookie(w, "guest_id", guestID, 10*time.Minute, true, r)
	}

	returnTo := sanitizeReturnTo(r.URL.Query().Get("return_to"))
	if returnTo != "" {
		setCookie(w, "post_login_redirect", returnTo, 10*time.Minute, true, r)
	}

	authURL := buildDiscordAuthURL(s.discord, state)
	http.Redirect(w, r, authURL, http.StatusFound)
}

func (s *Server) handleDiscordCallback(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if s.discord.ClientID == "" {
		http.Error(w, "discord oauth not configured", http.StatusServiceUnavailable)
		return
	}
	state := r.URL.Query().Get("state")
	code := r.URL.Query().Get("code")
	if state == "" || code == "" {
		http.Error(w, "invalid oauth response", http.StatusBadRequest)
		return
	}

	if !matchesCookie(r, "oauth_state", state) {
		http.Error(w, "invalid oauth state", http.StatusUnauthorized)
		return
	}

	token, err := exchangeDiscordCode(s.discord, code)
	if err != nil {
		log.Printf("discord token exchange failed: %v", err)
		http.Error(w, "oauth exchange failed", http.StatusBadGateway)
		return
	}

	user, err := fetchDiscordUser(token.AccessToken)
	if err != nil {
		log.Printf("discord user fetch failed: %v", err)
		http.Error(w, "oauth user fetch failed", http.StatusBadGateway)
		return
	}

	guestID := ""
	if cookie, err := r.Cookie("guest_id"); err == nil {
		guestID = normalizeGuestID(cookie.Value)
	}

	userID, _, err := s.upsertDiscordUser(user, guestID)
	if err != nil {
		log.Printf("oauth user store failed: %v", err)
		http.Error(w, "oauth user store failed", http.StatusInternalServerError)
		return
	}

	_, refreshToken, _, refreshExp, err := s.createSession(userID)
	if err != nil {
		log.Printf("oauth session create failed: %v", err)
		http.Error(w, "oauth session failed", http.StatusInternalServerError)
		return
	}

	setRefreshCookie(w, refreshToken, refreshExp, r)
	clearCookie(w, "oauth_state")
	clearCookie(w, "guest_id")

	redirectPath := "/"
	if cookie, err := r.Cookie("post_login_redirect"); err == nil {
		redirectPath = sanitizeReturnTo(cookie.Value)
	}
	clearCookie(w, "post_login_redirect")

	http.Redirect(w, r, redirectPath, http.StatusFound)
}

func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	refreshToken, fromCookie := readRefreshToken(r)
	if refreshToken == "" {
		http.Error(w, "missing refresh token", http.StatusUnauthorized)
		return
	}

	sessionID, user, err := s.sessionFromRefreshToken(refreshToken)
	if err != nil {
		http.Error(w, "invalid refresh token", http.StatusUnauthorized)
		return
	}

	accessToken, newRefresh, accessExp, refreshExp, err := s.rotateSession(sessionID)
	if err != nil {
		log.Printf("session rotate failed: %v", err)
		http.Error(w, "session rotate failed", http.StatusInternalServerError)
		return
	}

	response := authResponse{
		User:        user,
		AccessToken: accessToken,
		ExpiresIn:   accessExp - nowUnix(),
	}
	if fromCookie {
		setRefreshCookie(w, newRefresh, refreshExp, r)
	} else {
		response.RefreshToken = newRefresh
	}

	writeJSON(w, response, http.StatusOK)
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	user, err := s.userFromRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	writeJSON(w, user, http.StatusOK)
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	accessToken := readBearerToken(r)
	refreshToken, _ := readRefreshToken(r)
	if accessToken != "" {
		_ = s.deleteSessionByAccessToken(accessToken)
	}
	if refreshToken != "" {
		_ = s.deleteSessionByRefreshToken(refreshToken)
	}

	clearCookie(w, "refresh_token")
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleWSTicket(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	user, err := s.userFromRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	ticket, expiresAt, err := s.createWSTicket(user.ID)
	if err != nil {
		log.Printf("ws ticket failed: %v", err)
		http.Error(w, "ticket failed", http.StatusInternalServerError)
		return
	}

	writeJSON(w, wsTicketResponse{Ticket: ticket, ExpiresIn: expiresAt - nowUnix()}, http.StatusOK)
}

func (s *Server) handleHistory(w http.ResponseWriter, r *http.Request) {
	user, err := s.userFromRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	items, err := s.loadHistory(user.ID, 50)
	if err != nil {
		log.Printf("history load failed: %v", err)
		http.Error(w, "history failed", http.StatusInternalServerError)
		return
	}

	writeJSON(w, items, http.StatusOK)
}

func (s *Server) handleStats(w http.ResponseWriter, r *http.Request) {
	user, err := s.userFromRequest(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	stats, err := s.loadStats(user.ID)
	if err != nil {
		log.Printf("stats load failed: %v", err)
		http.Error(w, "stats failed", http.StatusInternalServerError)
		return
	}

	writeJSON(w, stats, http.StatusOK)
}

func exchangeDiscordCode(config discordConfig, code string) (discordTokenResponse, error) {
	data := url.Values{}
	data.Set("client_id", config.ClientID)
	data.Set("client_secret", config.ClientSecret)
	data.Set("grant_type", "authorization_code")
	data.Set("code", code)
	data.Set("redirect_uri", config.RedirectURI)

	req, err := http.NewRequest(http.MethodPost, "https://discord.com/api/v10/oauth2/token", strings.NewReader(data.Encode()))
	if err != nil {
		return discordTokenResponse{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return discordTokenResponse{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return discordTokenResponse{}, fmt.Errorf("discord token error: %s", string(body))
	}
	var token discordTokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
		return discordTokenResponse{}, err
	}
	return token, nil
}

func fetchDiscordUser(accessToken string) (discordUser, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest(http.MethodGet, "https://discord.com/api/v10/users/@me", nil)
	if err != nil {
		return discordUser{}, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	resp, err := client.Do(req)
	if err != nil {
		return discordUser{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return discordUser{}, fmt.Errorf("discord user error: %s", string(body))
	}
	var user discordUser
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return discordUser{}, err
	}
	return user, nil
}

func buildDiscordAuthURL(config discordConfig, state string) string {
	params := url.Values{}
	params.Set("client_id", config.ClientID)
	params.Set("redirect_uri", config.RedirectURI)
	params.Set("response_type", "code")
	params.Set("scope", "identify")
	params.Set("state", state)
	params.Set("prompt", "consent")
	return "https://discord.com/oauth2/authorize?" + params.Encode()
}

func sanitizeReturnTo(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	if strings.HasPrefix(trimmed, "//") {
		return ""
	}
	if strings.HasPrefix(trimmed, "/") {
		return trimmed
	}
	return ""
}

func readRefreshToken(r *http.Request) (string, bool) {
	if cookie, err := r.Cookie("refresh_token"); err == nil && cookie.Value != "" {
		return cookie.Value, true
	}
	var payload struct {
		RefreshToken string `json:"refresh_token"`
	}
	body, err := io.ReadAll(r.Body)
	if err != nil || len(body) == 0 {
		return "", false
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return "", false
	}
	return strings.TrimSpace(payload.RefreshToken), false
}

func readBearerToken(r *http.Request) string {
	value := strings.TrimSpace(r.Header.Get("Authorization"))
	if value == "" {
		return ""
	}
	parts := strings.SplitN(value, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return strings.TrimSpace(parts[1])
}

func (s *Server) userFromRequest(r *http.Request) (User, error) {
	accessToken := readBearerToken(r)
	if accessToken == "" {
		return User{}, errors.New("missing token")
	}
	return s.userFromAccessToken(accessToken)
}

func randomToken(size int) string {
	bytes := make([]byte, size)
	if _, err := rand.Read(bytes); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return base64.RawURLEncoding.EncodeToString(bytes)
}

func setCookie(w http.ResponseWriter, name, value string, maxAge time.Duration, httpOnly bool, r *http.Request) {
	http.SetCookie(w, &http.Cookie{
		Name:     name,
		Value:    value,
		Path:     "/",
		MaxAge:   int(maxAge.Seconds()),
		Expires:  time.Now().Add(maxAge),
		HttpOnly: httpOnly,
		SameSite: http.SameSiteLaxMode,
		Secure:   isSecureRequest(r),
	})
}

func setRefreshCookie(w http.ResponseWriter, token string, expiresAt int64, r *http.Request) {
	maxAge := time.Unix(expiresAt, 0).Sub(time.Now())
	if maxAge < 0 {
		maxAge = 0
	}
	setCookie(w, "refresh_token", token, maxAge, true, r)
}

func clearCookie(w http.ResponseWriter, name string) {
	http.SetCookie(w, &http.Cookie{
		Name:     name,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		Expires:  time.Unix(0, 0),
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
	})
}

func matchesCookie(r *http.Request, name, expected string) bool {
	cookie, err := r.Cookie(name)
	if err != nil {
		return false
	}
	return cookie.Value == expected
}

func isSecureRequest(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	proto := strings.ToLower(strings.TrimSpace(r.Header.Get("X-Forwarded-Proto")))
	return proto == "https"
}

func writeJSON(w http.ResponseWriter, payload any, status int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func (s *Server) upsertDiscordUser(user discordUser, guestID string) (int64, User, error) {
	displayName := strings.TrimSpace(user.GlobalName)
	if displayName == "" {
		displayName = strings.TrimSpace(user.Username)
	}
	avatarURL := ""
	if user.Avatar != "" {
		avatarURL = fmt.Sprintf("https://cdn.discordapp.com/avatars/%s/%s.png", user.ID, user.Avatar)
	}

	now := nowUnix()
	var stored User
	err := withTx(s.db, func(tx *sql.Tx) error {
		var discordID int64
		discordErr := tx.QueryRow("SELECT id FROM users WHERE discord_id = ?", user.ID).Scan(&discordID)
		if discordErr != nil && discordErr != sql.ErrNoRows {
			return discordErr
		}

		guestID = normalizeGuestID(guestID)
		var guestUserID int64
		guestErr := sql.ErrNoRows
		if guestID != "" {
			guestErr = tx.QueryRow("SELECT id FROM users WHERE guest_id = ?", guestID).Scan(&guestUserID)
			if guestErr != nil && guestErr != sql.ErrNoRows {
				return guestErr
			}
		}

		if discordErr == nil {
			if _, err := tx.Exec("UPDATE users SET username = ?, avatar = ?, is_guest = 0 WHERE id = ?", displayName, avatarURL, discordID); err != nil {
				return err
			}
			if guestErr == nil && guestUserID != discordID {
				if err := mergeUsers(tx, guestUserID, discordID); err != nil {
					return err
				}
			}
			stored = User{ID: discordID, DiscordID: user.ID, Username: displayName, Avatar: avatarURL, IsGuest: false}
			return nil
		}

		if guestErr == nil {
			if _, err := tx.Exec("UPDATE users SET discord_id = ?, username = ?, avatar = ?, is_guest = 0 WHERE id = ?", user.ID, displayName, avatarURL, guestUserID); err != nil {
				return err
			}
			stored = User{ID: guestUserID, DiscordID: user.ID, Username: displayName, Avatar: avatarURL, IsGuest: false}
			return nil
		}

		res, err := tx.Exec("INSERT INTO users (discord_id, username, avatar, is_guest, created_at) VALUES (?, ?, ?, 0, ?)", user.ID, displayName, avatarURL, now)
		if err != nil {
			return err
		}
		newID, err := res.LastInsertId()
		if err != nil {
			return err
		}
		stored = User{ID: newID, DiscordID: user.ID, Username: displayName, Avatar: avatarURL, IsGuest: false}
		return nil
	})
	return stored.ID, stored, err
}

func (s *Server) ensureGuestUser(guestID, name string) (int64, error) {
	guestID = normalizeGuestID(guestID)
	if guestID == "" {
		return 0, nil
	}

	if name == "" {
		name = "Invite"
	}

	var userID int64
	if err := s.db.QueryRow("SELECT id FROM users WHERE guest_id = ?", guestID).Scan(&userID); err == nil {
		if name != "" {
			_, _ = s.db.Exec("UPDATE users SET username = ? WHERE id = ?", name, userID)
		}
		return userID, nil
	} else if err != sql.ErrNoRows {
		return 0, err
	}

	res, err := s.db.Exec("INSERT INTO users (guest_id, username, is_guest, created_at) VALUES (?, ?, 1, ?)", guestID, name, nowUnix())
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Server) resolveUserID(sessionUserID *int64, guestID, name string) (int64, error) {
	if sessionUserID != nil && *sessionUserID != 0 {
		return *sessionUserID, nil
	}
	return s.ensureGuestUser(guestID, name)
}

func (s *Server) createSession(userID int64) (string, string, int64, int64, error) {
	accessToken := randomToken(24)
	refreshToken := randomToken(36)
	accessExp := nowUnix() + int64(accessTokenTTL.Seconds())
	refreshExp := nowUnix() + int64(refreshTokenTTL.Seconds())

	_, err := s.db.Exec(
		"INSERT INTO sessions (user_id, access_token_hash, access_expires_at, refresh_token_hash, refresh_expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)",
		userID,
		hashToken(accessToken),
		accessExp,
		hashToken(refreshToken),
		refreshExp,
		nowUnix(),
	)
	if err != nil {
		return "", "", 0, 0, err
	}
	return accessToken, refreshToken, accessExp, refreshExp, nil
}

func (s *Server) sessionFromRefreshToken(refreshToken string) (int64, User, error) {
	if refreshToken == "" {
		return 0, User{}, errors.New("missing token")
	}
	row := s.db.QueryRow(
		`SELECT s.id, u.id, u.discord_id, u.username, u.avatar, u.is_guest, s.refresh_expires_at
		 FROM sessions s
		 JOIN users u ON u.id = s.user_id
		 WHERE s.refresh_token_hash = ?`,
		hashToken(refreshToken),
	)
	var sessionID, userID int64
	var discordID, username, avatar string
	var isGuest int
	var refreshExp int64
	if err := row.Scan(&sessionID, &userID, &discordID, &username, &avatar, &isGuest, &refreshExp); err != nil {
		return 0, User{}, err
	}
	if refreshExp <= nowUnix() {
		return 0, User{}, errors.New("refresh token expired")
	}
	return sessionID, User{ID: userID, DiscordID: discordID, Username: username, Avatar: avatar, IsGuest: isGuest == 1}, nil
}

func (s *Server) rotateSession(sessionID int64) (string, string, int64, int64, error) {
	accessToken := randomToken(24)
	refreshToken := randomToken(36)
	accessExp := nowUnix() + int64(accessTokenTTL.Seconds())
	refreshExp := nowUnix() + int64(refreshTokenTTL.Seconds())

	_, err := s.db.Exec(
		"UPDATE sessions SET access_token_hash = ?, access_expires_at = ?, refresh_token_hash = ?, refresh_expires_at = ? WHERE id = ?",
		hashToken(accessToken),
		accessExp,
		hashToken(refreshToken),
		refreshExp,
		sessionID,
	)
	if err != nil {
		return "", "", 0, 0, err
	}
	return accessToken, refreshToken, accessExp, refreshExp, nil
}

func (s *Server) userFromAccessToken(accessToken string) (User, error) {
	if accessToken == "" {
		return User{}, errors.New("missing token")
	}
	row := s.db.QueryRow(
		`SELECT u.id, u.discord_id, u.username, u.avatar, u.is_guest, s.access_expires_at
		 FROM sessions s
		 JOIN users u ON u.id = s.user_id
		 WHERE s.access_token_hash = ?`,
		hashToken(accessToken),
	)
	var user User
	var expiresAt int64
	var isGuest int
	if err := row.Scan(&user.ID, &user.DiscordID, &user.Username, &user.Avatar, &isGuest, &expiresAt); err != nil {
		return User{}, err
	}
	if expiresAt <= nowUnix() {
		return User{}, errors.New("access token expired")
	}
	user.IsGuest = isGuest == 1
	return user, nil
}

func (s *Server) deleteSessionByAccessToken(token string) error {
	if token == "" {
		return nil
	}
	_, err := s.db.Exec("DELETE FROM sessions WHERE access_token_hash = ?", hashToken(token))
	return err
}

func (s *Server) deleteSessionByRefreshToken(token string) error {
	if token == "" {
		return nil
	}
	_, err := s.db.Exec("DELETE FROM sessions WHERE refresh_token_hash = ?", hashToken(token))
	return err
}

func (s *Server) createWSTicket(userID int64) (string, int64, error) {
	if userID == 0 {
		return "", 0, errors.New("missing user id")
	}
	ticket := randomToken(18)
	expiresAt := nowUnix() + int64(wsTicketTTL.Seconds())
	_, err := s.db.Exec("INSERT INTO ws_tickets (user_id, ticket_hash, expires_at, used, created_at) VALUES (?, ?, ?, 0, ?)", userID, hashToken(ticket), expiresAt, nowUnix())
	if err != nil {
		return "", 0, err
	}
	return ticket, expiresAt, nil
}

func (s *Server) consumeWSTicket(ticket string) (int64, error) {
	if ticket == "" {
		return 0, errors.New("missing ticket")
	}

	var userID int64
	var expiresAt int64
	var used int
	row := s.db.QueryRow("SELECT user_id, expires_at, used FROM ws_tickets WHERE ticket_hash = ?", hashToken(ticket))
	if err := row.Scan(&userID, &expiresAt, &used); err != nil {
		return 0, err
	}
	if used == 1 || expiresAt <= nowUnix() {
		return 0, errors.New("ticket expired")
	}
	_, err := s.db.Exec("UPDATE ws_tickets SET used = 1 WHERE ticket_hash = ?", hashToken(ticket))
	if err != nil {
		return 0, err
	}
	return userID, nil
}

func withTx(db *sql.DB, fn func(*sql.Tx) error) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

func mergeUsers(tx *sql.Tx, fromID, toID int64) error {
	if fromID == 0 || toID == 0 || fromID == toID {
		return nil
	}
	if _, err := tx.Exec("UPDATE games SET player_x_user_id = ? WHERE player_x_user_id = ?", toID, fromID); err != nil {
		return err
	}
	if _, err := tx.Exec("UPDATE games SET player_o_user_id = ? WHERE player_o_user_id = ?", toID, fromID); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM sessions WHERE user_id = ?", fromID); err != nil {
		return err
	}
	if _, err := tx.Exec("DELETE FROM users WHERE id = ?", fromID); err != nil {
		return err
	}
	return nil
}
