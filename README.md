# SpendWise

**Know Your Money. Own Your Future.**
A privacy-first, offline-first personal finance and expense tracker for Android, built with Flutter.

- Application ID: `in.creovix.spendwise` (configurable — see below)
- Free core app, optional **SpendWise Pro** subscription (Google Play Billing)
- Currency defaults to INR (₹); records stay on the device; no account needed

> **Status:** feature-complete offline app with real tests. Production release additionally needs the manual
> steps in [docs/PLAY_STORE_RELEASE.md](docs/PLAY_STORE_RELEASE.md) (signing key, Play Console products,
> optional verification backend, policy URLs, support email). See "What is real vs. awaiting setup" below.

## Quick start

Requirements: Flutter 3.47+ (Dart 3.13+), JDK 17+ (21 works), Android SDK 36 with build-tools 35/36, NDK 28.2 and
CMake 3.22 (Gradle installs the last two automatically).

```bash
flutter pub get
dart run build_runner build      # regenerates lib/data/database/app_database.g.dart
dart format .
flutter analyze
flutter test                     # unit + database + widget tests (host machine)
flutter run                      # on a connected device / emulator
flutter build apk --release      # needs android/key.properties for a Play-uploadable build
flutter build appbundle --release
```

Integration (end-to-end) test, needs an emulator or device:

```bash
flutter test integration_test/app_test.dart -d <deviceId>
```

### Build-time configuration (`--dart-define`)

See `.env.example` for the full list. None of these are secrets and no secret ever belongs in the app.

| Define | Purpose |
|---|---|
| `SPENDWISE_MONTHLY_ID` / `SPENDWISE_ANNUAL_ID` | Google Play subscription product ids |
| `SPENDWISE_VERIFY_URL` | HTTPS base URL of your purchase-verification backend (optional) |
| `SPENDWISE_SUPPORT_EMAIL` | Shown on About & support |
| `SPENDWISE_PACKAGE` | Package name sent to the verifier (must match the application id) |

Change the application id before first publication with `-PapplicationId=com.yourco.spendwise`
(Gradle property) or edit `android/app/build.gradle.kts`; also update `namespace` and the Kotlin package if you
want them to match. **After publishing it can never change.**

## Features

Home dashboard (balance, income/expenses, Safe-to-Spend with visible assumptions, budgets, category chart, bills,
recent items, month selector) · transactions (add/edit/delete with undo + 30-day recovery, search, filters, sort,
paging) · income/expense/transfer with separate accounting · categories (custom, icons, colours, archive) ·
wallets · monthly and category budgets with history, thresholds, optional rollover and once-only alerts ·
reports (day→year, comparisons, trends, top expenses, budget performance, custom ranges in Pro) · recurring items
and bill reminders (never auto-marked paid) · CSV import with preview/validation/duplicate detection, CSV export,
JSON backup/restore · privacy & data tools, erase-all · light/dark themes, accent themes (Pro) · Pro screen with
real Play Billing integration.

## What is real vs. awaiting setup

| Area | State |
|---|---|
| Offline tracking, budgets, reports, reminders, import/export, backup | Implemented and tested |
| Local notifications (bill reminders, budget alerts) | Implemented; needs on-device verification (see release doc) |
| Google Play Billing client | Implemented against `in_app_purchase`; **needs Play Console products + a Play-installed build to test** |
| Server-side purchase verification | Client + contract implemented (`HttpPurchaseVerifier`); **backend not included / not configured** |
| Cloud backup & sync | **Not implemented** (documented seam only). Pro screen says so. |
| Crash reporting / analytics | **None** in this build (privacy-preserving default). `CrashReporter` is the seam for Crashlytics |
| Ads | **None** |
| PDF export | **Not implemented** (no fake button) |
| Release signing | Needs your upload key (`android/key.properties`) |

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/PRIVACY_AND_SECURITY.md](docs/PRIVACY_AND_SECURITY.md)
- [docs/BILLING_SETUP.md](docs/BILLING_SETUP.md)
- [docs/PLAY_STORE_RELEASE.md](docs/PLAY_STORE_RELEASE.md) — checklist, listing copy, declarations, known issues
