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
`https://enkapp-telemetry.exe.xyz/api/har`.

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
