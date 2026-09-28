# dartvel_site

The source of https://dartvel.dev, built with Dartvel.

## How dartvel.dev is served

dartvel.dev runs on the binary `dartvel build web-server` writes, not on a
static `dartvel build web` bundle. The one binary carries the backend, the web
app and Studio, renders every page on request with its head, meta tags and
crawler text, and keeps its SQLite database in its data directory.

On the server:

| What | Where |
|---|---|
| systemd unit | `dartvel-site` (`Restart=always`, enabled at boot), running as the deploying user |
| Listens on | `127.0.0.1:8740`, behind nginx, which terminates TLS |
| Releases | `/srv/dartvel.dev/releases/<stamp>-<sha>/server`, newest five kept |
| Running release | `/srv/dartvel.dev/current`, a symlink swapped atomically |
| Data | `/srv/dartvel.dev/data` (`DARTVEL_DATA_DIR`): `data.db` holds the Studio account and its grant |
| Environment | `/srv/dartvel.dev/env` (mode 600), read by the unit |

Studio is at `/__studio`. `dartvel.admin.enabled: true` in `pubspec.yaml` puts
it in the release build, and it opens only for a signed-in person granted
`Studio.access`. Everybody else gets the same 404 as any path the site does not
serve, so the path does not confirm that Studio exists. The site's one account
page is the sign-in at `/login`; there is no sign-up page, and nginx refuses
`/api/auth/sign-up`, so nobody else can make an account here.

Granting and revoking, on the server:

```bash
dartvel admin grant <user-id> --database /srv/dartvel.dev/data/data.db
dartvel admin list --database /srv/dartvel.dev/data/data.db
dartvel admin revoke <user-id> --database /srv/dartvel.dev/data/data.db
```

### Deploying

From a checkout on the server:

```bash
tool/deploy_site_server.sh               # build, install, swap, restart, check
tool/deploy_site_server.sh --skip-build  # deploy the build/server already built
tool/deploy_site_server.sh --rollback    # back to the previous release
```

The script signals the unit's main process and systemd starts it again on the
new binary, so it needs no sudo. It then checks that the home page and
`/studio` render on the server, that `sitemap.xml` is served and that an
anonymous `/__studio/` answers 404, and swaps the previous release back in if
any of that fails.

The static bundle the site used to be served from is still at
`/var/www/dartvel.dev`. nginx keeps it as a rollback: the static server block
is `/etc/nginx/sites-available/dartvel.dev.static.conf`.

### CI

`.github/workflows/site.yml` builds the static bundle, checks every page's
crawler text and photographs every page, publishes that bundle to GitHub Pages,
and builds the web-server binary and checks that it renders pages and refuses
an anonymous Studio.

## Working on it

```bash
flutter pub get
dartvel dev
```

`pubspec_overrides.yaml` points the Dartvel packages at this repository's
working tree, so the site always shows what is about to ship.

The Studio screenshots in `assets/studio_shots/` are photographs of a running Studio;
see `.github/workflows/studio-shots.yml` and `dartvel capture studio`.
