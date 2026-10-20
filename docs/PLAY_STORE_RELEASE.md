# Google Play release guide

Nothing in this guide has been submitted: publishing, purchases and Play Console changes need **your** explicit action.

## 0. Current platform requirement (checked 20 Oct 2026)

New apps and updates must target **Android 16 / API 36** (deadline 31 Aug 2026; extension requests to 1 Nov 2026 exist);
existing apps must target ≥ API 35. This project targets API 36 (`flutter.targetSdkVersion`). Re-check
<https://developer.android.com/google/play/requirements/target-sdk> before every release. Edge-to-edge and large-screen
(no orientation locking) behaviour of API 36 applies; the app does not lock orientation.

## 1. One-time setup

1. **Application id** – decide the final id (default `in.creovix.spendwise`; use `-PapplicationId=` or edit
   `android/app/build.gradle.kts`). Permanent once published.
2. **Upload key** (keep it and its passwords private, back it up, never commit):
   ```bash
   keytool -genkeypair -v -keystore C:/secure/upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```
   Create `android/key.properties`:
   ```
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=C:/secure/upload-keystore.jks
   ```
   Enrol in Play App Signing when creating the app (Google holds the app-signing key).
3. **Policy URLs** – host the privacy policy (text in `lib/features/settings/legal_text.dart`) at a public HTTPS URL,
   replace the `[DATE]` / `[SUPPORT EMAIL]` placeholders, and add the URL in Play Console. Build with
   `--dart-define=SPENDWISE_SUPPORT_EMAIL=...`.
4. **Billing** – follow [BILLING_SETUP.md](BILLING_SETUP.md).

## 2. Build

```bash
flutter pub get && dart run build_runner build
flutter analyze && flutter test
flutter build appbundle --release --dart-define=SPENDWISE_SUPPORT_EMAIL=support@yourdomain.example
# output: build/app/outputs/bundle/release/app-release.aab
```
Without `key.properties` the build is signed with the **debug key** and Play will reject it. Bump `version:` in
`pubspec.yaml` (`1.0.0+1` → build number must increase for every upload).

## 3. Store listing (draft copy — edit freely)

- **App name:** SpendWise – Expense & Budget Tracker
- **Short description (≤80):** Private expense tracker & budget planner. Offline. No sign-up.
- **Full description:**
  > SpendWise helps you know your money. Record income and expenses in seconds, set monthly and category budgets, get
  > bill reminders, and see where your money goes — all stored privately on your phone.
  >
  > • Unlimited income & expense entries, free forever • Works fully offline, no account required • Safe-to-Spend estimate
  > with the maths shown • Monthly & category budgets with alerts at 80% and 100% • Rent, bill & subscription reminders
  > (reminders never pay or record anything for you) • Reports from daily to yearly, trends and top expenses • Wallets for
  > cash, bank and UPI records, with transfers • CSV import/export and local backup • Light & dark themes • INR by
  > default, other currencies supported.
  >
  > SpendWise does not connect to your bank, does not read your SMS and does not sell data. Balances reflect what you record.
  > Optional SpendWise Pro (auto-renewing subscription, price shown in Google Play) adds custom report ranges, extra
  > themes and automatic recording of recurring items.
- **Graphics:** 512×512 icon: `assets/store/icon-512.png`. Feature graphic (1024×500) and phone screenshots must be captured
  from the real app (see §7) — screenshots are not fabricated in this repository.

## 4. Declarations (guidance — answer according to the final build)

**Data safety** (for this build): *Does the app collect or share data?* — **No data collected/shared by the app** if you ship
exactly this build with no verifier URL. Financial info is stored on-device only; Google Play Billing is handled by Google
(purchase history is Google's, not collected by you). If you configure a verification backend: declare *Purchases* /
*Other financial info (purchase token)* as collected, for "App functionality", encrypted in transit, deletable on request.
If you add Crashlytics/analytics/cloud sync, update the form and the privacy policy **before** release.
Security practices: data encrypted in transit — yes if verifier used; users can request deletion — "no data collected" or your process.

**Financial features declaration:** declare that the app is a *personal finance tracker / budgeting* app with no banking,
lending, payments or investment features; no loans, no money transfer, no crypto, no financial advice. (Wallet "transfers" are
bookkeeping entries only.)

**Content rating (IARF) questionnaire:** violence none, sexual content none, language none, controlled substances none,
gambling none, user-generated content none, shares location no, digital purchases yes (subscription). Expected: Everyone / 3+.

**Target audience:** 18+ / general adult (not designed for children). **Ads:** declare "No ads". **App access:** no login;
all functionality available without special instructions. **Permissions:** notifications (opt-in), boot completed
(reminder rescheduling), billing. **News / health / government declarations:** not applicable.

## 5. Testing instructions for Play review / testers

Install → skip or finish onboarding → add an income and an expense with the + button → create a budget under Budgets →
Settings → Bill reminders → add a reminder due tomorrow, turn notifications on (grant permission) → Import & export →
export CSV. No account or credentials are needed. Pro purchases: use a license-tester account on the internal track.

## 6. Release checklist

- [ ] Final application id decided; `versionName`/`versionCode` bumped
- [ ] Upload key created, `android/key.properties` present, **not committed**
- [ ] `flutter analyze`, `flutter test` green; integration test run on a device/emulator
- [ ] Manual device pass (§7), including notifications after reboot and with permission denied
- [ ] Release AAB built and signed with the upload key (verify: `keytool -printcert -jarfile app-release.aab`)
- [ ] Privacy policy URL live, placeholders replaced; support email set
- [ ] Billing products created & activated; license-tester purchase scenarios passed; verification backend (if used) live
- [ ] Data safety, Financial features, content rating, target audience, ads declarations completed
- [ ] Store listing text, icon, feature graphic, ≥2 real phone screenshots (+7"/10" tablet screenshots recommended)
- [ ] Internal → closed testing (new personal accounts need 12 testers for 14 days before production access — check current rules)
- [ ] Pre-launch report reviewed; crash/ANR free; then staged production rollout

## 6b. Release smoke test (mandatory — it caught a ship-blocking bug)

Unit/widget tests run un-minified, so they cannot see R8 problems. Plugins such as `shared_preferences` call their own
Kotlin classes via JNI by exact name/signature; R8 renamed `kotlin.coroutines.Continuation` and stripped classes, `main()`
threw before `runApp`, and the release app sat on the system splash forever (no crash report). `android/app/proguard-rules.pro`
now keeps `kotlin.**`, `kotlinx.coroutines.**`, `io.flutter.plugins.**` and the JNI package. **After adding or upgrading any plugin,
install the release APK on a device/emulator and verify:** it reaches onboarding, Skip → Home, add an expense, restart the app and the
expense is still there. If it hangs on the splash, temporarily print the error in `LocalCrashReporter.recordError` and read
`adb logcat` to find the missing class, then add a keep rule.

## 7. Manual verification still required (could not be automated here)

Already verified on an API 35 x86_64 emulator: debug and R8-minified release start-up, onboarding→add→persist→restart→export content (integration test), and that bill reminders are registered with AlarmManager at 09:00 IST. Still needed on real hardware: notification *delivery* and the permission prompt UX on Android 13–16 · reminders surviving reboot · Play Billing end-to-end ·
real-device performance in release mode (`flutter run --release --profile` traces) · TalkBack pass · very small / tablet
screens · system file-picker save/open for CSV and backup · screenshots.

## 8. Known issues & limitations

- No encryption at rest, no biometric lock (see PRIVACY_AND_SECURITY.md).
- No cloud backup/sync, PDF export, widgets, ads, analytics or crash reporting in this version.
- Without a verification backend Pro is time-boxed (72 h) and re-confirmed through Google Play at each launch.
- Currency change only changes the display symbol/format; amounts are not converted. Only 2-decimal currencies are offered.
- Balances/Safe-to-Spend are estimates from user-entered data; the dashboard "as of" boundary is evaluated when data changes
  (not at midnight while the app stays open).
- Database schema is v1; no historical migrations exist yet.
- Debug builds are large (all ABIs, 185 MB); the release AAB is split per ABI by Play.
