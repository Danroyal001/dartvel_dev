# dartvel_shelf

WinterCG-first (Fetch-like) Shelf-style Dart API powered by Actix Web via **ffigen**-generated FFI. No IPC.

## Features
- HTTP/1.1 today; HTTP/2 automatically via ALPN when you pass TLS (Rustls 0.23).
- Default `/health` endpoint; `/healthz` and `/healths` redirect to `/health` (308).
- Shelf-like router on top of Fetch-style Request/Response/Headers.
- **Build hook** compiles Rust cdylib and runs **ffigen** to generate bindings on first `dart run/test`.

## Quick start

```bash
dart pub get
dart run example/hello.dart
# then in another terminal:
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8080/healthz
curl -i http://127.0.0.1:8080/hello
```

### HTTP/2 via TLS (ALPN)

Provide PEMs:

```dart
final certPem = await File('cert.pem').readAsString();
final keyPem  = await File('key.pem').readAsString();
await serve(app.call, host: '0.0.0.0', port: 8443,
  tls: TlsConfig(certPem: certPem, keyPem: keyPem));
```

Or plaintext H2C:

```dart
await serve(app.call, host: '0.0.0.0', port: 8080, h2c: true);
```

## Development
- Edit Rust C ABI in `rust/src/lib.rs`.
- Build hook runs `cargo build` (generating `include/dartvel_shelf.h` via `cbindgen`) and then runs `ffigen` to produce `lib/src/generated/bindings.dart` automatically whenever you run `dart test`/`dart run` in this package.


## HTTPS / HTTP/2 Demo

Create development certs (trusted via `mkcert` if available, else self-signed OpenSSL):

```bash
make gen-certs
# or:
# scripts/generate_dev_certs.sh
```

Run the HTTPS demo (serves on :8443, ALPN negotiates HTTP/2 automatically):

```bash
make run-https
# or
dart run example/https_demo.dart
```

Test:
```bash
curl -k https://127.0.0.1:8443/health
curl -k https://127.0.0.1:8443/hello
```
