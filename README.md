# Limitwen: Claude Code and Codex limits for macOS

**Just your AI limits, in your menu bar.**

Limitwen is a free, open-source, lightweight macOS menu bar app for tracking **Claude Code and OpenAI Codex usage limits**. See how much allowance you have left and when it resets. Simple rings, a click for details, and optional alerts. No fluff.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111)](https://github.com/uzair166/limitwen-app)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138)](https://www.swift.org/)
[![License: 0BSD](https://img.shields.io/badge/license-0BSD-blue)](LICENSE)
[![CI](https://github.com/uzair166/limitwen-app/actions/workflows/ci.yml/badge.svg)](https://github.com/uzair166/limitwen-app/actions/workflows/ci.yml)

<p>
  <img src="https://raw.githubusercontent.com/uzair166/limitwen-app/main/docs/images/menu-bar-context.png" width="906" alt="Limitwen's single and nested usage rings in a real macOS menu bar, alongside Slack, Docker and other menu-bar icons" />
</p>

*Limitwen in the menu bar. The two rings on the left show your subscription limits at a glance.*

[Download for Mac](https://github.com/uzair166/limitwen-app/releases/latest) · [Install with Homebrew](#homebrew) · [Install with npm](#npm) · [Report a bug](https://github.com/uzair166/limitwen-app/issues)

## Simple by design

- **Separate Claude Code and Codex rings.** Pin either, both or neither; one app icon remains when nothing is pinned.
- **Short and weekly windows when reported.** Inner ring = shorter window, outer ring = longer window. Weekly-only accounts get one ring.
- **Clear reset times.** Relative countdowns and exact local times, with optional per-window reset reminders.
- **Low-limit alerts.** Choose a remaining-allowance threshold; repeated polls do not send duplicate alerts for the same reset cycle.
- **Honest stale and missing data.** Unknown is not zero. A reset deadline does not invent a refill. Transient failures retain the last-known observation where account ownership remains valid.
- **Lightweight and native.** Built with SwiftUI and AppKit, with no third-party Swift dependencies. One small Settings panel, light/dark appearance, and no Dock icon.

## Install

You need **macOS 14 or newer**. The signed, notarized app runs on Apple silicon and Intel Macs. Swift and Xcode are **not required** for Homebrew, npm or the downloadable app.

### Homebrew

```sh
brew install --cask uzair166/tap/limitwen
```

Then open **Limitwen** from **Applications**. It runs in the menu bar, with no Dock icon. A terminal command is not needed to launch it.

This command uses our independent tap. Limitwen is not currently included in Homebrew’s central collection.

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

The [npm package](https://www.npmjs.com/package/limitwen) bundles the same signed app; it does not compile code or download another executable during installation.

Requires Node.js 20 or newer and npm:

```sh
npm install -g limitwen
```

The installer uses your user's `~/Applications` folder, or reuses an identical verified installation in `/Applications`. Open **Limitwen.app** in Finder. For `~/Applications`, use Finder’s **Go → Go to Folder…** and enter `~/Applications`. The optional `limitwen` command also opens the app. If npm disables install scripts, run `limitwen install` once.

The installer verifies the archive checksum, signing identity and Gatekeeper assessment before installing. It does not overwrite an older installation owned by another installer. Removing the npm package removes the launcher; the standalone app remains and can be moved to Trash separately.

### Update or uninstall

Use the same channel you installed with. Quit Limitwen from its menu-bar menu before updating.

| Channel | Update | Uninstall |
| --- | --- | --- |
| Homebrew | `brew upgrade --cask uzair166/tap/limitwen` | `brew uninstall --cask uzair166/tap/limitwen` |
| npm | `npm install -g limitwen@latest` | `npm uninstall -g limitwen`, then move the app from Applications to Trash |
| Direct download | Download the latest release and replace the app in Applications | Move the app to Trash |

If npm reused a Homebrew installation, update the app through Homebrew; npm will not overwrite a different version owned by another installer. Removing the app normally leaves preferences in place. There is no built-in automatic app updater.

### Build it yourself

Contributors need Apple developer tools with **Swift 6**:

```sh
git clone https://github.com/uzair166/limitwen-app.git
cd limitwen-app
./scripts/build.sh release
open build/Limitwen.app
```

Quit a running checkout-built copy before rebuilding it. Scripts respect your selected developer toolchain (`xcode-select`) or an explicit `DEVELOPER_DIR`. Local builds use ad-hoc signatures; the public release uses Developer ID signing and notarization.

## Screenshots

<p>
  <img src="https://raw.githubusercontent.com/uzair166/limitwen-app/main/docs/images/popover-light.png" width="380" alt="Limitwen macOS menu bar popover showing separate Claude Code and Codex allowance, five-hour and weekly reset times, and notification controls" />
  <img src="https://raw.githubusercontent.com/uzair166/limitwen-app/main/docs/images/settings-light.png" width="380" alt="Limitwen single-panel Settings with provider initials, Claude Code and Codex connections, and individual menu-bar pinning" />
</p>

*These popover and Settings previews use labeled example data.*

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
