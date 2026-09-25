# syntax=docker/dockerfile:1.7

# =============================================================================
# Chimney Online Store — combined single-image build (frontend + backend)
#
# Build context MUST be the parent dir that contains BOTH repos:
#   /Side/
#     ├── chimney-online-store-frontend/
#     ├── chimney-online-store-backend/
#     └── chimney-deploy/            <- this Dockerfile lives here
#
# Build (from /Side):
#   docker build -f chimney-deploy/Dockerfile -t chimney-app:local .
# Or just use chimney-deploy/build.sh which sets the context for you.
# =============================================================================


# -----------------------------------------------------------------------------
# Stage 1 — build the Next.js frontend
# NEXT_PUBLIC_* are baked into the client bundle at build time (they are NOT
# secrets — they are visible to every visitor). Pass them as --build-arg.
# -----------------------------------------------------------------------------
FROM node:20-alpine AS frontend-builder

WORKDIR /fe

# Public (non-secret) build-time config for the frontend.
# Defaults target the same-origin nginx routing used in this image.
ARG NEXT_PUBLIC_SITE_URL=http://localhost:8080
# Must be an ABSOLUTE url that resolves BOTH from the browser AND from the Node
# server (SSR). Some services prefix this value directly, so a relative "/backend"
# breaks SSR (Node needs absolute) and pointing at 127.0.0.1:8000 breaks the
# browser (that port isn't exposed). The single value that works for both is the
# PUBLIC origin + /api/v1, proxied by nginx to the backend:
#   - browser: http://localhost:8080/api/v1/... -> nginx -> backend
#   - SSR:     same url, container reaches itself via nginx -> backend
# For a real deploy set this to https://YOUR_DOMAIN/api/v1.
ARG NEXT_PUBLIC_API_URL=http://localhost:8080/api/v1
ARG NEXT_PUBLIC_MEDIA_URL=/media
ARG NEXT_PUBLIC_MEDIA_HOST=localhost
ARG NEXT_PUBLIC_MEDIA_PATH=/media
ARG NEXT_PUBLIC_MEDIA_PORT=8080
ARG NEXT_PUBLIC_MEDIA_SCHEMA=http
ARG NEXT_PUBLIC_MEDIA_ITEMS=uploads
ARG NEXT_PUBLIC_MEDIA_CATEGORIES=categories

ENV NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL \
    NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL \
    NEXT_PUBLIC_MEDIA_URL=$NEXT_PUBLIC_MEDIA_URL \
    NEXT_PUBLIC_MEDIA_HOST=$NEXT_PUBLIC_MEDIA_HOST \
    NEXT_PUBLIC_MEDIA_PATH=$NEXT_PUBLIC_MEDIA_PATH \
    NEXT_PUBLIC_MEDIA_PORT=$NEXT_PUBLIC_MEDIA_PORT \
    NEXT_PUBLIC_MEDIA_SCHEMA=$NEXT_PUBLIC_MEDIA_SCHEMA \
    NEXT_PUBLIC_MEDIA_ITEMS=$NEXT_PUBLIC_MEDIA_ITEMS \
    NEXT_PUBLIC_MEDIA_CATEGORIES=$NEXT_PUBLIC_MEDIA_CATEGORIES \
    NEXT_TELEMETRY_DISABLED=1

# Install deps first (better layer caching)
COPY chimney-online-store-frontend/package.json chimney-online-store-frontend/package-lock.json ./
RUN npm ci

# Copy source and build
COPY chimney-online-store-frontend/ ./
RUN npm run build \
 && npm prune --omit=dev


# -----------------------------------------------------------------------------
# Stage 2 — build backend python dependencies (wheels via poetry)
# Mirrors chimney-online-store-backend/Dockerfile (alpine + poetry, main only)
# -----------------------------------------------------------------------------
FROM python:3.12-alpine AS backend-builder

WORKDIR /be

RUN apk add --no-cache --virtual .build-deps gcc musl-dev libpq-dev python3-dev

COPY chimney-online-store-backend/pyproject.toml chimney-online-store-backend/poetry.lock* ./
RUN pip install --upgrade pip && pip install poetry \
 && poetry config virtualenvs.create false \
 && poetry install --no-root --no-interaction --no-ansi --only main


# -----------------------------------------------------------------------------
# Stage 3 — final runtime image
# Contains: python backend + node runtime for `next start` + nginx + supervisord
# nginx is the only public port (8080). It routes:
#   /backend/*  -> backend  (rewritten to /api/v1/*)
#   /media/*    -> backend
#   /api/docs   -> backend  (swagger)
#   everything else -> Next.js (:3000)
# -----------------------------------------------------------------------------
FROM python:3.12-alpine

# Runtime OS deps:
#   libmagic/file/libpq  -> backend needs these (python-magic, asyncpg/libpq)
#   nodejs/npm           -> run the already-built Next.js app
#   nginx                -> reverse proxy / single public port
#   supervisor           -> run + supervise the 3 processes, logs to stdout
#   tini                 -> proper PID 1 / signal handling
RUN apk add --no-cache \
    libmagic file libpq \
    nodejs npm \
    nginx \
    supervisor \
    tini

WORKDIR /app

# --- Backend ---
# Python site-packages + console scripts (uvicorn/gunicorn/alembic) from builder
COPY --from=backend-builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=backend-builder /usr/local/bin /usr/local/bin
# Backend source (includes app/certificates/*.pem, alembic.ini, migrations)
COPY chimney-online-store-backend/ /app/backend/
# Backend startup script (migrations + gunicorn)
COPY chimney-deploy/start-backend.sh /app/backend/start-backend.sh
RUN chmod +x /app/backend/start-backend.sh

# --- Frontend ---
# Built Next.js app + node_modules (pruned to prod) + config needed by `next start`
COPY --from=frontend-builder /fe /app/frontend/

# --- Process/reverse-proxy config ---
COPY chimney-deploy/nginx.conf /etc/nginx/nginx.conf
COPY chimney-deploy/supervisord.conf /etc/supervisord.conf

# nginx runtime dirs
RUN mkdir -p /run/nginx

# Public port exposed by nginx (Koyeb maps this)
EXPOSE 8080

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
