# enkapp App Clip site

Static nginx container for `enkapp.svk.app`.

It serves:

- `/.well-known/apple-app-site-association`
- `/apple-app-site-association`
- `/g/*` fallback pages for App Clip and universal link invocations
- `/healthz`

Build and run locally:

```sh
docker build -t enkapp-appclip-site web/appclip-site
docker run --rm -p 8080:80 enkapp-appclip-site
curl -i http://127.0.0.1:8080/.well-known/apple-app-site-association
```

Optional environment:

```sh
ENKAPP_APP_STORE_ID=1234567890
ENKAPP_TESTFLIGHT_URL=https://testflight.apple.com/join/QVfQ5Hzf
```

`ENKAPP_APP_STORE_ID` enables the Smart App Banner meta tag. Leave it empty until the App Store Connect app has an Apple ID.
