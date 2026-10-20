# Architecture

Flutter + Riverpod (3.x) + Drift (SQLite) + GoRouter, Material 3.

```
lib/
  main.dart                 bootstrap: prefs, database file, notifications, billing, error hooks
  app/                      app.dart (MaterialApp.router), router.dart, shell.dart (bottom nav + FAB),
                            providers.dart (all Riverpod wiring), theme.dart
  core/                     money.dart (integer minor units), dates.dart, ids.dart, widgets/ (shared UI)
  domain/                   PURE logic (unit-tested): calculations.dart (summaries, balances, budgets,
                            safe-to-spend), recurrence.dart, reports.dart, enums.dart
  data/
    database/               tables.dart, app_database.dart (+ generated .g.dart), seed.dart
    repositories/           transaction / catalog (categories, wallets, budgets) / recurring / settings
  services/                 ledger_service (post-change hooks), budget_service (+ alert dedupe),
                            notification_service, csv_service, import_service, backup_service,
                            export_helper, crash_reporter, billing/ (entitlement, gateway, verifier, repository)
  features/                 one folder per feature area (screens only; logic lives below)
test/  unit/ db/ widget/    integration_test/
```

## Key decisions

- **Money is `int` minor units** (paise). Parsing/formatting never touches `double`. Max 1,000,000,000.00.
- **Single source of truth is the database.** Dashboard, budgets, reports and balances are *derived* from stored rows by
  pure functions; streams make every screen update immediately after add/edit/delete/import/restore.
- **Transfers are their own type**; they move balances between wallets and are excluded from income/expense/budgets.
- **Dates**: date-only entries are stored at local noon (no DST/time-zone day shifts). Month boundaries use local time.
- **Soft delete + 30-day recovery** for transactions (Undo snackbar, "Recently deleted"). Startup purges older rows.
- **Duplicate prevention for recurring items**: `transactions.occurrence_key` (`ruleId|yyyy-MM-dd`) is UNIQUE, and
  `markPaid` is idempotent. Auto-posting (Pro, per-rule opt-in) catches up missed occurrences exactly once.
- **Budget alerts** are deduplicated by `(budgetId, period, threshold)` in `budget_alerts`.
- **Notifications**: only the *next* occurrence of each rule is scheduled (inexact alarms, no exact-alarm permission),
  everything is rescheduled whenever rules/settings change and at start; boot/package-replace receivers re-arm after
  reboot. Reminder text contains no amounts.
- **Entitlements are separate from financial data** (`services/billing`, SharedPreferences record). Pro is derived by
  `evaluateEntitlement` (pure, tested): server-verified expiry → Pro; otherwise, only if no backend is configured, a
  Google-Play-confirmed purchase counts for a 72-hour grace window and must be re-confirmed. A bare flag never grants Pro.
- **Billing is optional**: `BillingGateway` interface (`PlayBillingGateway`, `UnavailableBillingGateway`, test fakes).
  The free app is fully functional if billing is unavailable.
- **Testability**: all external effects are behind providers (`databaseProvider`, `notificationServiceProvider`,
  `billingGatewayProvider`, `purchaseVerifierProvider`) and overridden in tests.

## Schema & migrations

`AppDatabase.schemaVersion = 1`. Add a step to `migration.onUpgrade` for every schema change and a test that opens a
database file created by the previous version. Foreign keys are enforced (`PRAGMA foreign_keys = ON`).

## Extending

- Cloud sync: implement a `SyncService` over repositories (records already have ids, `updatedAt`, soft deletes).
  Do not enable it without a configured Firebase project and the privacy-policy update described in PRIVACY_AND_SECURITY.md.
- Crashlytics: implement `CrashReporter`; never attach transaction data.
