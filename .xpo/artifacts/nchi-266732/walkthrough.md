# Walkthrough: stable local code signing

## Why
macOS ties privacy grants (Accessibility, used by WindowRaiser) to an app's *designated requirement*. An ad hoc signature has no certificate, so the requirement falls back to the cdhash, the hash of the binary. Every rebuild changes the hash, and TCC sees a new app. When a build is signed with a certificate, the requirement becomes `identifier "com.github.nicbet.nocchi" and certificate leaf = H"…"`, which stays the same across rebuilds.

This is not notarization. Notarization needs a paid Developer ID. The self-signed certificate only matters on the machine that holds it. Anyone else still uses right-click → Open.

## Pieces
- **`scripts/create-signing-cert.sh`** is ported from colorsip.
  - It makes an RSA certificate with openssl, restricted to the codeSigning extended key usage.
  - It imports the certificate into the login keychain with `-T /usr/bin/codesign`, so codesign can use the key without a prompt.
  - It trusts the certificate for code signing. This step asks for the user's password.
  - If the identity already exists, the script does nothing.
  - The identity is `${SIGNING_IDENTITY:-Local App Signing}`. The name is shared on purpose, so AgentSpaces (and later colorsip) sign with the same identity. Colorsip's xcconfig step was dropped because this is a SwiftPM build.
- **`scripts/bundle.sh`** checks `security find-identity -v -p codesigning` for the identity. If it's there, it signs with it. If not, it signs ad hoc and prints a hint. The hint goes to **stderr** because `dev.sh` takes the app path from the last line of stdout.
- **Makefile** has two new targets: `signing-cert`, and `reset-permissions` (`tccutil reset Accessibility com.github.nicbet.nocchi`). The help column is wider to fit the longer names.
- **README** explains the one-time setup.

## Verified
- Without the identity, the build is `Signature=adhoc` and the requirement is a cdhash.
- With it, the requirement is the certificate leaf and identical after a rebuild.
- Switching from ad hoc to the certificate resets the Accessibility grant once. After that it holds.