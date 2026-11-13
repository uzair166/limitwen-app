# Contributing

Limitwen is licensed under [0BSD](LICENSE). Use, modify and redistribute it freely, including commercially; attribution is not required. Contributions should be compatible with that license.

Read [AGENTS.md](AGENTS.md), [design principles](docs/DESIGN.md) and [architecture](docs/ARCHITECTURE.md). Keep changes focused on Claude Code and the combined Codex & ChatGPT entry.

## Build and test

Use macOS 14+ and Apple developer tools providing Swift 6. Scripts honor `xcode-select` and an explicit `DEVELOPER_DIR`.

```sh
xcrun swift --version
./scripts/test.sh
./scripts/check.sh
./scripts/run.sh
```

`check.sh` runs offline tests, packages an ad-hoc-signed development app, checks the legacy helper and validates the bundle. Quit the checkout-built app before rebuilding its bundle. Python 3 is needed for the script tests.

For UI changes, run `./scripts/test-ui.sh` in an unlocked graphical session and inspect the actual app. Native tests run in separate processes because AppKit menu tracking can interfere with a command-line test host. Verify Tab/Space, Escape, outside clicks, pinning, appearance and relaunch persistence. Headless tests and screenshots alone do not establish visual or assistive-technology acceptance.

Some Command Line Tools versions need the Swift Testing plugin path passed explicitly. If discovery fails, locate the selected toolchain and run:

```sh
TOOLCHAIN_USR="$(dirname "$(dirname "$(xcrun --find swift)")")"
./scripts/test.sh -Xswiftc -plugin-path \
  -Xswiftc "$TOOLCHAIN_USR/lib/swift/host/plugins/testing"
```

Use that workaround only when the directory exists. The same arguments can be passed to `check.sh` and `test-ui.sh`.

## Fixes and fixtures

Each bug fix needs a permanent regression: observe a meaningful failure, implement the fix, then demonstrate the pass. Keep tests offline with fixed clocks, isolated defaults and sanitized temporary fixtures. Do not require paid accounts, notification permission or live services in the default suite.

Never commit provider configuration, account identifiers, credentials, transcripts, personal settings or generated logs. Developer rendering with `--render-previews` uses labeled example values. Live probes are deliberate local diagnostics, not ordinary CI jobs.

## Pull requests

Explain the behavior being corrected and the resulting user experience. Include relevant test evidence and UI screenshots for visual changes. Distinguish verified behavior from untested platforms or permissions. Keep documentation current and avoid adding conversation history or machine-specific investigation notes.

Use [private vulnerability reporting](https://github.com/uzair166/limitwen-app/security/advisories/new) for security issues rather than posting exploitable details or secrets publicly.
