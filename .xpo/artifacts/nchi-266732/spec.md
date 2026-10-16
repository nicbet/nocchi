# Stable local code signing

## What
Sign Nocchi.app with a stable self-signed identity, "Local App Signing", so macOS privacy grants (Accessibility) survive rebuilds. Fall back to ad hoc signing when the identity is missing.

## Why
`bundle.sh` signs ad hoc (`codesign --sign -`). Each rebuild gets a new cdhash-based designated requirement, so TCC treats it as a new app. AgentSpaces will reuse the same identity and script.

## How
- `scripts/create-signing-cert.sh`: ported from colorsip. The identity is `${SIGNING_IDENTITY:-Local App Signing}`. It is idempotent (exits early if the identity exists), creates the certificate with openssl, imports it into the login keychain with `-T /usr/bin/codesign`, and trusts it for codeSign. There is no xcconfig, because this is SwiftPM.
- `scripts/bundle.sh`: if `security find-identity -v -p codesigning` lists the identity, sign with it; otherwise sign ad hoc and print a hint to run `make signing-cert`. Honour `SIGNING_IDENTITY` as an override.
- `Makefile`: `signing-cert` and `reset-permissions` targets (`tccutil reset Accessibility com.github.nicbet.nocchi`).
- README: a short note on local signing.

## Acceptance criteria
- Without the identity, `make app` signs ad hoc and prints the hint.
- With the identity, `codesign -dv` shows Authority=Local App Signing and the designated requirement does not depend on the cdhash.
- Running `make signing-cert` a second time is a no-op.

## Decisions
- One shared identity name for all local apps. The user confirmed "Local App Signing".