# tic_tac_toe

Flutter (iOS/Android) + Vue Web + Go WebSocket backend for a real-time Tic-Tac-Toe.

Web frontend expects Node 25+.

## Backend (Go)

```bash
cd server
# Go 1.24+
go run .
```

By default the server listens on `:8080` and exposes:

- `GET /health`
- `WS /ws`
- `GET /auth/discord/login`
- `GET /auth/discord/callback`
- `POST /auth/refresh`
- `GET /auth/me`
- `POST /auth/logout`
- `POST /auth/ws-ticket`
- `GET /api/history`
- `GET /api/stats`
- static web files (if available)

### Serve Vue Web

Build the web bundle from the project root:

```bash
cd webapp
npm install
npm run build
```

Dev server (Node 25+):

```bash
cd webapp
npm run dev
```

Then run the Go server with the web directory:

```bash
cd server
WEB_DIR=../webapp/dist go run .
```

### Discord OAuth + SQLite

The server persists users/sessions/games in SQLite and supports Discord login.

Required environment variables:$

- `DB_PATH` (default: `./data/tictactoe.db`)
- `DISCORD_CLIENT_ID`
- `DISCORD_CLIENT_SECRET`
- `DISCORD_REDIRECT_URL` (e.g. `https://tictactoe.bxota.com/auth/discord/callback`)

## Flutter app

Run on web or mobile by pointing to your server:

```bash
flutter run -d chrome --dart-define=SERVER_URL=ws://localhost:8080/ws
```

For mobile, replace `localhost` with your VPS domain/IP:

```bash
flutter run --dart-define=SERVER_URL=ws://YOUR_VPS_IP:8080/ws
```

## Deployment (Docker + Caddy + GitHub Actions)

This repo includes:

- `Dockerfile` (builds Go server + Vue web)
- `deploy/docker-compose.yml` and `deploy/Caddyfile`
- `.github/workflows/deploy.yml`

### VPS setup (Ubuntu)

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
```

### Configure the deployment folder

```bash
sudo mkdir -p /opt/tictactoe
sudo chown -R $USER:$USER /opt/tictactoe
```

Copy `deploy/docker-compose.yml` and `deploy/Caddyfile` to `/opt/tictactoe` and update:

- `OWNER/REPO` with your GitHub repo
- domain in `Caddyfile` (default: `tictactoe.bxota.com`)
- Discord env vars in `.env` (or inline)

Then:

```bash
cd /opt/tictactoe
docker compose up -d
```

### GitHub Actions secrets

Add these repo secrets:

- `VPS_HOST` (VPS IP)
- `VPS_USER` (SSH user)
- `VPS_SSH_KEY` (private key content)

### Vue Web WebSocket URL

By default, the web app derives the WebSocket URL from the current domain.
If you want to override it, build with:

```text
VITE_WS_URL=wss://tictactoe.bxota.com/ws npm run build
```

Change it if you use another domain.

If your API runs on a different origin in dev, you can also set:

```text
VITE_API_URL=http://localhost:8080 npm run dev
```

## Notes

- Rooms are private (6-letter code).
- Rules are enforced server-side.
- Reconnect: a player has 1 minute to reconnect before the room closes.
- Optional: set `ALLOWED_ORIGINS` env on the server (comma-separated) to restrict WebSocket origins.
