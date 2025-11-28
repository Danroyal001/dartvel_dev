
# Troubleshooting — dartvel v0.1

## Router not updating
- Re-run `dartvel routes` after adding/renaming pages or changing config.
 - Check for route conflicts with `dartvel doctor` (will list files mapping to the same route).

## 404 / wrong route
- Ensure file name ends with `.page.dart` and class ends with `Page` and **extends `DartvelPage`**.
- Check dynamic segments: `[id]` becomes `:id`, `[...slug]` becomes `*slug`.

## API calls fail in dev
- Use the right dev host: Android emulator needs `http://10.0.2.2:<port>`, iOS Simulator can use `http://localhost:<port>`.
- Confirm your backend is running and listening on `backendHost:backendPort`.
 - You can set `DARTVEL_BACKEND_URL` at build time to force a specific base URL.

## CORS errors
- Add `cors()` middleware; dartvel_shelf will map this hint to native CORS when supported.

## Production build points to wrong API
- Set `prodBackendHost` and rebuild. You can override at build time:
```bash
flutter build web --dart-define=DARTVEL_BACKEND_URL=https://staging.example.com
```
 
## Env values not available in Flutter
- Ensure your `.env` is listed under `dartvel.envFiles` (defaults: `.env`, `.env.local`).
- Only keys prefixed with `PUBLIC_` are exported to `lib/dartvel_client/env.g.dart`.
