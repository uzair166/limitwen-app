# Security policy

Report vulnerabilities through [GitHub private vulnerability reporting](https://github.com/uzair166/limitwen-app/security/advisories/new). Include affected version, a minimal sanitized reproduction and the impact. Do not include provider credentials, account configuration or real session transcripts.

Please do not post exploitable details in a public issue before a fix is available. No response-time or long-term-support guarantee is implied. Security fixes target the current release.

Limitwen uses existing local CLI sign-ins without copying credentials. See [architecture and privacy boundaries](docs/ARCHITECTURE.md). Local CLI integrations and observed provider cache formats can change; an upstream change must not lead to invented usage values or a credential-scraping fallback.

Source builds are signed locally for development. A locally built app is not a Developer ID-notarized binary. Distribution tooling must not disable Gatekeeper, remove quarantine attributes or request unrelated permissions to work around missing signing.
