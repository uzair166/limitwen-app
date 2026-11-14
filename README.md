# Limitwen

**Claude Code and Codex usage limits, right in your Mac menu bar.**

Limitwen is a small native macOS app that shows your remaining AI subscription allowance, reset times and low-limit alerts. Glance at the rings, open the popover when you need detail, and get back to work.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111)](https://github.com/uzair166/limitwen-app)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138)](https://www.swift.org/)
[![License: 0BSD](https://img.shields.io/badge/license-0BSD-blue)](LICENSE)
[![CI](https://github.com/uzair166/limitwen-app/actions/workflows/ci.yml/badge.svg)](https://github.com/uzair166/limitwen-app/actions/workflows/ci.yml)

<p>
  <img src="https://raw.githubusercontent.com/uzair166/limitwen-app/main/docs/images/popover-light.png" width="380" alt="Limitwen macOS menu bar popover showing separate Claude Code and Codex allowance, five-hour and weekly reset times, and notification controls" />
  <img src="https://raw.githubusercontent.com/uzair166/limitwen-app/main/docs/images/settings-light.png" width="380" alt="Limitwen single-panel Settings with provider initials, Claude Code and Codex connections, and individual menu-bar pinning" />
</p>

*Screenshots use labeled example data, not a real account.*

## What you get

- **Separate Claude Code and Codex rings.** Pin either, both or neither; one app icon remains when nothing is pinned.
- **Short and weekly windows when reported.** Inner ring = shorter window, outer ring = longer window. Weekly-only accounts get one ring.
- **Clear reset times.** Relative countdowns and exact local times, with optional per-window reset reminders.
- **Low-limit alerts.** Choose a remaining-allowance threshold; repeated polls do not send duplicate alerts for the same reset cycle.
- **Honest stale and missing data.** Unknown is not zero. A reset deadline does not invent a refill. Transient failures retain the last-known observation where account ownership remains valid.
- **A native Mac experience.** SwiftUI and AppKit, light/dark appearance, keyboard controls, one Settings panel and no Dock icon.

## Install

You need **macOS 14 or newer**. The signed, notarized app runs on Apple silicon and Intel Macs. Swift and Xcode are **not required** for Homebrew, npm or the downloadable app.

### Homebrew

```sh
brew install --cask uzair166/tap/limitwen
```

Then open **Limitwen** from **Applications**. A terminal command is not needed to launch it.

The custom tap is added automatically. To use the short name on Homebrew versions with explicit tap trust:

```sh
brew tap uzair166/tap
brew trust --cask uzair166/tap/limitwen
brew install --cask limitwen
```

If you installed the earlier source formula, run `brew uninstall --formula limitwen` before installing the cask. Preferences are preserved. Move an existing manually installed copy aside if Homebrew reports an Applications-folder conflict.

### Download

Download the universal app from [GitHub Releases](https://github.com/uzair166/limitwen-app/releases/latest), unzip it, and drag **Limitwen.app** into **Applications**. The release carries a Developer ID signature and a stapled Apple notarization ticket.

### npm

The npm package bundles the same signed app; it does not compile code or download another executable during installation. Registry availability is pending the first publication.

Once published, `npm install -g limitwen` installs into your user's `~/Applications` folder, or reuses an identical verified installation in `/Applications`. Open the app in Finder, or run `limitwen`. If npm disables install scripts, run `limitwen install` once.

The installer verifies the archive checksum, signing identity and Gatekeeper assessment before installing. It does not overwrite an older installation owned by another installer. Removing the npm package removes the launcher; the standalone app remains and can be moved to Trash separately.

### Build it yourself

Contributors need Apple developer tools with **Swift 6**:

```sh
git clone https://github.com/uzair166/limitwen-app.git
cd limitwen-app
./scripts/build.sh release
open build/Limitwen.app
```

Quit a running checkout-built copy before rebuilding it. Scripts respect your selected developer toolchain (`xcode-select`) or an explicit `DEVELOPER_DIR`. Local builds use ad-hoc signatures; the public release uses Developer ID signing and notarization.

## Connect your subscriptions

| Entry | What it reads | What you need |
| --- | --- | --- |
| **Claude Code** | Reported short, weekly and model-specific limits from Claude's native usage command and account-matched cache | Installed, signed-in Claude Code. Automatic refresh currently requires a supported Claude 2.x version starting at 2.1.273. Enable **Connect** in Settings. |
| **Codex & ChatGPT** | **Codex allowance** through the installed Codex CLI's app-server interface | Installed, signed-in Codex CLI. Use `codex login` if needed, then refresh. |

The combined Codex & ChatGPT entry does **not** claim to measure separate ChatGPT message limits. Account plans differ: Limitwen only displays the windows the source actually reports. Claude Team accounts can expose local usage too; availability depends on the installed CLI and source data, not just the plan name.

Provider interfaces can change. Claude's usage cache is an observed implementation detail, not a guaranteed public API. See [provider contracts](docs/ARCHITECTURE.md) for compatibility boundaries and failure behavior.

## Privacy

Limitwen does not collect analytics, copy authentication tokens, scrape browser cookies or send model prompts to check your limits. Your installed CLIs use their own sign-in to retrieve usage. That means quota refreshes can make network requests through those CLIs; “local integration” does not mean “never connects to the internet.”

Preferences and notification deduplication stay on your Mac. Codex snapshots stay in memory rather than an account-unbound disk cache. Claude cache identity is checked and then discarded. Notification permission is requested only when you turn on a reminder or alert.

## Everyday use

Click a ring to open usage. Right-click for refresh, Settings and Quit. Press **⌘,** for Settings and **Escape** to close the popover. Settings lets you show provider initials, enable subscriptions and choose which ones appear in the menu bar.

Meters always show **remaining** allowance. A dim or unknown reading is not a fresh entitlement. At a reset time, Limitwen checks again rather than assuming the quota replenished.

## Development

```sh
./scripts/test.sh           # deterministic, offline Swift tests
./scripts/check.sh          # tests, build, helper and bundle checks
./scripts/test-ui.sh        # native presentation; unlocked Mac required
npm test                   # installer/launcher tests; Node 20+ required
```

There are no third-party Swift dependencies. Default tests do not require a paid account or live network. Graphical, live-account and assistive-technology checks remain separate from headless CI.

Read [Contributing](CONTRIBUTING.md), [Design](docs/DESIGN.md) and [Architecture](docs/ARCHITECTURE.md). Report bugs through [GitHub Issues](https://github.com/uzair166/limitwen-app/issues) and security concerns through [private reporting](https://github.com/uzair166/limitwen-app/security/advisories/new).

## License

[Zero-Clause BSD (0BSD)](LICENSE). Use it, modify it, redistribute it or use it commercially. **No attribution required.**

Limitwen is an independent project, not affiliated with or endorsed by Anthropic or OpenAI. Provider names identify the services it works with.
