# enkapp HAR telemetry

Small Go server for developer diagnostics.

Endpoints:

- `POST /api/har` accepts a raw HAR 1.2 JSON document from the mobile app.
- `GET /` lists received captures. Requires Basic Auth.
- `GET /sessions/{id}` shows requests and responses in a readable HTML view. Requires Basic Auth.
- `GET /sessions/{id}?raw=1` returns the original HAR JSON. Requires Basic Auth.
- `GET /api/state` returns live-update state for the viewer. Requires Basic Auth.
- `POST /api/sessions/share` creates a public share link for one session. Requires Basic Auth.
- `GET /share/{token}` shows a shared session without authentication.
- `GET /share/{token}?raw=1` returns the shared session HAR JSON without authentication.

Run locally:

```sh
go run .
```

Configuration:

- `ADDR`, default `:8080`
- `DATA_DIR`, default `data`
- `VIEW_USERNAME`, default `admin`
- `VIEW_PASSWORD`, required for viewer access

If `VIEW_PASSWORD` is not set, viewer endpoints fail closed with HTTP 503.
`POST /api/har` remains unauthenticated for mobile uploads.

The service expects TLS to be terminated by the public reverse proxy for
`https://telemetry.enkapp.svk.app/api/har`.

## Docker Compose

From the repository root:

```sh
cd analytics-server/har
cp .env.example .env
```

Set `VIEW_PASSWORD` in `.env` to a strong password (for example, generate one
with `openssl rand -hex 32`). Compose refuses to start with an empty password.
Then start the service with the prebuilt image from GHCR:

```sh
docker compose pull
docker compose up -d
docker compose logs -f telemetry
```

The image is published as `ghcr.io/skrashevich/enkapp/har-telemetry:latest`
(linux/amd64 and linux/arm64) by the `telemetry-docker` GitHub Actions
workflow on every push to `main` that touches `analytics-server/har/`. Set
`TELEMETRY_IMAGE` in `.env` to pin a specific tag. To build locally instead,
run `docker compose up -d --build`.

The viewer is available at `http://127.0.0.1:8080` with the credentials from
`.env`. By default the published port is accessible only on the Docker host.
Configure the host's HTTPS reverse proxy for `telemetry.enkapp.svk.app` to
forward to `http://127.0.0.1:8080`, preserving `Host` and setting
`X-Forwarded-Proto: https`. Allow request bodies of at least 25 MiB for HAR
uploads. If the proxy runs in a container, attach it to the Compose network
and use `http://telemetry:8080` as its upstream instead.

`PORT` and `BIND_ADDRESS` in `.env` override the published port and interface.
Use `BIND_ADDRESS=0.0.0.0` only when direct network access is intended.

Captures and share links persist in the `telemetry-data` named volume across
container rebuilds and `docker compose down`. Back up this volume; running
`docker compose down -v` deletes its data.

To update to the latest published image, run `docker compose pull && docker
compose up -d`. To stop the service, run `docker compose down`.

## Large session viewer

Session detail pages load entry summaries in batches of 50. Opening Request or
Response loads that entry's details once. HTML response previews create their
sandboxed iframe only when the HTML tab becomes active.

The viewer uses HTML fragments from the same detail URL:

- `?view=entries&offset=N` returns up to 50 entry summaries.
- `?view=request&entry=N` returns one zero-based request detail.
- `?view=response&entry=N` returns one zero-based response detail.

Private fragment requests require the same Basic Auth as `/sessions/{id}`.
Shared fragments are available only below the corresponding `/share/{token}`.
These fragment queries are viewer internals; `?raw=1` remains the stable raw
HAR download interface.
