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
