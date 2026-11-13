#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
python3 scripts/test-toolchain.py
python3 scripts/test-build.py
./scripts/test.sh "$@"
./scripts/build.sh release
python3 scripts/test-relay.py "$PWD/build/Limitwen.app/Contents/MacOS/LimitwenRelay"
plutil -lint build/Limitwen.app/Contents/Info.plist
codesign --verify --strict --verbose=2 build/Limitwen.app
echo "All deterministic checks passed. Native interaction and live-account checks are separate."
