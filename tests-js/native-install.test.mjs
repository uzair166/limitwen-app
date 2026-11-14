import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { installNative, release } from '../scripts/native-install.mjs';

function fixture(t, { existing, managed = false, failVerify = false, running = false, receiptConflict = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'limitwen-installer-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const appDirectory = join(root, 'Applications'), target = join(appDirectory, 'Limitwen.app');
  mkdirSync(join(root, 'vendor')); mkdirSync(appDirectory);
  const bytes = Buffer.from('synthetic signed release');
  writeFileSync(join(root, 'vendor/Limitwen.zip'), bytes);
  function app(path, version) { mkdirSync(join(path, 'Contents'), { recursive: true }); writeFileSync(join(path, 'Contents/Info.plist'), version); }
  if (existing) app(target, existing);
  if (managed) writeFileSync(join(appDirectory, '.limitwen-npm.json'), JSON.stringify({ app: target, version: existing }));
  if (receiptConflict) mkdirSync(join(appDirectory, '.limitwen-npm.json'));
  const calls = [];
  const run = (command, args) => {
    calls.push([command, args]);
    if (command.endsWith('/ditto')) app(join(args.at(-1), 'Limitwen.app'), release.version);
    if (command.endsWith('/codesign') && failVerify && args.at(-1).includes('.limitwen-install-')) return { status: 1 };
    let stdout = '';
    if (command.endsWith('/PlistBuddy')) stdout = readFileSync(args.at(-1), 'utf8');
    if (command.endsWith('/ps')) stdout = running ? join(target, 'Contents/MacOS/Limitwen') : '';
    return { status: 0, stdout };
  };
  return { root, target, calls, options: { root, appDirectory, systemApp: join(root, 'no-system-app'), run, expectedHash: createHash('sha256').update(bytes).digest('hex') } };
}
test('tampered archive never invokes extraction or touches an existing app', t => {
  const f = fixture(t, { existing: '0.0.1', managed: true });
  assert.throws(() => installNative({ ...f.options, expectedHash: 'invalid' }), /checksum/);
  assert.equal(f.calls.length, 0); assert.equal(readFileSync(join(f.target, 'Contents/Info.plist'), 'utf8'), '0.0.1');
});
test('fresh install verifies identity and Gatekeeper before placing the app', t => {
  const f = fixture(t); assert.equal(installNative(f.options), f.target);
  assert.ok(f.calls.some(([cmd, args]) => cmd.endsWith('/codesign') && args.includes(release.requirement)));
  assert.ok(f.calls.some(([cmd]) => cmd.endsWith('/spctl')));
  assert.equal(JSON.parse(readFileSync(join(f.options.appDirectory, '.limitwen-npm.json'))).version, release.version);
});
test('failed signature verification preserves the old managed app', t => {
  const f = fixture(t, { existing: '0.0.1', managed: true, failVerify: true });
  assert.throws(() => installNative(f.options), /codesign failed/);
  assert.equal(readFileSync(join(f.target, 'Contents/Info.plist'), 'utf8'), '0.0.1');
});
test('an unmanaged older app is never overwritten', t => {
  const f = fixture(t, { existing: '0.0.1' }); assert.throws(() => installNative(f.options), /unmanaged/);
  assert.equal(f.calls.some(([cmd]) => cmd.endsWith('/ditto')), false);
});
test('running managed app must be quit before replacement', t => {
  const f = fixture(t, { existing: '0.0.1', managed: true, running: true }); assert.throws(() => installNative(f.options), /Quit/);
});
test('managed update replaces the app after successful verification', t => {
  const f = fixture(t, { existing: '0.0.1', managed: true }); installNative(f.options);
  assert.equal(readFileSync(join(f.target, 'Contents/Info.plist'), 'utf8'), release.version);
});
test('a receipt write failure rolls back a fresh installation', t => {
  const f = fixture(t, { receiptConflict: true }); assert.throws(() => installNative(f.options)); assert.equal(existsSync(f.target), false);
});
test('same signed version reuses an existing system app', t => {
  const f = fixture(t, { existing: release.version });
  const options = { ...f.options, systemApp: f.target, appDirectory: join(f.root, 'other-apps') };
  assert.equal(installNative(options), f.target); assert.equal(f.calls.some(([cmd]) => cmd.endsWith('/ditto')), false);
});
test('application symlinks are refused before signature verification', t => {
  const f = fixture(t); symlinkSync(join(f.root, 'elsewhere'), f.target);
  // Broken symlinks are still occupied destinations, never installation slots.
  assert.throws(() => installNative(f.options));
});
