# Releases and installation channels

## Verification

Run `./scripts/check.sh`, `npm test` and `./scripts/test-ui.sh` in an unlocked macOS session. Inspect the actual app and use synthetic screenshots. Keep Resources/Info.plist and package.json versions aligned. CI covers Apple silicon and Intel builds; native interaction and real-account behavior remain separate acceptance work.

## Signed application

Build a universal executable and helper with `xcrun swift build -c release --arch arm64 --arch x86_64`. Package the normal app resources with those binaries. Sign the helper first, then the app, using a Developer ID Application identity, hardened runtime (`--options runtime`) and a trusted timestamp (`--timestamp`). Do not export private keys into the repository.

For notarization, Xcode's signed-in account can be used with a macOS `.xcarchive` and `xcodebuild -exportArchive`: export method `developer-id`, destination `upload`, manual signing, and the selected team/certificate. This avoids requiring a separate app-specific password for an interactive developer-machine release. Store archive metadata, distribution logs and exported products only in ignored build directories. An archive must include the signed app under Products/Applications and matching application properties in its Info.plist.

After Apple accepts the submission, `xcodebuild -exportNotarizedApp` exports the stapled application. Validate it with `xcrun stapler validate`, `codesign --verify --deep --strict`, and `spctl --assess --type execute --verbose=2`. A successful upload is not acceptance. Do not publish until all three validation steps pass.

ZIP the stapled app with `ditto -c -k --sequesterRsrc --keepParent`, record its SHA-256, and upload the immutable release asset. Test a downloaded/extracted copy and the public installation channels. Never remove quarantine or weaken Gatekeeper as an installation workaround.

See Apple's [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Automated release signing needs separately configured secrets and permissions; the current setup uses local Keychain credentials, not an unattended signing pipeline.

## Homebrew

[uzair166/homebrew-tap](https://github.com/uzair166/homebrew-tap) is a general-purpose tap. Its `limitwen` cask installs the notarized app into Applications. Update the cask version, immutable asset URL and SHA-256 for each release. Installation CI checks the app location, signature, ticket, Gatekeeper and uninstall behavior.

Use `brew install --cask uzair166/tap/limitwen`. The short name requires the tap to be added/trusted and must not conflict with another package. Inclusion in Homebrew's central collection is not implied. Earlier source-formula users must uninstall the formula before installing the cask; preferences are preserved.

## npm

The package contains a small Node launcher, source code and the same notarized ZIP. `scripts/native-install.mjs` pins the archive digest and expected signing identity. Update these together with the version and release URL in `scripts/fetch-release.sh`.

```sh
./scripts/fetch-release.sh
npm test
python3 scripts/test-npm-package.py
npm pack --ignore-scripts
# Install the tarball in a disposable prefix and verify the installed app.
npm publish --access public
```

The ZIP is an ignored build artifact included explicitly by npm's files allowlist. The installer verifies it before extraction, validates the signed app, and stages replacement. It reuses the same verified version in /Applications or installs into ~/Applications. It refuses to replace a different unmanaged installation or a running managed app. npm uninstall removes the launcher but leaves the standalone app.

Publication requires npm account authentication and its 2FA approval, or an appropriately configured trusted publisher. Configure [trusted publishing](https://docs.npmjs.com/trusted-publishers/) for subsequent releases if desired, verifying repository/workflow identity. Never store npm tokens in Git. Update the README to claim registry availability only after a successful registry read.


After npm accepts publication, wait until `npm view limitwen version` reports the expected version. A temporary staging placeholder is not a published release. Install from the registry into a disposable prefix and verify `limitwen --version` and `limitwen install`. Check the packaged README before publishing: a released tarball is immutable even if the GitHub README is later corrected.

## Central Homebrew submission

The third-party tap works independently of acceptance into `Homebrew/homebrew-cask`. Before opening a central submission, read the current [acceptance policy](https://docs.brew.sh/Package-Acceptance-Policy), [cask requirements](https://docs.brew.sh/Acceptable-Casks), [submission guide](https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request) and repository CONTRIBUTING.md. Search existing and previously closed PRs. Verify livecheck, style, the new-cask audit, installation and uninstallation, and run `brew lgtm --online` from the contribution checkout. Do not mark failed or unperformed checks as passed.

Disclose AI assistance when used. The submitter must personally review generated changes and PR text before requesting Homebrew review and must handle maintainer questions without AI assistance. A new release or a working third-party cask does not establish the age or public-interest requirements. Keep installation instructions pointing to the independent tap until a central cask is actually merged and available.
