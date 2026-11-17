# Release signing

Android only installs an update over an existing install when both APKs are
signed by the same certificate. The release job therefore refuses to publish
anything unless a real release keystore is available, and it verifies the
finished APK against that keystore before the release is written.

## What a human must hold

Keep these **outside the repository** (password manager plus an offline backup):

| Item | Purpose |
| --- | --- |
| `khutati-release.jks` (or `.keystore`) | The private signing key. Never commit it. |
| Store password | Opens the keystore. |
| Key alias | Selects the release key. |
| Key password | Unlocks that key. |

GitHub stores an encrypted copy as four repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Losing the keystore means every user must uninstall the app once before they
can install a later build, because Android treats it as a different app.

## Create the key (once, on a trusted machine)

```bash
keytool -genkeypair -v \
  -keystore khutati-release.jks \
  -alias khutati \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -storetype PKCS12

base64 -w0 khutati-release.jks > khutati-release.jks.b64
gh secret set ANDROID_KEYSTORE_BASE64 < khutati-release.jks.b64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

Delete the `.b64` file afterwards. Do not paste the passwords or the base64
into an issue, a commit, a CI log or a chat.

For a **local** release build, write `android/key.properties` (gitignored):

```properties
storeFile=khutati-release.jks
storePassword=...
keyAlias=khutati
keyPassword=...
```

and place `khutati-release.jks` in `android/app/`. Without these files a local
`flutter build apk --release` falls back to debug signing; CI never does.

## What CI does

In `.github/workflows/android.yml`, `Build signed release APK`:

1. **Requires all four secrets.** A missing value fails the job with
   `Release signing secrets are missing; refusing to publish a debug-signed
   APK.` There is no debug-signing fallback in CI.
2. **Validates the keystore before building** with
   `keytool -list ... -alias ...`, so a wrong password fails early.
3. Writes the keystore and `android/key.properties` only on the runner; both
   are gitignored and never uploaded.
4. **Verifies the shipped `Khutati.apk`** after copying it:
   - `apksigner verify --verbose --print-certs` must succeed (the APK is
     actually signed, not just zip-aligned);
   - the signer's SHA-256 fingerprint must equal the fingerprint of the
     `ANDROID_KEYSTORE_BASE64` secret;
   - the signer DN must not contain `CN=Android Debug`.
5. Publishes only after verification, and uploads `build/apk-signature.txt`
   with the APK artifact as evidence. The certificate subject and fingerprint
   are also written to the job's step summary.

The fingerprint comparison is the important part: it proves the published file
was signed by the secret-backed key, not merely by some other release key.

## Rotation and version discipline

A new certificate cannot update an older install. If the key must be replaced,
publish it as a new app identity (or accept one uninstall), and keep the old
keystore archived until users have migrated. Bump `version:` in `pubspec.yaml`
and `AppInfo` together — CI checks they match, and the in-app updater only
offers a build with a higher `versionCode`.
