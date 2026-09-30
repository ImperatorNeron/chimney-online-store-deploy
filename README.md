# chimney-deploy

Single-image deployment for the Chimney Online Store (frontend + backend in one
Docker image), designed for cheap single-service hosting (e.g. Koyeb) with
**all logs in one stream**.

This repo is **infrastructure only**. It does not copy or modify the two app
repos — it builds them using the sibling folders as build context.

```
/Side/
├── chimney-online-store-frontend/   # app repo (unchanged)
├── chimney-online-store-backend/    # app repo (unchanged)
└── chimney-deploy/                  # THIS repo
    ├── Dockerfile                   # multi-stage: FE build + BE deps + runtime
    ├── nginx.conf                   # single public port 8080, routes traffic
    ├── supervisord.conf             # runs backend + frontend + nginx, logs->stdout
    ├── start-backend.sh             # migrations + gunicorn (copied into image)
    ├── build.sh                     # builds with the correct context
    ├── push.sh                      # push to Docker Hub (when ready)
    ├── release.sh                   # scenario 3: build (+ push) prod image
    ├── run-local.sh                 # scenario 1: app + local DB
    ├── run-app-only.sh              # scenario 2: app + remote DB/bucket
    ├── docker-compose.local.yml     # scenario 1 compose (app + Postgres)
    ├── docker-compose.app-only.yml  # scenario 2 compose (app only)
    ├── scripts/
    │   ├── db-restore.sh            # restore a pg_dump into Railway Postgres
    │   └── upload-media.sh          # upload local media to the S3 bucket
    ├── .env.build.example           # BUILD-time frontend vars (NEXT_PUBLIC_*)
    ├── .env.local.example           # scenario 1 runtime vars
    └── .env.app-only.example        # scenario 2 runtime vars (secrets)
```

## Run scenarios (quick start)

First-time setup — copy the example env files and fill them in:

```bash
cp .env.build.example      .env.build        # build-time NEXT_PUBLIC_* (all scenarios)
cp .env.local.example      .env.local        # scenario 1
cp .env.app-only.example   .env.app-only     # scenario 2
# scenario 3 uses .env.build (+ runtime vars set on the host); see the
# "Deploy to Railway" section below for the full runtime var list
```

Real `.env.*` files are gitignored — only the `*.example` ones are committed.

### 1) Fully local — app + local DB, local creds
Starts the app AND a local Postgres together. Nothing external needed.
```bash
./run-local.sh            # build + up (Ctrl-C to stop)
./run-local.sh -d         # detached (background)
./run-local.sh --no-build # skip rebuild, just restart
```
App: http://localhost:8080

### 2) App local, EXTERNAL (prod) DB + bucket
Starts ONLY the app; it connects to your prod DB/bucket from `.env.app-only`.
No local DB is started.
```bash
./run-app-only.sh         # build + up
./run-app-only.sh -d      # detached
```
App: http://localhost:8080 (data comes from the real DB/bucket)

### 3) Clean production build — no app started
Builds (and optionally pushes) the image. Your host (Koyeb/Railway/…) runs it,
where you set the runtime env vars (see the "Deploy to Railway" section below).
Set `NEXT_PUBLIC_SITE_URL` in `.env.build` to your REAL domain first.
```bash
IMAGE=youruser/chimney-app TAG=v1 ./release.sh          # build only
IMAGE=youruser/chimney-app TAG=v1 ./release.sh --push   # build + push to registry
```

| Scenario | Script | App up? | DB | Creds |
|----------|--------|---------|-----|-------|
| 1 Fully local | `run-local.sh` | yes | local (started) | local |
| 2 App local + prod data | `run-app-only.sh` | yes | external (not started) | prod |
| 3 Prod build | `release.sh` | no (build/push only) | — | prod (on host) |

## Architecture

One container, three processes supervised by `supervisord`, all logging to
stdout/stderr so the cloud provider aggregates them into a single log stream:

- **nginx** — the only public port (`8080`). Routing:
  - `/backend/*` → backend (rewritten to `/api/v1/*`)
  - `/api/*`     → backend (Swagger at `/api/docs`)
  - `/media/*`   → backend
  - everything else → Next.js (`:3000`)
- **backend** — gunicorn + uvicorn workers on `127.0.0.1:8000` (prod mode)
- **frontend** — `next start` on `127.0.0.1:3000`

The frontend already calls the API same-origin via `/backend` (see the app's
`http.ts`), so there are effectively no cross-origin browser requests.

## Two kinds of env vars (important)

| Kind | Prefix | When | Secret? | Where to set |
|------|--------|------|---------|--------------|
| Frontend | `NEXT_PUBLIC_*` | **build time** (baked into JS bundle) | No — public | `--build-arg` (see `.env.build.example`) |
| Backend | `APP_CONFIG__*`, `RUN_MIGRATIONS`, ... | **runtime** | Yes (DB pass, storage key) | `.env.local` / `.env.app-only` locally; host env in prod |

You cannot change `NEXT_PUBLIC_*` after the image is built without rebuilding —
they are compiled into the client bundle. That's fine: they are not secrets.

## Security notes

- **No secrets in the image.** A `.dockerignore` at the build-context root
  (`/Side/.dockerignore`) excludes all `.env*`, `*.pem`/`*.key`/`*.crt`,
  `app/certificates/`, logs, caches, `.git`, dumps and build artifacts. The
  image contains code only.
- **JWT certificates are provided at runtime, not baked in.** Locally they are
  mounted read-only via the compose files. On the host, add them as
  mounted secret files and point the backend at them with:
  - `APP_CONFIG__AUTH_JWT__private_key_path=/path/to/private.pem`
  - `APP_CONFIG__AUTH_JWT__public_key_path=/path/to/public.pem`
  (or mount them at the default `app/certificates/{private,public}.pem`).
- **All runtime secrets go in the host env** (DB password, storage keys), never in
  the image or git.
- In `prod` the backend automatically sets the refresh cookie `Secure` +
  `HttpOnly`, with `SameSite=Lax`. The access token lives only in memory
  (never localStorage) and is sent via the `Authorization` header — so a
  separate CSRF token isn't required for this setup.
- Keep `APP_CONFIG__ALLOW_ORIGINS` scoped to your real domain (never `*`).
- nginx adds baseline security headers (nosniff, X-Frame-Options, HSTS,
  Referrer-Policy). Koyeb terminates TLS in front of the container.

## Build

From this folder (context is auto-detected as the parent `/Side`):

```bash
./build.sh                       # -> chimney-app:local (defaults, good for local test)
```

For a real deploy, bake your public URLs:

```bash
IMAGE=youruser/chimney-app TAG=v1 ./build.sh \
  --build-arg NEXT_PUBLIC_SITE_URL=https://shop.example.com \
  --build-arg NEXT_PUBLIC_API_URL=https://shop.example.com/api/v1 \
  --build-arg NEXT_PUBLIC_MEDIA_URL=/media \
  --build-arg NEXT_PUBLIC_MEDIA_SCHEMA=https \
  --build-arg NEXT_PUBLIC_MEDIA_HOST=shop.example.com \
  --build-arg NEXT_PUBLIC_MEDIA_PATH=/media
```

> Note: `NEXT_PUBLIC_API_URL` must be an **absolute** URL that resolves from
> BOTH the browser and the Node server (SSR). Several services prefix it
> directly, so a relative `/backend` breaks SSR and `127.0.0.1:8000` breaks the
> browser (that port isn't exposed). Use the public origin + `/api/v1`
> (`https://YOUR_DOMAIN/api/v1`); nginx proxies it to the backend. Locally use
> `http://localhost:8080/api/v1`.

## Test locally

Use the run scenarios above:
- `./run-local.sh` — app + a local Postgres 17 (with `pg_trgm`), no external deps.
- `./run-app-only.sh` — app against your real remote DB + bucket.

Open http://localhost:8080.

In production you won't use the bundled Postgres — point `APP_CONFIG__DATABASE__*`
at your managed DB (Railway / Neon / provider).

## Push (when ready)

```bash
docker login
IMAGE=youruser/chimney-app TAG=v1 ./push.sh
```

## The old workflow still works

Nothing here changes the original repos. You can still run the classic way:

```bash
# backend
cd ../chimney-online-store-backend && scons devup && scons migrate-up
# frontend
cd ../chimney-online-store-frontend && npm run dev
```

## Deploy to Railway

The app is ONE Docker image (frontend + backend + nginx on port 8080). On
Railway you run three things in one project: **this image**, a **Postgres**
service, and an **S3 Bucket** for media.

### Helper scripts (`scripts/`)

```bash
# Restore a pg_dump into the Railway Postgres (enables pg_trgm, --clean).
# Needs the DB's PUBLIC url (temporarily enable Public Networking on the DB).
./scripts/db-restore.sh "postgresql://postgres:PASS@HOST.proxy.rlwy.net:PORT/railway"
# (defaults to the newest *.dump in repo-root/dumps; pass a path as 2nd arg)

# Upload local media to the Railway S3 bucket (keys preserve folder structure).
# Reads S3 creds from .env.app-only (APP_CONFIG__S3__*). No secrets printed.
./scripts/upload-media.sh ~/Downloads/uploads uploads       # product images
./scripts/upload-media.sh ~/Downloads/categories categories # category images
```

### Build & push the image

```bash
# Set NEXT_PUBLIC_SITE_URL in .env.build to your real domain first.
IMAGE=youruser/chimney-app TAG=v1 ./release.sh --push
```
Then point the Railway app service at that image (or connect the repo and let
Railway build the Dockerfile).

### Runtime env vars to set on the Railway APP service

Media is served by the backend `/media` proxy (Railway buckets are PRIVATE).

```
APP_CONFIG__ENVIRONMENT=prod
APP_CONFIG__ALLOW_ORIGINS=https://YOUR_DOMAIN

# Session cookies: leave UNSET in real HTTPS prod (they default to Secure+HttpOnly).

# Database — use the INTERNAL host between Railway services (fast, free egress):
APP_CONFIG__DATABASE__driver=postgresql+asyncpg
APP_CONFIG__DATABASE__host=postgres.railway.internal
APP_CONFIG__DATABASE__port=5432
APP_CONFIG__DATABASE__user=postgres
APP_CONFIG__DATABASE__password=<from Postgres service>
APP_CONFIG__DATABASE__db_name=railway
APP_CONFIG__DATABASE__pool_size=5
APP_CONFIG__DATABASE__max_overflow=5
RUN_MIGRATIONS=0                 # DB already migrated; set 1 only for a fresh DB

# Storage: Railway S3 bucket (values from the bucket's Credentials tab)
APP_CONFIG__STORAGE_BACKEND=s3
APP_CONFIG__S3__endpoint=<ENDPOINT>
APP_CONFIG__S3__access_key_id=<ACCESS_KEY_ID>
APP_CONFIG__S3__secret_access_key=<SECRET_ACCESS_KEY>
APP_CONFIG__S3__bucket=<BUCKET>          # the unique S3 name, NOT the display name
APP_CONFIG__S3__region=auto
```

Build-time (baked into the image, set as `--build-arg` / in `.env.build`):
```
NEXT_PUBLIC_SITE_URL=https://YOUR_DOMAIN
NEXT_PUBLIC_MEDIA_URL=/media          # same-origin proxy (S3 backend)
NEXT_PUBLIC_MEDIA_PATH=/media
NEXT_PUBLIC_MEDIA_ITEMS=uploads
NEXT_PUBLIC_MEDIA_CATEGORIES=categories
```

### Certificates
The JWT keys (`app/certificates/*.pem`) are NOT baked into the image. On Railway,
provide them as mounted secret files at `/app/backend/app/certificates/` (same
paths the local compose files mount).
