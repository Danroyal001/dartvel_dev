#!/usr/bin/env bash
# Deploys dartvel.dev: builds the site as a web-server binary, installs it
# beside the previous ones, swaps it in atomically, restarts the service and
# checks that it serves. A release that does not answer is swapped back out.
#
#   tool/deploy_site_server.sh               build, then deploy
#   tool/deploy_site_server.sh --skip-build  deploy sites/dartvel_site/build/server as it is
#   tool/deploy_site_server.sh --rollback    go back to the previous release
#
# Layout under $DARTVEL_SITE_ROOT (default /srv/dartvel.dev):
#
#   releases/<stamp>-<sha>/server   every release installed, newest five kept
#   current -> releases/...         what the service runs
#   data/                           DARTVEL_DATA_DIR: the SQLite database with
#                                   the Studio account and grant; never touched
#
# The service is the systemd unit dartvel-site (Restart=always). The script
# restarts it by signalling its main process, which the unit's own user may
# do, so a deploy needs no sudo: systemd starts the process again, on the
# binary `current` now points at.
set -euo pipefail

ROOT="${DARTVEL_SITE_ROOT:-/srv/dartvel.dev}"
PORT="${DARTVEL_SITE_PORT:-8740}"
UNIT="${DARTVEL_SITE_UNIT:-dartvel-site}"
KEEP=5
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE="$REPO/sites/dartvel_site"
BASE="http://127.0.0.1:$PORT"

say() { printf 'deploy: %s\n' "$*"; }
die() { printf 'deploy: %s\n' "$*" >&2; exit 1; }

restart() {
  local pid
  pid="$(systemctl show -p MainPID --value "$UNIT" 2>/dev/null || echo 0)"
  if [ "${pid:-0}" != 0 ]; then
    kill -TERM "$pid"
    # Wait for that process to go, so the check below is of the new one.
    for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  else
    systemctl start "$UNIT" 2>/dev/null || sudo -n systemctl start "$UNIT"
  fi
}

healthy() {
  local i
  for i in $(seq 1 90); do
    curl -sf -o /dev/null "$BASE/sitemap.xml" && break
    sleep 1
  done
  # Every page in the sitemap rendered on the server with its title, meta
  # description and crawler text; Studio answering a stranger as an unknown
  # path; the image endpoint resizing.
  dart "$REPO/tool/ci/server_pages_check.dart" "$BASE"
}

activate() {
  # A symlink replaced by rename is never missing, even for an instant.
  ln -sfn "$1" "$ROOT/current.next"
  mv -Tf "$ROOT/current.next" "$ROOT/current"
}

previous_release() {
  local now
  now="$(readlink -f "$ROOT/current" || true)"
  ls -1d "$ROOT"/releases/*/ 2>/dev/null | sed 's#/$##' | sort | grep -vxF "$now" | tail -1
}

mode=deploy
case "${1:-}" in
  --skip-build) mode=skip-build ;;
  --rollback) mode=rollback ;;
  "") ;;
  *) die "unknown option $1" ;;
esac

[ -d "$ROOT/releases" ] || die "$ROOT/releases does not exist; see sites/dartvel_site/README.md"

if [ "$mode" = rollback ]; then
  prev="$(previous_release)"
  [ -n "$prev" ] || die "no earlier release to go back to"
  say "rolling back to $prev"
  activate "$prev"
  restart
  healthy || die "the previous release does not answer either"
  say "rolled back"
  exit 0
fi

if [ "$mode" = deploy ]; then
  say "building the site as a web-server binary"
  (cd "$SITE" && flutter pub get >/dev/null && dart run dartvel_cli:dartvel build web-server)
fi
[ -x "$SITE/build/server" ] || die "no $SITE/build/server"

sha="$(git -C "$REPO" rev-parse --short=8 HEAD)"
release="$ROOT/releases/$(date -u +%Y%m%d%H%M%S)-$sha"
mkdir -p "$release"
cp "$SITE/build/server" "$release/server.tmp"
chmod 755 "$release/server.tmp"
mv "$release/server.tmp" "$release/server"

before="$(readlink -f "$ROOT/current" || true)"
say "installing $release"
activate "$release"
restart
if ! healthy; then
  say "the new release failed its checks"
  journalctl -u "$UNIT" -n 30 --no-pager 2>/dev/null || true
  if [ -n "$before" ]; then
    say "swapping back to $before"
    activate "$before"
    restart
    healthy || say "the previous release does not answer either"
  fi
  exit 1
fi

# The newest $KEEP releases stay, and always the one running.
ls -1d "$ROOT"/releases/*/ | sed 's#/$##' | sort | head -n -"$KEEP" | while read -r old; do
  [ "$old" = "$(readlink -f "$ROOT/current")" ] || rm -rf "$old"
done
say "live: $release on $BASE"
