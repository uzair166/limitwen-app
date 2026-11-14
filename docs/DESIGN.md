# Design principles

Limitwen should answer two questions quietly: how much allowance remains, and when does it reset?

## Menu bar

Use restrained nested rings at native status-item size. The short window is inside and the longer window outside. Render only reported windows; one window uses one ring. Neutral color means ordinary usage, amber marks a low allowance, and unknown/stale states remain visibly distinct. Color is never the only signal.

Each provider has a separate pin. Initials are optional. With no providers pinned, a compact app item remains available. Re-pinning and appearance changes must redraw immediately in the status button's own appearance context.

## Popover

Use a real transient NSPopover, without an opening animation. Prepare its initial content layout during setup and remeasure against the anchor screen before presentation. Keep provider sections distinct, percentages aligned and reset times readable. Every reset has relative and exact local text. Long content scrolls within the anchor screen's available height. Footer actions remain reachable. Escape and outside clicks dismiss, including after menu tracking.

Use system typography, restrained semantic colors, consistent spacing and stable geometry. Use subtly separated provider surfaces, prominent remaining percentages and a single compact alert row. Avoid decorative dashboard chrome. Motion should explain a state change; respect Reduce Motion. Preserve native keyboard navigation and visible focus. The custom pin uses a shaped neutral focus cue within its bounds.

## Settings

One native window, no tabs. Group menu-bar initials and subscription enable/pin controls; use one enable switch per subscription and actionable connection errors. Claude reads existing local usage automatically when enabled; there is no separate Connect step. Preserve earlier explicit opt-outs. Keep a small privacy/version footer. There is no user-facing demo mode or style picker. Developer fixtures must always identify example values.

## States and acceptance

Design empty, loading, ready, stale, disconnected, denied and error states. Failed refreshes preserve last-known observations and their timestamps where account ownership is still valid. Never fabricate replenishment at a reset boundary.

Inspect light/dark appearance, increased contrast, keyboard focus, VoiceOver labels, long content, a single reported window, zero/unknown values, pinning and relaunch persistence. Review real on-screen presentation and normal-size status items, not only enlarged screenshots.

Design references: [Apple popovers](https://developer.apple.com/design/human-interface-guidelines/popovers), [NSPopover animation](https://developer.apple.com/documentation/appkit/nspopover/animates). Reviewed 14 November 2026. The immediate presentation is a product choice for quick menu-bar glances; it retains native positioning, focus and dismissal.
