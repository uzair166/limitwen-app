import { createHash } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

export const release = {
  version: '0.1.0',
  sha256: 'b6b55c0766451a251213fdfbc52fc8cdab3a897fd3d231a7cae56b4715e3c0ff',
  requirement: '=anchor apple generic and certificate leaf[subject.OU] = "SG955W9MFP" and identifier "app.limitwen.mac"',
};

function checked(run, command, args) {
  const result = run(command, args, { encoding: 'utf8', timeout: 120_000 });
  if (result.error || result.status !== 0) throw new Error(`${command.split('/').pop()} failed; the existing app was not replaced.`);
  return (result.stdout ?? '').trim();
}
export function verifyApp(app, run = spawnSync) {
  if (lstatSync(app).isSymbolicLink()) throw new Error('Refusing to replace an application symlink.');
  checked(run, '/usr/bin/codesign', ['--verify', '--deep', '--strict', '-R', release.requirement, app]);
  checked(run, '/usr/sbin/spctl', ['--assess', '--type', 'execute', app]);
  return checked(run, '/usr/libexec/PlistBuddy', ['-c', 'Print CFBundleShortVersionString', join(app, 'Contents/Info.plist')]);
}
export function findApp({ appDirectory = join(homedir(), 'Applications'), systemApp = '/Applications/Limitwen.app' } = {}) {
  const local = join(appDirectory, 'Limitwen.app');
  return existsSync(local) ? local : existsSync(systemApp) ? systemApp : null;
}

/** Installs the exact signed release, retaining any existing app until validation succeeds. */
export function installNative({ root, appDirectory = join(homedir(), 'Applications'), systemApp = '/Applications/Limitwen.app', run = spawnSync, expectedHash = release.sha256 } = {}) {
  const archive = resolve(root, 'vendor/Limitwen.zip');
  if (createHash('sha256').update(readFileSync(archive)).digest('hex') !== expectedHash) throw new Error('Bundled app checksum mismatch. Installation stopped.');
  const target = join(appDirectory, 'Limitwen.app');
  const receipt = join(appDirectory, '.limitwen-npm.json');
  // Respect Homebrew or manual installations; never update another installer's app.
  if (!existsSync(target) && existsSync(systemApp)) {
    if (verifyApp(systemApp, run) === release.version) return systemApp;
    throw new Error('Limitwen is already installed in /Applications. Update it with its original installer.');
  }
  if (existsSync(target)) {
    const version = verifyApp(target, run);
    if (version === release.version) return target;
    const saved = existsSync(receipt) ? JSON.parse(readFileSync(receipt, 'utf8')) : null;
    if (saved?.app !== target || saved?.version !== version) throw new Error('An unmanaged Limitwen app already exists. Move it aside or update it with its original installer.');
    const pids = checked(run, '/bin/ps', ['-axo', 'comm=']);
    if (pids.split('\n').some(line => line.trim() === join(target, 'Contents/MacOS/Limitwen'))) throw new Error('Quit Limitwen before updating it.');
  }
  mkdirSync(appDirectory, { recursive: true });
  const stage = mkdtempSync(join(appDirectory, '.limitwen-install-'));
  const backup = join(stage, 'previous.app');
  let moved = false, installed = false, rollbackFailed = false;
  try {
    checked(run, '/usr/bin/ditto', ['-x', '-k', archive, stage]);
    const incoming = join(stage, 'Limitwen.app');
    if (verifyApp(incoming, run) !== release.version) throw new Error('Bundled app version mismatch.');
    if (existsSync(target)) { renameSync(target, backup); moved = true; }
    renameSync(incoming, target); installed = true;
    const pendingReceipt = join(stage, 'receipt.json');
    writeFileSync(pendingReceipt, JSON.stringify({ app: target, version: release.version }) + '\n', { mode: 0o600 });
    renameSync(pendingReceipt, receipt);
    return target;
  } catch (error) {
    try {
      if (installed) rmSync(target, { recursive: true });
      if (moved) renameSync(backup, target);
    } catch {
      rollbackFailed = true;
      throw new Error(`Installation failed; the previous app is preserved at ${backup}.`);
    }
    throw error;
  } finally {
    if (!rollbackFailed) rmSync(stage, { recursive: true, force: true });
  }
}
