#!/usr/bin/env bash
set -euo pipefail

if command -v mkcert >/dev/null 2>&1; then
  echo "Using mkcert to create locally-trusted certs..."
  mkcert -install
  mkcert -key-file key.pem -cert-file cert.pem localhost 127.0.0.1 ::1 0.0.0.0
  echo "Wrote cert.pem and key.pem (trusted by your system CA)"
else
  echo "mkcert not found. Falling back to OpenSSL self-signed certificate."
  openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 365 -subj "/CN=localhost"
  echo "Wrote self-signed cert.pem and key.pem (browsers may warn)."
fi
