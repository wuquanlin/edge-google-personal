import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const readJson = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8'));
const baseline = readJson('docs/runtime-sha256.json');
const release = readJson('scripts/release-files.json');
const manifest = readJson('EdgeGooglePersonal/Extension/manifest.json');
const expectedId = 'fnbpglchnbbhcmjcoapbafejooijecah';

assert.equal(baseline.extensionId, expectedId);
assert.equal(manifest.version, release.version);
assert.equal(baseline.version, release.version);
assert.equal(readJson('package.json').version, release.version);
assert.deepEqual([...release.runtimeFiles].sort(), Object.keys(baseline.files).sort());
assert.equal(release.runtimeFiles.length, 11);
for (const [name, digest] of Object.entries(baseline.files)) {
  const actual = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, 'EdgeGooglePersonal', name))).digest('hex');
  assert.equal(actual, digest, `${name}: the verified runtime must remain byte-identical`);
}
console.log('PASS: all 11 runtime files match the original verified source byte-for-byte');

const key = crypto.createPublicKey({key: Buffer.from(manifest.key, 'base64'), type: 'spki', format: 'der'});
assert.equal(key.type, 'public');
const prefix = crypto.createHash('sha256').update(Buffer.from(manifest.key, 'base64')).digest('hex').slice(0, 32);
const id = [...prefix].map(n => String.fromCharCode(97 + parseInt(n, 16))).join('');
assert.equal(id, expectedId);
assert.equal(fs.readFileSync(path.join(root, 'EdgeGooglePersonal/extension-id.txt'), 'utf8').trim(), id);
console.log('PASS: preserved manifest public key derives the existing extension ID');

const files = [
  ...release.runtimeFiles.map(name => `EdgeGooglePersonal/${name}`),
  `EdgeGooglePersonal/${release.runtimeGuide}`,
  ...release.sourceOnlyFiles,
  ...release.sharedFiles,
];
assert.equal(files.length, new Set(files).size, 'No duplicate source entries');
const excluded = /(?:^|\/)(?:config\.json|login-request\.json|login\.log(?:\.old)?|reboot-verification\.json|installation-status\.json|code-verification\.json|powershell-verification\.txt|EdgeGoogle-verification\.json|交接说明\.md)$/i;
for (const name of files) {
  assert(!path.posix.isAbsolute(name) && !name.split('/').includes('..') && !/[\\:]/.test(name), `Safe path: ${name}`);
  assert(!excluded.test(name), `Private runtime state is excluded: ${name}`);
  assert(!/\.(?:pem|pfx|key|log|bak|tmp|zip)$/i.test(name), `No credential or runtime artifact: ${name}`);
  const target = path.join(root, name);
  assert(fs.lstatSync(target).isFile() && !fs.lstatSync(target).isSymbolicLink(), `Regular file: ${name}`);
  const content = fs.readFileSync(target, 'utf8');
  assert(!/C:\\Users\\[^\s\\"<>]+\\/.test(content), `No personal absolute user path: ${name}`);
  assert(!/^-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----$/m.test(content), `No private key: ${name}`);
}
for (const name of fs.readdirSync(root)) {
  if (fs.statSync(path.join(root, name)).isFile()) {
    assert(files.includes(name), `Top-level file should be explicitly included: ${name}`);
  }
}
console.log(`PASS: public release allowlist includes ${files.length} files and excludes installed state`);
console.log('3 release integrity checks passed. No Windows or Edge integration was run.');
