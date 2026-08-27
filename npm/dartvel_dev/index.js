// A launcher, not a copy of the framework.
//
// Dartvel is a Dart toolchain: the `dartvel` command is a Dart executable
// published on pub.dev as `dartvel_dev`. Vendoring a compiled build of it into
// an npm package would ship a second copy that drifts from the one
// `dart pub global activate` installs, so this finds the real one, installs it
// on first use, and gets out of the way.
//
// The npm package exists because many people reach for `npx` before anything
// else, and because the name should belong to the project.
//
// The package is `dartvel_dev` and the command is `dartvel`. Those differ on
// purpose: `dartvel` was taken on pub.dev on 2026-08-06 by an unrelated
// package, so the published name carries the suffix while the thing you type
// does not.

'use strict';

const { spawn, spawnSync } = require('child_process');

/** The pub.dev package that carries the CLI. */
const PUB_PACKAGE = 'dartvel_dev';

/** The command that package installs. */
const COMMAND = 'dartvel';

/** Where to send someone who has no Dart at all. */
const INSTALL_DART = 'https://docs.flutter.dev/get-started/install';

function which(command) {
  const probe = spawnSync(
    process.platform === 'win32' ? 'where' : 'which',
    [command],
    { encoding: 'utf8' }
  );
  return probe.status === 0 && String(probe.stdout).trim().length > 0;
}

/** Whether the Dartvel CLI is already on the PATH. */
function hasDartvel() {
  return which(COMMAND);
}

/** Whether a Dart SDK is available to install it with. */
function hasDart() {
  return which('dart') || which('flutter');
}

function activate() {
  // Not silent: this downloads and compiles, and a launcher that appears to
  // hang is worse than one that says what it is doing.
  process.stderr.write(
    `${COMMAND} is not installed yet — running: ` +
      `dart pub global activate ${PUB_PACKAGE}\n`
  );
  const result = spawnSync('dart', ['pub', 'global', 'activate', PUB_PACKAGE], {
    stdio: 'inherit',
  });
  return result.status === 0;
}

/** Run the Dartvel CLI with `args`, resolving to its exit code. */
function run(args) {
  if (hasDartvel()) {
    return spawnThrough(COMMAND, args);
  }

  if (!hasDart()) {
    process.stderr.write(
      'Dartvel needs the Dart SDK, and there is no `dart` on your PATH.\n' +
        `Install Flutter, which includes Dart: ${INSTALL_DART}\n`
    );
    return Promise.resolve(1);
  }

  if (!activate()) {
    process.stderr.write(
      `Could not install ${PUB_PACKAGE} from pub.dev.\n` +
        `Try it directly: dart pub global activate ${PUB_PACKAGE}\n`
    );
    return Promise.resolve(1);
  }

  // `pub global activate` installs into ~/.pub-cache/bin, which is on the PATH
  // only if the user has put it there. Going through `dart pub global run`
  // works either way.
  return spawnThrough('dart', ['pub', 'global', 'run', PUB_PACKAGE, ...args]);
}

function spawnThrough(command, args) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { stdio: 'inherit' });
    child.on('error', (error) => {
      process.stderr.write(`Could not run ${command}: ${error.message}\n`);
      resolve(1);
    });
    child.on('close', (code) => resolve(code === null ? 1 : code));
  });
}

module.exports = { run, hasDartvel, hasDart, PUB_PACKAGE, COMMAND };
