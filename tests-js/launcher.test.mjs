import test from 'node:test';
import assert from 'node:assert/strict';
import { runCLI } from '../scripts/npm-cli.mjs';

function context(options = {}) {
  const calls = [], messages = [];
  return { calls, messages, options: { platform: 'darwin', root: '/fixture/with spaces', exists: () => true,
    run: (...args) => { calls.push(args); return { status: 0 }; },
    output: text => messages.push(text), error: text => messages.push(text), ...options } };
}

test('help/version do not build, launch or inspect accounts', () => {
  for (const argument of ['--version', '--help']) {
    const c = context(); assert.equal(runCLI([argument], c.options), 0); assert.equal(c.calls.length, 0);
  }
});
test('unsupported hosts and unknown arguments cannot execute processes', () => {
  const c = context({ platform: 'linux' }); assert.equal(runCLI([], c.options), 1);
  assert.equal(runCLI(['--unexpected'], c.options), 2); assert.equal(c.calls.length, 0);
});
test('install builds only bundled source and propagates failure', () => {
  const c = context(); assert.equal(runCLI(['install'], c.options), 0);
  assert.deepEqual(c.calls[0].slice(0, 2), ['/bin/zsh', ['/fixture/with spaces/scripts/build.sh', 'release']]);
  const failure = context({ run: () => ({ status: 1 }) }); assert.equal(runCLI(['install'], failure.options), 1);
});
test('launch passes paths as arguments and supports explicit popover opening', () => {
  const c = context(); assert.equal(runCLI(['--show'], c.options), 0);
  assert.deepEqual(c.calls[0].slice(0, 2), ['/usr/bin/open', ['/fixture/with spaces/build/Limitwen.app', '--args', '--show']]);
});
test('missing builds and launch failures are actionable and nonzero', () => {
  const missing = context({ exists: () => false }); assert.equal(runCLI([], missing.options), 1); assert.equal(missing.calls.length, 0);
  const failure = context({ run: () => ({ error: new Error('fixture') }) }); assert.equal(runCLI([], failure.options), 1);
});
