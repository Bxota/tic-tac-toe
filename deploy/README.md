# Deployment (Docker + Caddy)

1) Copy this folder to `/opt/tictactoe` on the VPS.
2) Edit `docker-compose.yml` and replace `OWNER/REPO` with your GitHub repo.
3) Ensure DNS `tictactoe.bxota.com` points to your VPS IP.
4) Run:

```bash
cd /opt/tictactoe
sudo docker compose up -d
```

Caddy will fetch TLS certificates automatically.

Optional: set `ALLOWED_ORIGINS` in `docker-compose.yml` to restrict WebSocket origins.
