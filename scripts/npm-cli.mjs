import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const metadata = JSON.parse(readFileSync(resolve(packageRoot, 'package.json'), 'utf8'));

export function runCLI(args, {
  platform = process.platform,
  root = packageRoot,
  run = spawnSync,
  exists = existsSync,
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
    output('Limitwen — Claude Code and Codex usage in your macOS menu bar.\n\nlimitwen          Open the app\nlimitwen --show   Open its usage popover\nlimitwen install  Build/rebuild the native app (requires Swift 6 Apple developer tools)\n\nNo credentials or prebuilt binaries are downloaded by this installer.');
    return 0;
  }
  if (platform !== 'darwin') { error('Limitwen requires macOS 14 or later.'); return 1; }
  const app = resolve(root, 'build', 'Limitwen.app');
  if (command === 'install') {
    output('Building Limitwen locally. Swift 6 Apple developer tools are required.');
    const result = run('/bin/zsh', [resolve(root, 'scripts', 'build.sh'), 'release'], { cwd: root, stdio: 'inherit' });
    if (result.error || result.status !== 0) {
      error('Limitwen could not be built. Check xcrun swift --version and your developer-tool selection, then run limitwen install. Use a user-writable npm prefix; do not disable macOS security protections.');
      return 1;
    }
    output('Installed. Run limitwen to open the menu-bar app.');
    return 0;
  }
  if (!exists(resolve(app, 'Contents', 'MacOS', 'Limitwen'))) {
    error('The native app is not built. Run limitwen install (needed when npm lifecycle scripts are disabled).');
    return 1;
  }
  const result = run('/usr/bin/open', [app, ...(command === '--show' ? ['--args', '--show'] : [])], { stdio: 'inherit' });
  if (result.error || result.status !== 0) { error('Limitwen could not be opened.'); return 1; }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = runCLI(process.argv.slice(2));
}
