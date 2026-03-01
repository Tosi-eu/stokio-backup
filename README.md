# Infrastructure

This directory holds everything needed to run and secure the **Abrigo** application on a VPS: Docker Compose stack, reverse proxy, firewall, and backups.

## Layout

```
infrastructure/
├── README.md                 # This file
├── docker-compose.yml        # Main stack (postgres, redis, backend, frontend, proxy, backup)
├── backup/                   # PostgreSQL backup container and scripts
├── proxy/                    # Nginx reverse proxy
│   └── nginx/
│       ├── nginx.conf
│       ├── conf.d/default.conf
│       └── ssl/              # Place SSL certs here for HTTPS
├── firewall/                 # UFW rules and docs
│   ├── ufw-setup.sh
│   └── README.md
└── ssh/                      # SSH somente com chave pública
    ├── README.md
    ├── configure-key-only.sh
    └── sshd-config-snippet.conf
```

## Prerequisites

- Docker and Docker Compose on the VPS
- `.env` at the **repository root** with DB, JWT, and app variables (copy root `cp .env.example .env` and fill in)
- (Optional) SSL certificates for HTTPS in `proxy/nginx/ssl/`

## Run the stack

From the **repository root** (the root `docker-compose.yml` includes this file):

```bash
docker compose up -d --build
```

Or explicitly:

```bash
docker compose -f infrastructure/docker-compose.yml up -d --build
```

From the `infrastructure/` directory:

```bash
docker compose -f docker-compose.yml up -d --build
```

- App (via proxy): **http://localhost** (port 80)
- API: **http://localhost/api/v1**
- PostgreSQL and Redis are not exposed on the host by default (internal network only).

## VPS deployment checklist

1. **Server**
   - Ubuntu 22.04 or similar
   - Docker and Docker Compose installed
   - Non-root user with sudo (optional but recommended)

2. **SSH (recomendado: só chave pública)**  
   - Adicione sua chave em `~/.ssh/authorized_keys` no VPS.
   - Depois: `infrastructure/ssh/configure-key-only.sh` (veja `infrastructure/ssh/README.md`).

3. **Repository**
   - Clone the repo on the VPS
   - Copy `.env.sample` to `.env` at repo root and fill in values (especially `JWT_SECRET`, DB password, `ALLOWED_ORIGINS`)

4. **Firewall**
   - Run `infrastructure/firewall/ufw-setup.sh` (opens SSH, 80, 443)
   - Optionally restrict SSH to a specific IP (see `firewall/README.md`)

5. **Proxy & SSL**
   - For HTTPS: obtain certs (e.g. Let’s Encrypt) and place them in `infrastructure/proxy/nginx/ssl/`
   - Uncomment and adjust the HTTPS server block in `proxy/nginx/conf.d/default.conf`
   - Restart: `docker compose -f infrastructure/docker-compose.yml restart proxy`

6. **Start the stack**
   - `docker compose -f infrastructure/docker-compose.yml up -d --build`
   - Set `ALLOWED_ORIGINS` to your domain(s), e.g. `https://seu-dominio.com`

7. **Backups**
   - The `backup` service runs hourly and keeps PostgreSQL dumps in the `backups` volume
   - Copy backups off the server (e.g. cron + rsync or cloud storage) as needed

## Security notes

- PostgreSQL and Redis are bound to `127.0.0.1` or only on the Docker network; the only public entry is the nginx proxy (80/443).
- Use a strong `JWT_SECRET` and DB password in production.
- **SSH:** use only public key authentication (see `ssh/README.md` and `configure-key-only.sh`).
- Restrict SSH (and optionally admin IPs) via UFW as described in `firewall/README.md`.
- Keep the system and Docker images updated.

## Backup

- **Location:** `backup/` (script + Dockerfile)
- **Schedule:** Container runs a backup every hour; files older than 48 hours are removed.
- **Volume:** Backups are stored in the Docker volume `backups`. To extract:  
  `docker run --rm -v abrigo_backups:/backups -v $(pwd):/out alpine sh -c "cp /backups/backup_*.sql.gz /out"`
