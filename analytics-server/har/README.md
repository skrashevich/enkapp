# enkapp HAR telemetry

Small Go server for developer diagnostics.

Endpoints:

- `POST /api/har` accepts a raw HAR 1.2 JSON document from the mobile app.
- `GET /` lists received captures.
- `GET /sessions/{id}` shows requests and responses in a readable HTML view.
- `GET /sessions/{id}?raw=1` returns the original HAR JSON.

Run locally:

```sh
go run .
```

Configuration:

- `ADDR`, default `:8080`
- `DATA_DIR`, default `data`

The service expects TLS to be terminated by the public reverse proxy for
`https://enkapp-telemetry.exe.xyz/api/har`.
