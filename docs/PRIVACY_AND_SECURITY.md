# Privacy & security

## What the app does

- All financial records live in the app's private storage (`spendwise.sqlite` in the app support directory). There is no
  account, no server component and no upload of transactions, amounts, notes or categories.
- No analytics SDK, no advertising SDK, no crash-reporting SDK in this build. Unhandled errors are logged only to the
  debug console with the error *type* (not message) so user input cannot leak.
- Permissions requested: `RECEIVE_BOOT_COMPLETED` (re-arm reminders), `com.android.vending.BILLING`, and — from the
  notification plugin — `POST_NOTIFICATIONS` and `VIBRATE`; the release APK manifest (verified with `aapt2 dump badging`) also
  contains `INTERNET` and `ACCESS_NETWORK_STATE`, merged from Play Billing / url_launcher dependencies and used only for those. The Android 13+ notification prompt appears **only** when the
  user turns reminders on. No SMS, contacts, call log, accessibility, location, or storage permissions (files are saved and
  opened through Android's system file picker).
- Network: the app makes no network calls of its own except (a) Google Play Billing via the Play Store app and (b) an
  optional HTTPS call to *your* verification backend when `SPENDWISE_VERIFY_URL` is set. Cleartext traffic is disabled.
- Android cloud backup / device-transfer of app data is **disabled** (`allowBackup=false` + `data_extraction_rules`) so
  records are not copied to Google Drive without the user's explicit export.
- Release builds use R8 minification and resource shrinking.

## Limits you must not misrepresent

- **The database is not encrypted by SpendWise.** It relies on Android's per-app sandbox and the device's file-based
  encryption + screen lock. Rooted devices or malware with root could read it. If you want at-rest encryption, add
  SQLCipher (`sqlcipher_flutter_libs` + a key stored in Android Keystore via `flutter_secure_storage`) and then, only after
  verifying it, update the privacy copy. There is no biometric lock in this version (and a lock would not replace encryption).
- **Exports and backups are plain files** (CSV, JSON). The UI warns before saving/sharing. CSV cells beginning with
  `= + - @` are prefixed with `'` to stop spreadsheet formula injection; the importer strips that prefix again.
- **Entitlement caching**: without a backend, "Pro" is granted from Google Play's on-device purchase record for up to 72 h
  at a time. A rooted/tampered device could fake that — acceptable here because Pro only unlocks local conveniences
  (themes, custom ranges, auto-recording). Any future *server-side* Pro feature (cloud sync) must authorise on the
  server using verified purchase tokens, never on the client flag.
- Do not log transaction data. Do not add secrets to the repo: `.gitignore` excludes `.env`, keystores,
  `key.properties`, `google-services.json`, service-account JSON.

## Input validation

Amounts are parsed with a strict regex and capped; strings are length-limited; categories must match the transaction type;
transfers require two distinct wallets; CSV import validates dates, types, amounts, lengths, row/size limits (20,000 rows,
5 MB) and previews before writing; JSON restore validates format/version and runs in one transaction (all-or-nothing).

## Data deletion

Settings → Privacy & data → *Erase all data* (type DELETE) wipes the database, preferences and scheduled reminders.
Uninstalling removes app storage. User-created exports stay where the user saved them. No cloud data exists.
When cloud features are added you must also add account deletion + server-side data deletion and update the policy and
the Play Data safety form (deletion request URL).

## Cloud / Firebase (not configured)

Nothing connects to Firebase. To add it later: create the Firebase project, add `google-services.json` locally (git-ignored),
use Auth + Firestore security rules that scope documents to `request.auth.uid`, encrypt in transit (TLS, default),
implement conflict resolution by `updatedAt` with tombstones (soft deletes already exist), and re-run the privacy review.
