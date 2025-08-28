
# Troubleshooting — dartvel v0.1

## Router not updating
- Re-run `dart run dartvel_cli:routes` after adding/renaming pages or changing config.

## 404 / wrong route
- Ensure file name ends with `.page.dart` and class ends with `Page` and **extends `DartvelPage`**.
- Check dynamic segments: `[id]` becomes `:id`, `[...slug]` becomes `*slug`.

## API calls fail in dev
- Use the right dev host: Android emulator needs `http://10.0.2.2:<port>`, iOS Simulator can use `http://localhost:<port>`.
- Confirm your backend is running and listening on `backendHost:backendPort`.

## CORS errors
- Add `cors()` middleware in your Shelf pipeline during development.

## Production build points to wrong API
- Set `prodBackendHost` and rebuild. You can override at build time:
  ```bash
  flutter build web --dart-define=DARTVEL_BACKEND_URL=https://staging.example.com
  ```
