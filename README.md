# tic_tac_toe

Flutter (iOS/Android/Web) + Go WebSocket backend for a real-time Tic-Tac-Toe.

## Backend (Go)

```bash
cd server
# Go 1.22+
go run .
```

By default the server listens on `:8080` and exposes:
- `GET /health`
- `WS /ws`
- static web files (if available)

### Serve Flutter Web

Build the web bundle from the project root:

```bash
flutter build web
```

Then run the Go server with the web directory:

```bash
cd server
WEB_DIR=../build/web go run .
```

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
- `Dockerfile` (builds Go server + serves `build/web`)
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

### Flutter Web build URL

The workflow builds Flutter Web with:
```
--dart-define=SERVER_URL=wss://tictactoe.bxota.com/ws
```
Change it if you use another domain.

## Notes
- Rooms are private (6-letter code).
- Rules are enforced server-side.
- Reconnect: a player has 1 minute to reconnect before the room closes.
- Optional: set `ALLOWED_ORIGINS` env on the server (comma-separated) to restrict WebSocket origins.
