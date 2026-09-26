# dartvel_cli

The `dartvel` command for [Dartvel](https://dartvel.dev), a full-stack
application platform built around Flutter.

It is the one code generator (`dartvel routes`), the development server with
hot reload across the Flutter app and its backend, the build for every target
Dartvel supports, deployment to web hosts and app stores, and the tools around
a running application: database migrations, queues, cache, logs, a task runner
and a cross-platform shell.

This package is the command. The framework an application imports is
[`dartvel_core`](https://pub.dev/packages/dartvel_core) and
[`dartvel_flutter`](https://pub.dev/packages/dartvel_flutter), or all of it at
once through [`dartvel_dev`](https://pub.dev/packages/dartvel_dev).

## Install

Install the CLI from pub.dev, or as a self-contained executable with the Dart
runtime and the Rust server library linked into it, which needs neither Dart
nor Flutter to run. Building an application still needs Flutter, for whichever
target you are building.

### From pub

With the Dart SDK installed (it ships with Flutter):

```sh
dart pub global activate dartvel_cli
dartvel --help
```

Activate `dartvel_cli`, the command. Activating `dartvel_dev` instead succeeds
and then every run fails, because `dartvel_dev` is the package an application
depends on, it depends on Flutter, and pub does not run a global command from a
package that does. Pub puts `dartvel` in `~/.pub-cache/bin`; add that to your
PATH if your shell cannot find it.

### Homebrew

```sh
brew install Danroyal001/dartvel_dev/dartvel_dev
```

The [tap](https://github.com/Danroyal001/homebrew-dartvel_dev) installs the
same prebuilt binary. It is bumped after a release, so it can trail npm.

### GitHub releases

Each release at
[github.com/Danroyal001/dartvel_dev/releases](https://github.com/Danroyal001/dartvel_dev/releases)
carries one binary per platform, with `SHA256SUMS` and `latest.json`:

| Asset | Platform |
|---|---|
| `dartvel-linux-amd64` | Linux x64 |
| `dartvel-linux-arm64` | Linux arm64 |
| `dartvel-darwin-amd64` | macOS Intel |
| `dartvel-darwin-arm64` | macOS Apple silicon |
| `dartvel-windows-amd64.exe` | Windows x64 |

There is no Windows on ARM build; the x64 one runs under emulation.

```sh
curl -LO https://github.com/Danroyal001/dartvel_dev/releases/download/v0.6.0/dartvel-linux-amd64
mkdir -p ~/.dartvel/bin
mv dartvel-linux-amd64 ~/.dartvel/bin/dartvel
chmod +x ~/.dartvel/bin/dartvel
~/.dartvel/bin/dartvel ensure-path   # adds ~/.dartvel/bin to your PATH
```

**For 0.6.0, only the Linux binaries are attached until the CI release
workflow has run.** Until then, npm on macOS or Windows fails on the download
and prints the release URL. Use the per-project route below on those hosts,
or 0.5.0.

### From pub, per project

With the Dart SDK installed, the CLI can run from a project's own
dependencies. `dartvel create` already writes this:

```yaml
dev_dependencies:
  dartvel_cli: ^0.6.0
```

```sh
dart run dartvel_cli:dartvel --help
dart run dartvel_cli:dartvel dev
```

The first `dart run` compiles the CLI, so it is slower than the binary.

`dartvel --version` prints the CLI version with the Dart, Flutter and
Shorebird it finds, so a missing toolchain shows up before a build fails on it.

### npm

```sh
npm install -g dartvel_dev      # or: npm install -g dartvel_cli
dartvel --help

npx dartvel_dev --help          # without installing
```

`dartvel_cli` on npm is an alias that forwards to `dartvel_dev`. The first time
it runs, the launcher downloads the binary for your platform from the GitHub
release of the same version, checks it against that release's `SHA256SUMS`,
and keeps it beside the package. Node 18 or newer.

## Quick start

```sh
dartvel create my_app          # alias: new
cd my_app
dartvel dev                    # generate, run the app and the backend, hot reload
dartvel build web              # production web build in build/web
dartvel deploy --target web --provider firebase-hosting
```

`dartvel dev` and `dartvel build` run the generator first, so you do not need
to run `dartvel routes` yourself. Run it when you want the generated client
(`lib/dartvel_client/`) refreshed without starting anything, for example so
the analyzer sees a new page.

To add Dartvel to a Flutter project that already exists, use `dartvel init`
rather than `create`. See [example/README.md](example/README.md) for a full
session: a new app, a page, a data model, the dev server and a web build.

## Commands

`dartvel --help` lists every command, and `dartvel help <command>` (or
`dartvel <command> --help`) shows its options.

### Projects

| Command | What it does |
|---|---|
| `create [dir]` | Scaffold a new project. Alias `new`. Refuses to write over a project it did not create. |
| `init` | Add Dartvel to an existing project: the dependency and the `dartvel:` key, nothing else. `--dry-run`, `--yes`. |
| `doctor` | Check the environment and the project. `--target <t>` checks one build target's toolchain. |
| `upgrade --plan` | Report what upgrading this project to this CLI's release changes. Writes nothing. |
| `migrate-code` | Rewrite deprecated Dartvel names. A dry run unless `--apply`. |
| `update` | Update the CLI itself. `--check` reports without installing. |
| `version` | Print the CLI version. |
| `ensure-path` | Add the `dartvel` binary's directory to your PATH. |

### Develop

| Command | What it does |
|---|---|
| `dev` | Run the app, the backend and Studio with hot reload. Aliases `run`, `start`. Prints a QR code that development builds pair with. |
| `routes` | Run the generator: routes, the typed client, models, backend glue. |
| `generate page\|model\|form\|backend-function <name>` | Write a starter file. `generate --check` fails when generated output is stale. |
| `test` | Run `dart test` or `flutter test`, with `--watch`, sharding and golden updates. |
| `preview` | Serve the production build locally. Also manages preview environments (`create`, `list`, `open`, `destroy`, `sweep`). |
| `inspect` | Print the project graph: `routes`, `models`, `functions`, `jobs` and more. `--json`. |
| `explain <code>` | Explain a diagnostic such as `DV-WINDOW-004`, or every code in a family. |
| `docs` | Build a documentation site for the application from its project graph. |
| `mcp` | Serve the project-graph inspectors to a coding agent over MCP. |
| `ai context\|doctor\|generate` | AI helpers. |
| `devtools` | Generate the devtools metadata pages. |

### Build

| Command | What it does |
|---|---|
| `build [platform]` | Build one target, or every target this host can build. See below. |
| `prerender` | Prerender routes to static HTML, with `sitemap.xml` and `robots.txt`. |
| `capture` | Photograph what a build rendered and fail on a blank one (`pages`, `firefox`, `pty`, `studio`, `pwa-sync`, `verify`). |
| `artifact split\|join` | Split a large artifact into committable chunks, or rejoin them. |
| `engine plan\|verify` | Resolve and verify a from-source Flutter engine build. |
| `webos verify-package` | Check an assembled webOS package. |

### Deploy and operate

| Command | What it does |
|---|---|
| `deploy` | Ship a web build or a server (`--provider`), or an app to a store (`--store`). |
| `key` | The application key (`generate`, `rotate`, `status`), and credentials kept in Dartvel Cloud (`cloud`). |
| `admin grant\|revoke\|list` | Say who may open Studio on a deployed application. `admin generate` writes the admin pages. |
| `updates release\|patch\|rollback` | Over-the-air updates through Shorebird, or a patch source you host. |
| `infra plan\|provision\|check` | Provision and check the hosts declared under `dartvel.infra`. |
| `compatibility-check` | Check the build's protocol against the clients an environment still serves. |
| `logs`, `traces`, `metrics` | Read a running server's recent logs, trace spans and `/metrics`. |
| `analyze performance` | Performance measurements from a running application. |

### Data and application services

| Command | What it does |
|---|---|
| `db migrate\|push\|pull\|seed` | Schema migrations and seeding. `migrate --plan` classifies each change without applying it. |
| `queue work\|failed\|retry\|flush` | Work and inspect job queues. |
| `cache clear\|inspect\|purge\|revalidate` | Inspect and revalidate the cache. |
| `privacy check\|export\|erase\|retention` | Subject paths, retention, and a subject's export or erasure. |
| `flags list\|prune` | Declared feature flags, and the ones past their expiry with the code still reading them. |
| `i18n extract\|check` | Collect translatable strings and check locale catalogues. |
| `import openapi\|postman` | Generate models and a typed client from an OpenAPI document or a Postman export. |
| `add <source>` | Resolve a capability source (a Dartvel project, an OpenAPI document, a GraphQL schema) into a mounted module. |
| `modules list\|manifest\|pin\|publish` | Inspect, pin, sign and publish modules. |
| `plugin add\|list\|remove` | Manage Dartvel plugins. |

### Scripts

| Command | What it does |
|---|---|
| `task <name>` | Run a task declared under `dartvel.tasks`. `--list` shows them. |
| `sh <command>` | Run a command with Dartvel's escaping, environment and glob handling, the same on every OS. |
| `spec status` | Summarise which parts of the specification are built. |

## Building

```sh
dartvel build                        # every target this host can build
dartvel build web
dartvel build web-server             # one executable: backend, web app and Studio
dartvel build android --format aab   # the App Bundle Google Play takes
dartvel build ios --format ipa       # the IPA App Store Connect takes
dartvel build android --profile development   # a build `dartvel dev` pairs with
```

`--profile` is `development` (Flutter debug, with dev-client pairing on
Android, iOS, macOS, Linux and Windows), `profile`, or `release` (the default).

Targets: `web`, `web-server`, `android`, `fireos`, `ios`, `macos`, `windows`,
`linux`, `tvos`, `tizen` (alias `tpk`), `sony-elinux` (with `--format bundle|iso|img`),
`webos`, `fuchsia`, `vscode`, `chrome-extension`, `firefox-extension`, and the
terminal targets `linux-cli`, `macos-cli`, `windows-cli` and `fuchsia-cli`
(each also spelled `-tui`).

Not all of these build today. `web`, `web-server`, `linux`, `android`,
`fireos`, `windows`, `macos`, `ios`, `vscode` and the two browser extensions
build and have been checked; `tvos` is verified for the simulator only; `tizen`
needs Tizen Studio installed by hand; `webos` skips because LG's toolchain
bundles a Dart too old for Dartvel; `fuchsia` is blocked. The per-target
evidence is in
[docs/build-targets.md](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/build-targets.md).

A build checks host support and the tools it needs before generating
anything, so it never starts something it cannot finish. Flutter has no
desktop cross-compilation: Windows builds need Windows and Apple targets need
macOS, and `dartvel build` skips what the host cannot build. Tools Dartvel can
fetch unattended (embedder forks, the webOS CLI, Linux desktop dependencies)
are installed under `~/.dartvel/toolchains/` after a prompt, or without one in
CI; `--auto-install` and `--no-auto-install` override that. Licence-gated SDKs
(Xcode, Visual Studio, the Android SDK, Tizen Studio) are never installed for
you; the build prints what to install instead.

`--cloud` sends the build to Dartvel Cloud, which needs a paid plan and a token
(`--cloud-token` or `DARTVEL_CLOUD_TOKEN`).

## Deploying

```sh
dartvel deploy --target web --provider vercel      # also firebase-hosting, netlify, cloudflare
dartvel deploy --target server                     # builds web-server; ship build/server yourself
dartvel deploy --functions --function-target cloud-run   # one artifact per backend function in build/deploy
dartvel deploy --store play --dry-run              # also appstore, testflight, firebase-app-distribution
```

`--target` defaults to `all`, which builds every platform the host can. Name
the target you mean. With no `--provider` the command builds and stops, and
you deploy from `build/` yourself. Secrets declared as required for the
`--environment` (default `production`) must resolve before anything ships.

Stores are declared under `dartvel.deploy.stores.<store>` in `pubspec.yaml`
and deploy an artifact you built first (`dartvel build android --format aab`,
`dartvel build ios --format ipa`).

## Configuration

The CLI reads the `dartvel:` section of the project's `pubspec.yaml`. Every key
is optional; `dartvel create` writes the common ones.

```yaml
dartvel:
  pagesDir: lib/pages
  backendDir: lib/backend
  backendPort: 3000
  devBackendHost: http://localhost:3000
  prodBackendHost: https://api.example.com
  apiBasePath: /api
  envFiles: [.env, .env.local]
  webPrerender: false
  ota: false
  transitions:
    default: fade
    durationMs: 200
    curve: easeInOut
  seo:
    siteName: My app
    defaultTitle: Welcome
    defaultDescription: A Dartvel application
```

| Key | Default | Meaning |
|---|---|---|
| `pagesDir` | `lib/pages` | Where file-based pages live. |
| `modelsDir` | `lib/models` | Where data models live. |
| `backendDir` | `lib/backend` | Where backend functions live. |
| `componentsDir`, `stylesDir`, `servicesDir` | `lib/components`, `lib/styles`, `lib/services` | Other source folders the generator reads. |
| `backendHost` | `0.0.0.0` | Address the development backend binds to. |
| `backendPort` | `3000` | Port of the development backend. |
| `devBackendHost` | `http://localhost:<backendPort>` | Backend URL the app calls in development. |
| `prodBackendHost` | empty | Backend URL the app calls in a release build. A `web-server` build calls its own origin instead. |
| `apiBasePath` | `/api` | Path prefix for backend functions. |
| `envFiles` | `[.env, .env.local]` | Environment files loaded, in order. `PUBLIC_` variables reach the client. |
| `seo` | empty | `siteName`, `defaultTitle`, `defaultDescription`, `defaultImage`, `twitterHandle`. |
| `transitions` | `fade`, `220`, `easeInOut` | Default page transition: `default`, `durationMs`, `curve`. |
| `routingNormalizeTrailingSlash` | `true` | Treat `/about/` as `/about`. |
| `notFoundRedirect` | empty | Where an unknown route redirects. |
| `plugins` | `[]` | Enabled Dartvel plugins. |
| `webPrerender` | `false` | Prerender pages on a web build. |
| `ota` | `false` | Over-the-air updates. |

Other sections are read by the commands that need them, for example
`tasks` (`dartvel task`), `database` (`provider`, `path`; used by `dartvel db`),
`deploy.stores` (`dartvel deploy --store`), `admin` (`enabled`, `path`, the
Studio mount, `/__studio` by default), `terminal` (link the terminal backend
into desktop builds), `modules`, `deviceProfiles` and `infra`.

```yaml
dartvel:
  tasks:
    lint: dart analyze
    gen: dartvel routes
```

## Code generation

Dartvel has one generator and it is this CLI. `dartvel routes` writes the
whole client under `lib/dartvel_client/`, including the
`dartvel_client.dart` barrel every page imports, and `dartvel dev` and
`dartvel build` run it before anything else. Output is byte-identical for
identical inputs, so `dartvel generate --check` can fail CI when committed
output is stale.

`dartvel_generator`'s `build_runner` builders are retired: they still run and
warn on every build, and are removed in `dartvel_generator` 2.0.0. Do not add
`build_runner` to an application for Dartvel's sake. `dartvel build` and
`dartvel dev` still run it, after Dartvel's own generation, when a project
declares it for another package's builders.

Routes are typed. Navigate with the generated `DVRoutes` members rather than
path strings:

```dart
context.navigateToPage(DVRoutes.about);
```

## doctor

```sh
dartvel doctor
dartvel doctor --target tizen
dartvel doctor --target android,ios
dartvel doctor --modules
```

Plain `doctor` checks Dart, Flutter and Git, lists optional tools (Shorebird,
Codemagic), checks the project (the `dartvel:` section, the Flutter
dependency, the configured pages, backend and models folders, `.env`) and then
prints `flutter doctor`. `[+]` passed, `[!]` needs attention, `[-]` is
information: a project with no models has no models folder, and that is fine.

`--target` checks one embedded, TV, extension or terminal target's toolchain,
or, for `android` and `ios`, the deep-link verification files your declared
domains serve. `--modules` verifies every module pin against what the
application grants.

## Troubleshooting

**`dartvel publish` is an unknown command.** It was removed in 0.6.0. Store
submission is `dartvel deploy --store play|appstore|testflight|firebase-app-distribution`,
and a `dartvel.publish:` block is refused, naming where each store moved under
`dartvel.deploy.stores`.

**`--release` or `--no-release` is a usage error on `build`.** Since 0.6.0 the
mode is `--profile development|profile|release`. `dartvel build dev-client` is
gone too: build `--profile development` for the platform instead.

**`dartvel create` refuses with `DV-ADOPT-005`.** The directory already holds a
`pubspec.yaml` that Dartvel did not write. Create into a new directory, or run
`dartvel init` to add Dartvel to that project.

**`flutter pub get failed` during `create`.** The scaffold is still written.
Fix what pub reports (usually network or an SDK older than Dart 3.12 /
Flutter 3.44) and run `flutter pub get` in the project.

**`dartvel build web` exits 1 with an accessibility finding.** A web build reads
each page's semantics tree and fails on a page a screen reader cannot use,
such as `page-heading` for a page with no level 1 heading. Give the page a
heading (`@DVPage(title: ..., showAppBar: true)` makes the bar title one, or
`DVText(...).modifier(const DVModifier().semanticHeading(1))`), or record a
documented exception under `dartvel.accessibility.waivers` as a list of
`route`, `rule` and `reason`. The files in
`build/web` are already written when the audit runs. `--no-prerender` skips
the audit along with the prerendered HTML, for a build nobody will serve.

**A target is skipped.** The host cannot build it, or a tool is missing. Run
`dartvel doctor --target <target>`; the skip message names the tool.

**`Target of URI doesn't exist: '../dartvel_client/dartvel_client.dart'`.** The
client has not been generated yet. Run `dartvel routes`.

**npm says `HTTP 404` fetching the binary.** That release carries no binary for
your platform. The error prints the release page; see the 0.6.0 note under
Install.

**A diagnostic code you do not recognise.** `dartvel explain DV-GEN-001`, or a
family: `dartvel explain DV-KIOSK`.

## 0.6.0 breaking changes

- `dartvel publish` is removed; use `dartvel deploy --store`. Stores are
  declared under `dartvel.deploy.stores`.
- `--provider firebase` is refused; Firebase Hosting is
  `--provider firebase-hosting`.
- `dartvel build --profile development|profile|release` replaces `--release`,
  `--no-release` and the old boolean `--profile`. `build dev-client` is gone.
- `dartvel init` adopts an existing project and is no longer an alias of
  `create`.
- `dartvel create` refuses to scaffold over a project it did not create.

The full list is in the [changelog](CHANGELOG.md).

## The name

`dartvel` on pub.dev was taken on 2026-08-06 by an unrelated package, so the
published identifiers carry a suffix: `dartvel_cli` for this package and
`dartvel_dev` for the umbrella on pub.dev, npm and Homebrew. The command is
`dartvel` however you install it.

## Links

- [dartvel.dev](https://dartvel.dev)
- [Repository](https://github.com/Danroyal001/dartvel_dev) and
  [getting started](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/getting-started.md)
- [Build targets and their evidence](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/build-targets.md)
- [What is built, per spec section](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json)
- [Releases](https://github.com/Danroyal001/dartvel_dev/releases)
- [Issues](https://github.com/Danroyal001/dartvel_dev/issues)
