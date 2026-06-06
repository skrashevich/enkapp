#!/bin/sh
set -eu

: "${ENKAPP_DOMAIN:=enkapp.svk.app}"
: "${ENKAPP_TEAM_ID:=ZLQX2C6SX2}"
: "${ENKAPP_APP_BUNDLE_ID:=com.svk-team.encx-cli}"
: "${ENKAPP_CLIP_BUNDLE_ID:=com.svk-team.encx-cli.Clip}"
: "${ENKAPP_APP_STORE_ID:=}"
: "${ENKAPP_TESTFLIGHT_URL:=https://testflight.apple.com/join/QVfQ5Hzf}"

export ENKAPP_DOMAIN
export ENKAPP_TEAM_ID
export ENKAPP_APP_BUNDLE_ID
export ENKAPP_CLIP_BUNDLE_ID
export ENKAPP_APP_STORE_ID
export ENKAPP_TESTFLIGHT_URL

envsubst < /usr/share/nginx/html/.well-known/apple-app-site-association.template \
    > /usr/share/nginx/html/.well-known/apple-app-site-association

smart_banner=""
if [ -n "$ENKAPP_APP_STORE_ID" ]; then
    smart_banner="<meta name=\"apple-itunes-app\" content=\"app-id=$ENKAPP_APP_STORE_ID, app-clip-bundle-id=$ENKAPP_CLIP_BUNDLE_ID\">"
fi
export ENKAPP_SMART_APP_BANNER="$smart_banner"

for page in index game; do
    envsubst < "/usr/share/nginx/html/$page.html.template" > "/usr/share/nginx/html/$page.html"
done
