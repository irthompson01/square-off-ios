#!/usr/bin/env bash
# Trusts the mkcert development CA inside an iOS simulator so the app can reach the docker
# backend at https://localhost:8002 (and wss://localhost:8002/ws). Run once per simulator.
#   scripts/trust-mkcert-simulator.sh            # the booted simulator
#   scripts/trust-mkcert-simulator.sh <UDID>     # a specific one
set -euo pipefail
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
command -v mkcert >/dev/null || { echo "mkcert is not installed (brew install mkcert)"; exit 1; }
CA="$(mkcert -CAROOT)/rootCA.pem"
[ -f "$CA" ] || { echo "No mkcert root CA at $CA (run: mkcert -install)"; exit 1; }
DEVICE="${1:-booted}"
xcrun simctl keychain "$DEVICE" add-root-cert "$CA"
echo "Trusted $CA in simulator '$DEVICE'. Pick 'Local docker' under Profile › Developer (or launch with -backend live)."
