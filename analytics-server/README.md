# enkapp analytics server

This compose stack runs the open-source server side for enkapp telemetry:

- Aptabase for anonymized product analytics.
- GlitchTip for Sentry-compatible manual error reporting and MetricKit diagnostics.
- Caddy for automatic HTTPS on both public domains.

## Deploy

1. Point two DNS records to the server:
   - `analytics.example.com`
   - `errors.example.com`
2. Copy `.env.example` to `.env` and replace all secrets and domains.
3. Start the stack:

```sh
docker compose up -d
```

On exe.dev, use the single-host override instead:

```sh
docker compose -f docker-compose.yml -f docker-compose.exe-dev.yml up -d
```

With the exe.dev override, Aptabase is served from the VM root URL and GlitchTip is served
under `/glitchtip`.

4. Open Aptabase, create an app, and copy its app key.
5. Open GlitchTip, create an organization/project, and copy the Sentry DSN.

## App build settings

Pass the server values into the iOS build without changing source files:

```sh
ENKAPP_APTABASE_APP_KEY=A-... \
ENKAPP_APTABASE_HOST=https://analytics.example.com \
ENKAPP_GLITCHTIP_DSN=https://...@errors.example.com/... \
ENKAPP_TELEMETRY_ENVIRONMENT=production \
xcodebuild -project encx-cli.xcodeproj -scheme encx-cli -configuration Release
```

Build a no-op analytics binary:

```sh
ENKAPP_SWIFT_ACTIVE_COMPILATION_CONDITIONS=ANALYTICS_DISABLED \
xcodebuild -project encx-cli.xcodeproj -scheme encx-cli -configuration Release
```

The app currently uses direct HTTP reporting instead of bundled analytics SDKs, so the
`ANALYTICS_DISABLED` build does not need external package resolution. This covers usage
events, manually captured errors, and iOS MetricKit diagnostic payloads delivered after
crashes/hangs. Full realtime native crash capture and dSYM symbolication would require adding
Sentry Cocoa back to the app target.
