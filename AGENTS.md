# Working on Limitwen

## Priorities

1. Clear, polished user experience and truthful usage information.
2. Correctness, privacy, accessibility and resilience.
3. Small, maintainable native implementation.

Read docs/DESIGN.md before changing UI and docs/ARCHITECTURE.md before changing providers. Scope is Claude Code and one combined Codex & ChatGPT entry. Do not expand provider coverage or add configuration without a product requirement.

## Product invariants

- Native macOS menu utility: SwiftUI content, AppKit status items/popover/settings window.
- Rings only. Inner is the shorter window; outer is the longer window. One reported window means one ring. All meters show remaining allowance; never total unrelated quotas.
- Absent, unknown, stale, exhausted and disconnected are distinct. Preserve source observation timestamps. A reset time passing does not prove replenishment.
- Show relative and exact local reset times. Keep independently reported quotas separate.
- Pin any subset, including none; retain one app item when none are pinned. Preserve supported choices and ordering through migration.
- Show Codex allowance under Codex & ChatGPT; do not imply separate ChatGPT message quotas are measured.
- Connections use the installed CLIs and existing local sign-ins. No credential extraction, browser-cookie scraping, analytics, model turns or transcript logging to obtain usage.
- Claude's native local /usage receipt and account-matched cache are version-sensitive; fail closed when their contract changes.
- Notifications require deliberate opt-in, fresh observations and per-window/reset-cycle deduplication. Keep sample fixtures isolated from real preferences, providers and notifications.

## Engineering

Use Swift 6 strict concurrency. UI state belongs to MainActor; process and file I/O belong on cancellable workers. Inject time and external effects at meaningful boundaries. Prefer explicit value states and deep, small modules over wrappers or speculative plugin frameworks.

Bound subprocess input/output and deadlines. Handle EOF, cancellation, malformed data, auth failures, offline operation, sleep/wake and late results. Keep last-known observations on transient failure, but clear data when account ownership cannot be trusted. Never log credentials, account identifiers or session content.

Use native controls and shared tokens. Preserve keyboard operation, visible focus, accessibility labels, Reduce Motion and appearance changes. UI correctness includes geometry, loading/error states and dismissal behavior.

## Tests and delivery

Every bug fix requires a permanent regression: write it, run it and observe a relevant behavioral failure, fix the implementation, then demonstrate the pass. A compiler failure is not a reproduction.

Default tests must be deterministic and offline, with synthetic fixtures, isolated defaults and temporary directories. Use Swift Testing for domain and app-state boundaries. Native presentation tests are separate: run scripts/test-ui.sh in an unlocked graphical session for presentation changes and inspect the built app, including keyboard, outside clicks, Escape, pinning and actual-size menu items. Unit tests and offscreen renders alone do not establish UI acceptance.

Run scripts/check.sh before delivery. Keep generated bundles, logs, personal configuration and credentials out of Git. Keep documentation about current contracts and reproducible workflows, not chat transcripts, audit diaries or personal machine history. Report any unverified platform, accessibility or live-account behavior plainly; never claim perfection from a green suite.
