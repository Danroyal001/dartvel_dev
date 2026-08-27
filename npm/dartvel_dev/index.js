// Fetches the self-contained `dartvel` binary for this platform and runs it.
//
// The CLI is a Dart program, but it does not need a Dart SDK to run: `dart
// build cli` links the Dart runtime and dartvel_shelf's Rust library into one
// executable. So this package downloads that executable rather than requiring
// a toolchain.
//
// It used to run `dart pub global activate` instead, and that could not work.
// The umbrella depends on the Flutter SDK and pub refuses to run a global
// executable from a package that does — it activated and then would not run,
// which looks installed and is not:
//
//   dartvel_dev as globally activated requires the Flutter SDK, which is
//   unsupported for global executables
//
// Building the CLI still needs Flutter, for whichever target you are building.
// Running the CLI does not.

'use strict';

const fs = require('fs');
const https = require('https');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

const VERSION = require('./package.json').version;
const REPO = 'Danroyal001/dartvel_dev';
const RELEASE_BASE = `https://github.com/${REPO}/releases/download/v${VERSION}`;

/**
 * The release asset for a platform.
 *
 * Named for the operating system and architecture rather than Node's own
 * spellings, because the release is what has to be matched.
 */
function assetName(platform = process.platform, arch = process.arch) {
  const osName = { linux: 'linux', darwin: 'darwin', win32: 'windows' }[platform];
  if (!osName) {
    throw new Error(
      `Dartvel has no build for ${platform}. Supported: Linux, macOS, Windows.`
    );
  }

  const archName = { x64: 'amd64', arm64: 'arm64' }[arch];
  if (!archName) {
    throw new Error(
      `Dartvel has no build for ${arch}. Supported: x64, arm64.`
    );
  }

  // Windows on ARM is not published yet, and saying so beats a 404 from a URL
  // this would otherwise construct confidently.
  if (osName === 'windows' && archName === 'arm64') {
    throw new Error(
      'Dartvel has no Windows on ARM build yet. The x64 build runs under ' +
        'emulation; install it directly from the releases page.'
    );
  }

  return `dartvel-${osName}-${archName}${osName === 'windows' ? '.exe' : ''}`;
}

/** Where the downloaded binary is kept, beside this package. */
function binaryPath() {
  const name = process.platform === 'win32' ? 'dartvel.exe' : 'dartvel';
  return path.join(__dirname, 'vendor', name);
}

function download(url, redirectsLeft = 5) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { 'user-agent': 'dartvel-npm' } }, (response) => {
        const status = response.statusCode || 0;
        if (status >= 300 && status < 400 && response.headers.location) {
          if (redirectsLeft <= 0) {
            reject(new Error('too many redirects'));
            return;
          }
          response.resume();
          resolve(download(response.headers.location, redirectsLeft - 1));
          return;
        }
        if (status !== 200) {
          response.resume();
          reject(new Error(`HTTP ${status} for ${url}`));
          return;
        }
        const chunks = [];
        response.on('data', (chunk) => chunks.push(chunk));
        response.on('end', () => resolve(Buffer.concat(chunks)));
        response.on('error', reject);
      })
      .on('error', reject);
  });
}

/**
 * Fetch the binary if it is not already here.
 *
 * The checksum published alongside the release is verified before anything is
 * made executable. A truncated download otherwise becomes a binary that fails
 * in a way that looks like a bug in the tool.
 */
async function ensureBinary() {
  const target = binaryPath();
  if (fs.existsSync(target)) return target;

  const asset = assetName();
  process.stderr.write(`Fetching ${asset} ${VERSION}…\n`);

  const binary = await download(`${RELEASE_BASE}/${asset}`);

  let expected = null;
  try {
    const sums = (await download(`${RELEASE_BASE}/SHA256SUMS`)).toString('utf8');
    for (const line of sums.split('\n')) {
      const [digest, name] = line.trim().split(/\s+/);
      if (name === asset) expected = digest;
    }
  } catch {
    // A release without a checksum file is still installable; say so rather
    // than refusing, and never claim it was verified.
    process.stderr.write('No SHA256SUMS published for this release; skipping verification.\n');
  }

  if (expected) {
    const actual = crypto.createHash('sha256').update(binary).digest('hex');
    if (actual !== expected) {
      throw new Error(
        `Checksum mismatch for ${asset}.\n  expected ${expected}\n  got      ${actual}`
      );
    }
  }

  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, binary, { mode: 0o755 });
  return target;
}

/** Run the CLI with `args`, resolving to its exit code. */
async function run(args) {
  let binary;
  try {
    binary = await ensureBinary();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.stderr.write(
      `Releases: https://github.com/${REPO}/releases/tag/v${VERSION}\n`
    );
    return 1;
  }

  return new Promise((resolve) => {
    const child = spawn(binary, args, { stdio: 'inherit' });
    child.on('error', (error) => {
      process.stderr.write(`Could not run dartvel: ${error.message}\n`);
      resolve(1);
    });
    child.on('close', (code) => resolve(code === null ? 1 : code));
  });
}

module.exports = { run, assetName, binaryPath, ensureBinary, VERSION };
