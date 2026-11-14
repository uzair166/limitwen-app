import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { installNative, findApp } from './native-install.mjs';

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const metadata = JSON.parse(readFileSync(resolve(packageRoot, 'package.json'), 'utf8'));

export function runCLI(args, {
  platform = process.platform,
  root = packageRoot,
  run = spawnSync,
  exists = existsSync,
  install = installNative,
  locate = findApp,
  output = console.log,
  error = console.error,
} = {}) {
  const command = args[0] ?? 'open';
  if (args.length > 1 || !['open', 'install', '--show', '--version', '--help', '-h'].includes(command)) {
    error('Usage: limitwen [install | --show | --version | --help]');
    return 2;
  }
  if (command === '--version') { output(metadata.version); return 0; }
  if (command === '--help' || command === '-h') {
    output('Limitwen — Claude Code and Codex usage in your macOS menu bar.\n\nlimitwen          Open the app\nlimitwen --show   Open its usage popover\nlimitwen install  Install the signed, notarized app in your Applications folder\n\nThe app is bundled with this package. No Swift compiler or separate download is required.');
    return 0;
  }
  if (platform !== 'darwin') { error('Limitwen requires macOS 14 or later.'); return 1; }
  if (command === 'install') {
    try {
      const app = install({ root });
      output(`Installed: ${app}\nOpen Limitwen from Finder, or run limitwen.`);
      return 0;
    } catch (failure) { error(failure.message); return 1; }
  }
  const app = locate();
  if (!app || !exists(resolve(app, 'Contents', 'MacOS', 'Limitwen'))) {
    error('The app is not installed. Run limitwen install (needed when npm lifecycle scripts are disabled).');
    return 1;
  }
  const result = run('/usr/bin/open', [app, ...(command === '--show' ? ['--args', '--show'] : [])], { stdio: 'inherit' });
  if (result.error || result.status !== 0) { error('Limitwen could not be opened.'); return 1; }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = runCLI(process.argv.slice(2));
}
