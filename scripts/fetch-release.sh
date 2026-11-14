#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p vendor
staged="$(mktemp "$PWD/vendor/.release-XXXXXX")"
trap 'rm -f "$staged"' EXIT
curl --fail --location --proto '=https' --proto-redir '=https' \
  'https://github.com/uzair166/limitwen-app/releases/download/v0.1.1/Limitwen-0.1.1-universal-notarized.zip' \
  --output "$staged"
node --input-type=module - "$staged" <<'JS'
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { release } from './scripts/native-install.mjs';
if (createHash('sha256').update(readFileSync(process.argv[2])).digest('hex') !== release.sha256) {
  throw new Error('Release checksum mismatch');
}
JS
mv "$staged" vendor/Limitwen.zip
