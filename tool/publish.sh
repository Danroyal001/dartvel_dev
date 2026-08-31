#!/usr/bin/env bash
#
# Publish Dartvel to pub.dev and npm.
#
# A script rather than a command to paste: the one-liner this replaces was long
# enough that a terminal wrapped it mid-subshell, so `cd` ran with no argument
# and bash tried to execute `packages/dartvel_core` as a program. Nothing was
# published and the failure did not look like a paste problem.
#
#   tool/publish.sh              publish everything that is behind
#   tool/publish.sh --dry-run    check everything, publish nothing
#   tool/publish.sh --yes        skip the confirmation prompt (for CI)
#
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# Dependency order, and it is load-bearing rather than tidy: shelf, flutter and
# generator each depend on core, cli depends on core and shelf, and dev depends
# on all of them. Publishing out of order fails to resolve, because the version
# a package names is not on pub.dev yet.
PUB_PACKAGES=(
  dartvel_core
  dartvel_shelf
  dartvel_flutter
  dartvel_generator
  dartvel_cli
  dartvel_dev
)

# dartvel_cli pins dartvel_dev exactly, so it is unresolvable until dev is up.
NPM_PACKAGES=(dartvel_dev dartvel_cli)

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
green(){ printf '\033[32m%s\033[0m\n' "$*"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }

fail() { red "✗ $*"; exit 1; }

local_pub_version()  { grep -m1 '^version:' "packages/$1/pubspec.yaml" | awk '{print $2}'; }
local_npm_version()  { node -p "require('./npm/$1/package.json').version"; }

# Empty when the package has never been published, which is not an error.
live_pub_version() {
  curl -fsS "https://pub.dev/api/packages/$1" 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).latest.version)}catch(e){}})' \
    2>/dev/null
}

live_npm_version() {
  curl -fsS "https://registry.npmjs.org/$1" 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s)["dist-tags"].latest)}catch(e){}})' \
    2>/dev/null
}

echo "── toolchain ───────────────────────────────────────────"

# Found rather than assumed. This Codespace has no system Dart, and the SDK
# lives on the one volume a rebuild keeps -- so a script that relies on the
# caller's PATH works for whoever set it up and for nobody else.
#
# The Flutter SDK's bin is preferred over a bare Dart, because dartvel_flutter
# is a Flutter package and resolving it needs the Flutter SDK.
if [[ -z "${FLUTTER_ROOT:-}" ]]; then
  for candidate in \
    /workspaces/.toolchains/flutter \
    "$HOME/.dartvel/toolchains/flutter" \
    "$HOME/flutter" \
    /opt/flutter
  do
    if [[ -x "$candidate/bin/dart" ]]; then
      FLUTTER_ROOT="$candidate"
      break
    fi
  done
fi

if [[ -n "${FLUTTER_ROOT:-}" && -x "$FLUTTER_ROOT/bin/dart" ]]; then
  PATH="$FLUTTER_ROOT/bin:$PATH"
  export PATH
  green "✓ dart $("$FLUTTER_ROOT/bin/dart" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) from $FLUTTER_ROOT"
elif command -v dart >/dev/null 2>&1; then
  green "✓ dart $(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) from $(command -v dart)"
else
  fail "no dart on PATH and no Flutter SDK found. Set FLUTTER_ROOT, or add the SDK's bin to PATH."
fi

command -v node >/dev/null 2>&1 || fail "node is required to read package versions"
command -v npm  >/dev/null 2>&1 || fail "npm is required to publish the npm packages"

echo
echo "── credentials ─────────────────────────────────────────"

# Checked before anything is published, not discovered at the last step. The
# run this replaces published five Dart packages' worth of nothing and then
# failed on npm with a 404, which is what npm returns instead of 403 so as not
# to confirm a package exists to someone who cannot write to it.
PUB_CREDS="${PUB_CACHE:-$HOME/.pub-cache}/credentials.json"
if [[ -f "$HOME/.config/dart/pub-credentials.json" || -f "$PUB_CREDS" ]]; then
  green "✓ pub.dev credentials present"
else
  fail "not logged in to pub.dev — run: dart pub login"
fi

NPM_USER="$(npm whoami 2>/dev/null)"
if [[ -n "$NPM_USER" ]]; then
  green "✓ npm logged in as $NPM_USER"
else
  fail "not logged in to npm — run: npm login"
fi

echo
echo "── versions ────────────────────────────────────────────"

PUB_TODO=()
for p in "${PUB_PACKAGES[@]}"; do
  want="$(local_pub_version "$p")"
  have="$(live_pub_version "$p")"
  if [[ "$want" == "$have" ]]; then
    dim "  $p $want — already published, skipping"
  else
    printf '  %-20s %s → %s\n' "$p" "${have:-none}" "$want"
    PUB_TODO+=("$p")
  fi
done

NPM_TODO=()
for p in "${NPM_PACKAGES[@]}"; do
  want="$(local_npm_version "$p")"
  have="$(live_npm_version "$p")"
  if [[ "$want" == "$have" ]]; then
    dim "  npm/$p $want — already published, skipping"
  else
    printf '  %-20s %s → %s\n' "npm/$p" "${have:-none}" "$want"
    NPM_TODO+=("$p")
  fi
done

if [[ ${#PUB_TODO[@]} -eq 0 && ${#NPM_TODO[@]} -eq 0 ]]; then
  echo
  green "Everything is already published."
  exit 0
fi

echo
echo "── dry run ─────────────────────────────────────────────"

# Every package is checked before any is published. A failure found halfway
# through leaves the registry holding some of a release, and a version cannot
# be republished once it is taken.
WARNED=()
for p in "${PUB_TODO[@]}"; do
  out="$(dart pub publish --dry-run -C "packages/$p" 2>&1)"
  summary="$(echo "$out" | grep -oE 'Package has [0-9]+ warning.*' | tail -1)"

  # Not the exit code. `dart pub publish --dry-run` exits non-zero for a
  # warning as well as for an error, and the real publish below passes
  # --force, which goes ahead anyway -- so gating on the exit code means this
  # script can never run while any warning stands. The summary line is what
  # distinguishes "would not publish" from "would publish, with something
  # worth reading first".
  if [[ -z "$summary" ]]; then
    echo "$out" | tail -20
    fail "$p would not publish"
  fi

  if [[ "$summary" == *"0 warning"* ]]; then
    green "✓ $p — $summary"
  else
    red "! $p — $summary"
    WARNED+=("$p")
    # The headline of each warning, not the paragraph under it. The one that
    # stands today is dartvel_flutter depending on a pre-release of mix, and
    # it is worth seeing rather than scrolling past.
    echo "$out" | grep -E '^\* ' | sed 's/^/    /'
  fi
done

for p in "${NPM_TODO[@]}"; do
  if out="$(npm publish "./npm/$p" --dry-run 2>&1)"; then
    green "✓ npm/$p"
    echo "$out" | grep 'npm warn' | sed 's/^/    /'
  else
    echo "$out" | tail -20
    fail "npm/$p would not publish"
  fi
done

if [[ ${#WARNED[@]} -gt 0 ]]; then
  echo
  red "Warnings stand on: ${WARNED[*]}"
  red "--force publishes past them. Read them above before continuing."
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  green "Dry run only. Nothing was published."
  exit 0
fi

echo
echo "── publish ─────────────────────────────────────────────"
red "This cannot be undone. pub.dev allows unpublishing only within 7 days,"
red "and a version number can never be reused."
echo

if [[ $ASSUME_YES -eq 0 ]]; then
  read -r -p "Publish ${#PUB_TODO[@]} pub package(s) and ${#NPM_TODO[@]} npm package(s)? [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "Cancelled."; exit 1; }
fi

for p in "${PUB_TODO[@]}"; do
  echo
  echo "→ $p"
  # Stops here rather than continuing: the packages after this one depend on
  # it, and publishing them against a version that never landed produces a
  # release nobody can install.
  dart pub publish --force -C "packages/$p" || fail "$p failed to publish"
  green "✓ $p published"
done

for p in "${NPM_TODO[@]}"; do
  echo
  echo "→ npm/$p"
  npm publish "./npm/$p" || fail "npm/$p failed to publish"
  green "✓ npm/$p published"
done

echo
green "Done."
