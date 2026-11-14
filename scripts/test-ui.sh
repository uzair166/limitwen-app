#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Real AppKit presentation requires an unlocked graphical macOS session.
export LIMITWEN_NATIVE_UI_TESTS=1
# A native menu's tracking loop stops the command-line test host's outer run
# loop on exit. Isolate the tests so that cannot silently skip later async work.
./scripts/test.sh --filter openingFromMenuBarKeepsTheEntirePopoverOnScreen "$@"
./scripts/test.sh --filter cancellingAMenuDoesNotDisableDismissalWhenTheAppDeactivates "$@"

./scripts/test.sh --filter longConnectionMessagesStayWithinTheDisplay "$@"
./scripts/test.sh --filter settingsUsesOnePanelAndReopensTheSameWindow "$@"

./scripts/test.sh "$@" --filter escapeDismissesPopoverThroughResponderChain
./scripts/test.sh "$@" --filter customControlsDoNotStackNativeRectangularFocusRings
./scripts/test.sh "$@" --filter repinnedStatusItemTracksItsOwnAppearanceWithoutPolling

./scripts/test.sh "$@" --filter unchangedStatusAppearanceDoesNotRewriteTheMenuItem

./scripts/test.sh "$@" --filter menuBarPresentationDoesNotWaitForAnOpeningAnimation
