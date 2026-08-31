// The asset name is the whole contract with the release, so it is the thing
// worth asserting. A wrong one is a 404 at install time on someone else's
// machine, and it cannot be reproduced on the machine that wrote it.
'use strict';

const assert = require('assert');
const { assetName } = require('./index');

assert.strictEqual(assetName('linux', 'x64'), 'dartvel-linux-amd64');
assert.strictEqual(assetName('linux', 'arm64'), 'dartvel-linux-arm64');
assert.strictEqual(assetName('darwin', 'x64'), 'dartvel-darwin-amd64');
assert.strictEqual(assetName('darwin', 'arm64'), 'dartvel-darwin-arm64');
assert.strictEqual(assetName('win32', 'x64'), 'dartvel-windows-amd64.exe');

// Only Windows carries an extension, and it carries it once.
for (const [p, a] of [['linux', 'x64'], ['darwin', 'arm64']]) {
  assert.ok(!assetName(p, a).includes('.exe'), `${p}/${a} must not be .exe`);
}

// An unsupported combination says which one, rather than building a URL that
// will 404 with no explanation.
assert.throws(() => assetName('sunos', 'x64'), /sunos/);
assert.throws(() => assetName('linux', 'ia32'), /ia32/);
assert.throws(() => assetName('win32', 'arm64'), /Windows on ARM/);

console.log('asset names ok');

// The bin entries, which npm silently rewrites if they are not exactly right.
//
// `./bin/dartvel.js` made npm warn "script name bin/dartvel.js was invalid and
// removed" and auto-correct the manifest it sends to the registry. The bin
// block is the entire point of this package -- without it `npm i -g
// dartvel_dev` installs a directory and no `dartvel` command -- so it should
// not depend on npm silently fixing it up.
const fs = require('fs');
const path = require('path');

for (const dir of ['.', '../dartvel_cli']) {
  const manifestPath = path.join(__dirname, dir, 'package.json');
  if (!fs.existsSync(manifestPath)) continue;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const bin = manifest.bin || {};

  assert.ok(Object.keys(bin).length > 0, `${manifest.name} declares no bin`);

  for (const [name, target] of Object.entries(bin)) {
    // The leading "./" is what npm objects to.
    assert.ok(
      !target.startsWith('./'),
      `${manifest.name} bin[${name}] must not start with "./": npm rewrites it`
    );
    assert.ok(
      fs.existsSync(path.join(__dirname, dir, target)),
      `${manifest.name} bin[${name}] points at a missing file: ${target}`
    );
    // Shipped, or the published package has a bin pointing at nothing.
    assert.ok(
      (manifest.files || []).some((f) => target.startsWith(f.replace(/\/$/, ''))),
      `${manifest.name} does not ship ${target}`
    );
  }
}

console.log('bin entries ok');
