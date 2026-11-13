#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-debug}"
app_dir="$PWD/build/Limitwen.app"

ensure_not_running() {
    local process_id executable expected_executable
    expected_executable="$app_dir/Contents/MacOS/Limitwen"
    for process_id in $(pgrep -x Limitwen || true); do
        executable="$(ps -p "$process_id" -o comm= 2>/dev/null || true)"
        if [[ "${executable:A}" == "${expected_executable:A}" ]]; then
            print -u2 "Quit this copy of Limitwen before rebuilding it: $app_dir"
            exit 1
        fi
    done
}
ensure_not_running
xcrun swift build -c "$configuration"
binary_dir="$(xcrun swift build -c "$configuration" --show-bin-path)"
mkdir -p build
if [[ ! -f build/Limitwen.icns || scripts/draw-icon.swift -nt build/Limitwen.icns ]]; then
    xcrun swift scripts/draw-icon.swift "$PWD/build/Limitwen.iconset"
    iconutil -c icns build/Limitwen.iconset -o build/Limitwen.icns
fi

# Never modify the installed executable while compiling/signing its replacement.
staging="$(mktemp -d "$PWD/build/.limitwen-stage-XXXXXX")"
backup="$staging/previous.app"
cleanup() {
    if [[ -d "$backup" && ! -e "$app_dir" ]]; then mv "$backup" "$app_dir"; fi
    rm -rf "$staging"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
staged_app="$staging/Limitwen.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/Limitwen" "$staged_app/Contents/MacOS/Limitwen"
cp "$binary_dir/LimitwenRelay" "$staged_app/Contents/MacOS/LimitwenRelay"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
cp build/Limitwen.icns "$staged_app/Contents/Resources/Limitwen.icns"
codesign --force --sign - "$staged_app/Contents/MacOS/LimitwenRelay"
codesign --force --sign - "$staged_app"
codesign --verify --strict "$staged_app"
ensure_not_running
if [[ -e "$app_dir" ]]; then mv "$app_dir" "$backup"; fi
mv "$staged_app" "$app_dir"
echo "$app_dir"
