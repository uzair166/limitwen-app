# Releases and installation channels

## Source release

1. Run `./scripts/check.sh`, `npm test` and `./scripts/test-ui.sh` in an unlocked macOS session.
2. Inspect the app's menu bar, Settings, keyboard, pinning and provider failure states. Use synthetic screenshots; never publish account data.
3. Keep `Resources/Info.plist` and `package.json` versions aligned.
4. Tag the reviewed commit and publish source release notes. Do not claim binaries are notarized unless signing and notarization were actually verified.
5. Update the Homebrew tap formula's source URL, version and SHA-256, then test a fresh installation.

CI uses macOS on Apple silicon and Intel for offline build/test coverage. Native interaction and real-account behavior need their own acceptance run. A green CI result is not proof of every macOS version, display, accessibility setting or provider plan.

## Homebrew

The tap is [uzair166/homebrew-tap](https://github.com/uzair166/homebrew-tap). Its formula builds this repository's tagged source with the user's Swift 6 Apple toolchain and installs the app plus a `limitwen` launcher. Installation does not disable macOS security protections or extract provider credentials.

A custom tap makes `brew install limitwen` available after `brew tap uzair166/tap`; no inclusion in Homebrew's central repositories is implied. Formula testing should use the exact published source archive/checksum.

## npm

The root package contains the native sources, build script and a small Node launcher. `npm install -g limitwen` will build the app locally through its postinstall script once the package is published. The installer downloads no separate binary and requires macOS with Swift 6 developer tools. A user-writable npm prefix is recommended. If lifecycle scripts are disabled, `limitwen install` performs the build explicitly.

Before publication:

```sh
npm test
npm pack --dry-run --ignore-scripts
npm pack --ignore-scripts
# In a disposable, user-writable prefix, install the resulting tarball and verify the app.
npm login
npm publish --access public
```

An npm account and its configured 2FA/approval may be required. Do not store tokens in this repository or replace a human login with copied credentials. After the initial package is published, configure [trusted publishing](https://docs.npmjs.com/trusted-publishers/) if desired and verify the exact repository/workflow identity. README registry instructions should only claim availability after a successful public registry read.

## Notarized binary releases

Local ad-hoc signing is not Developer ID distribution. A future prebuilt release needs a Developer ID Application identity, hardened-runtime signing of the nested helper and app, notarization submission and stapling. Validate signatures and Gatekeeper assessment on the resulting artifact and test clean-machine installation.

Use Apple's [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Keep private keys, passwords and API keys outside source control. Never add a quarantine-removal or Gatekeeper-disable command as an installation workaround. An Apple Development identity does not replace a Developer ID Application certificate.
