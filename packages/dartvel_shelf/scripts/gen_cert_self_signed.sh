#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p certs
echo "==> Generating self-signed cert (dev ONLY)…"
openssl req -x509 -newkey rsa:2048 -nodes -keyout certs/privkey.pem -out certs/fullchain.pem -subj "/CN=localhost" -days 365
echo "certs/fullchain.pem and certs/privkey.pem generated."
