#!/usr/bin/env bash
# Deploys dartvel.dev: builds the site as a web-server binary, installs it
# beside the previous ones, swaps it in atomically, restarts the service and
# checks that it serves. A release that does not answer is swapped back out.
# Every page in the sitemap (and an address nothing serves) is fetched before
# and after the switch: a changed status swaps the release back out, and each
# page whose text changed is printed. The previous release stays installed
# for --rollback.
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

# snapshot DIR: every page in the live sitemap, plus an address nothing serves,
# fetched as dartvel.dev; DIR/status.txt has "path code" per line and DIR/<n>.txt
# the visible text of each page (scripts, styles and tags removed).
snapshot() {
  local dir="$1" path n=0
  rm -rf "$dir"; mkdir -p "$dir"
  { curl -s -m 20 -H "Host: dartvel.dev" "$BASE/sitemap.xml" \
      | grep -o "<loc>[^<]*</loc>" | sed -E "s#</?loc>##g; s#^https?://[^/]+##; s#^\$#/#"
    echo "/__deploy-check-missing"; } | while read -r path; do
    n=$((n + 1))
    code="$(curl -s -m 30 -H "Host: dartvel.dev" -H "X-Forwarded-Proto: https" \
      -o "$dir/$n.html" -w "%{http_code}" "$BASE$path")"
    echo "$path $code" >> "$dir/status.txt"
    perl -0777 -pe 's/<script.*?<\/script>|<style.*?<\/style>/ /gis; s/<[^>]+>/ /g; s/\s+/ /g; s/(.{1,160})(\s|$)/$1\n/g' \
      "$dir/$n.html" > "$dir/$n.txt"
  done
}

# compare BEFORE AFTER: fails when any status changed; prints each page whose
# text changed, so the deploy shows exactly what it changed.
compare() {
  local before="$1" after="$2" n=0 path code changed
  if ! diff -q "$before/status.txt" "$after/status.txt" >/dev/null; then
    say "status changed:"; diff "$before/status.txt" "$after/status.txt" || true
    return 1
  fi
  while read -r path code; do
    n=$((n + 1))
    changed="$(diff "$before/$n.txt" "$after/$n.txt" | grep -c "^[<>]" || true)"
    [ "$changed" = 0 ] || { say "text changed on $path ($changed lines):"; diff "$before/$n.txt" "$after/$n.txt" | grep "^[<>]" | head -6 | cut -c1-200; }
  done < "$before/status.txt"
  say "$(wc -l < "$after/status.txt") addresses compared, statuses unchanged"
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
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
snapshot "$work/before"
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

# Before and after, page by page: a changed status is a regression and is
# swapped back out; changed text is printed for the deployer to read.
snapshot "$work/after"
if ! compare "$work/before" "$work/after"; then
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
say "live: $release on $BASE (rollback: ${before:-none}, or --rollback)"
