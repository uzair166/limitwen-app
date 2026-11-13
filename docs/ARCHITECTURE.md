# Architecture and provider contracts

Limitwen is a dependency-free Swift 6 package targeting macOS 14+. SwiftUI supplies content; AppKit owns NSStatusItem, a transient NSPopover and one reusable NSWindowController for Settings.

## Boundaries

- **LimitwenCore:** normalized quota values, parsing, freshness/reset/alert policy, bounded process transport and private local storage.
- **Limitwen:** main-actor UI state, independent provider refreshes, notification delivery and native presentation.
- **LimitwenProbe:** explicit developer diagnostics that print normalized quotas, timestamps and connection errors.
- **LimitwenRelay:** legacy migration compatibility. New connections do not install or require a status-line wrapper.

Provider adapters return normalized snapshots or actionable failures. A missing window is absent, not zero. A reported unknown value is still a window. Keep source timestamps and separate unrelated quotas. Retry delays and late-result ownership belong in app state; wire protocols stay in adapters.

## Claude Code

The adapter uses the installed CLI's native local `/usage` command, then reads the account-matched usage cache. Automatic refresh currently accepts the supported Claude 2.x range starting at 2.1.273. It uses safe mode and requires a receipt proving local execution with no model turns or model cost. Unsupported versions may provide existing cache data, but automatic refresh fails closed.

The cache format is an observed implementation detail, not a stable third-party API. Cache account identity must match the current CLI account; identity is discarded after validation. Empty, malformed, future or mismatched cache records cannot become fresh readings. Team membership alone does not make local usage unavailable.

References: [Claude interactive commands](https://code.claude.com/docs/en/interactive-mode), [CLI reference](https://code.claude.com/docs/en/cli-usage), [official changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md). Public docs do not guarantee the internal cache schema or headless command receipt; validate adapter changes against sanitized fixtures and a deliberate live check.

## Codex & ChatGPT

The installed, signed-in Codex CLI exposes `account/rateLimits/read` through its [app-server interface](https://learn.chatgpt.com/docs/app-server). Initialize over stdio, send `initialized`, and request only quota information. No thread or model turn is created. Select the Codex rate-limit bucket and identify windows by reported duration rather than primary/secondary position.

The combined UI entry shows **Codex allowance**, not separately fetched ChatGPT message quotas. Snapshots stay in memory: the quota payload does not establish a stable account binding for a persisted cache. Authentication failures clear old usage. Same-session transient errors retain timestamped last-known values. An external account change between polls is only detectable on a subsequent read.

Review current provider authentication/distribution requirements before changing the release model. Functionality of a local CLI integration does not itself authorize arbitrary hosted or commercial reuse of provider services.

## Refresh and notifications

Provider reads run independently. Native refresh is approximately every five minutes, with debounced manual refresh, wake/reset reads and bounded backoff. Claude's local cache is checked more frequently. Observations become stale after 15 minutes. A reset deadline never fabricates new allowance.

Revision checks invalidate effects after stop, disconnect, provider changes or fixture transitions. Notification authorization is requested only on deliberate opt-in. Low-limit alerts deduplicate by provider/window/reset cycle and require fresh observations. Reset reminders describe the scheduled time, not guaranteed replenishment. Corrected reset requests preserve saved intent across suspended effects.

## Privacy and process safety

Limitwen does not copy tokens, scrape browser cookies, send prompts or collect analytics. Installed CLIs perform their own authentication and network usage reads. Limits are not a local-only networking promise.

Process transport bounds bytes, uses nonblocking pipes, deadlines and cancellation, closes unused pipe ends and terminates stuck children. File reads are bounded and reject inappropriate file types. App-owned atomic writes create private temporary files without changing permissions on existing parent directories. Preferences and notification deduplication use UserDefaults.
