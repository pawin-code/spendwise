import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/catalog_repositories.dart';
import 'package:spendwise/data/repositories/recurring_repository.dart';
import 'package:spendwise/data/repositories/settings_repository.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/domain/recurrence.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise/services/billing/billing_config.dart';
import 'package:spendwise/services/billing/billing_gateway.dart';
import 'package:spendwise/services/billing/purchase_verifier.dart';
import 'package:spendwise/services/billing/subscription_repository.dart';
import 'package:spendwise/services/budget_service.dart';
import 'package:spendwise/services/csv_service.dart';
import 'package:spendwise/services/import_service.dart';
import 'package:spendwise/services/ledger_service.dart';
import 'package:spendwise/services/notification_service.dart';

// ---------------------------------------------------------------------------
// Infrastructure (overridden in main() / tests)
// ---------------------------------------------------------------------------

final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NoopNotificationService(),
);

final billingGatewayProvider = Provider<BillingGateway>(
  (ref) => UnavailableBillingGateway(),
);

final purchaseVerifierProvider = Provider<PurchaseVerifier>(
  (ref) => BillingConfig.verifierConfigured
      ? HttpPurchaseVerifier(BillingConfig.verifyUrl)
      : const UnconfiguredPurchaseVerifier(),
);

// ---------------------------------------------------------------------------
// Repositories & services
// ---------------------------------------------------------------------------

final transactionRepositoryProvider = Provider(
  (ref) => TransactionRepository(ref.watch(databaseProvider)),
);
final categoryRepositoryProvider = Provider(
  (ref) => CategoryRepository(ref.watch(databaseProvider)),
);
final walletRepositoryProvider = Provider(
  (ref) => WalletRepository(ref.watch(databaseProvider)),
);
final budgetRepositoryProvider = Provider(
  (ref) => BudgetRepository(ref.watch(databaseProvider)),
);
final recurringRepositoryProvider = Provider(
  (ref) => RecurringRepository(
    ref.watch(databaseProvider),
    ref.watch(transactionRepositoryProvider),
  ),
);
final settingsRepositoryProvider = Provider(
  (ref) => SettingsRepository(ref.watch(sharedPrefsProvider)),
);
final backupServiceProvider = Provider(
  (ref) => BackupService(ref.watch(databaseProvider)),
);
final csvServiceProvider = Provider((ref) => const CsvService());

final importServiceProvider = Provider(
  (ref) => ImportService(
    db: ref.watch(databaseProvider),
    transactions: ref.watch(transactionRepositoryProvider),
    categories: ref.watch(categoryRepositoryProvider),
    wallets: ref.watch(walletRepositoryProvider),
  ),
);

final budgetServiceProvider = Provider(
  (ref) => BudgetService(
    ref.watch(budgetRepositoryProvider),
    ref.watch(transactionRepositoryProvider),
  ),
);

final ledgerServiceProvider = Provider((ref) {
  return LedgerService(
    transactions: ref.watch(transactionRepositoryProvider),
    alerts: BudgetAlertService(
      budgetService: ref.watch(budgetServiceProvider),
      budgets: ref.watch(budgetRepositoryProvider),
      categories: ref.watch(categoryRepositoryProvider),
      notifications: ref.watch(notificationServiceProvider),
    ),
    // Budget alerts need both the alert switch and the user's explicit notification opt-in.
    alertsEnabled: () {
      final s = ref.read(settingsProvider);
      return s.budgetAlertsEnabled && s.notificationsEnabled;
    },
    currency: () => ref.read(currencyProvider),
  );
});

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();

  Future<void> update(AppSettings Function(AppSettings s) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

final currencyProvider = Provider<CurrencyInfo>(
  (ref) =>
      currencyByCode(ref.watch(settingsProvider.select((s) => s.currencyCode))),
);

// ---------------------------------------------------------------------------
// Subscription / entitlement
// ---------------------------------------------------------------------------

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  final repo = SubscriptionRepository(
    gateway: ref.watch(billingGatewayProvider),
    verifier: ref.watch(purchaseVerifierProvider),
    prefs: ref.watch(sharedPrefsProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

class BillingNotifier extends Notifier<BillingState> {
  StreamSubscription<BillingState>? _sub;

  @override
  BillingState build() {
    final repo = ref.watch(subscriptionRepositoryProvider);
    _sub = repo.stream.listen((s) => state = s);
    ref.onDispose(() => _sub?.cancel());
    return repo.current;
  }
}

final billingProvider = NotifierProvider<BillingNotifier, BillingState>(
  BillingNotifier.new,
);

/// True only when the entitlement rules say so (never from a bare flag).
final isProProvider = Provider<bool>(
  (ref) => ref.watch(billingProvider).entitlement.isPro,
);

// ---------------------------------------------------------------------------
// Catalog data
// ---------------------------------------------------------------------------

final categoriesProvider = StreamProvider<List<CategoryRow>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);
final allCategoriesProvider = StreamProvider<List<CategoryRow>>(
  (ref) =>
      ref.watch(categoryRepositoryProvider).watchAll(includeArchived: true),
);
final walletsProvider = StreamProvider<List<WalletRow>>(
  (ref) => ref.watch(walletRepositoryProvider).watchAll(),
);
final allWalletsProvider = StreamProvider<List<WalletRow>>(
  (ref) => ref.watch(walletRepositoryProvider).watchAll(includeArchived: true),
);
final balancesProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchBalances(),
);
final budgetsProvider = StreamProvider<List<BudgetRow>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchAll(),
);
final rulesProvider = StreamProvider<List<RuleRow>>(
  (ref) => ref.watch(recurringRepositoryProvider).watchAll(),
);
final transactionCountProvider = StreamProvider<int>(
  (ref) => ref.watch(transactionRepositoryProvider).watchCount(),
);
final deletedTxnsProvider = StreamProvider<List<TxnRow>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchDeleted(),
);

Map<String, CategoryRow> categoryMap(List<CategoryRow> list) => {
  for (final c in list) c.id: c,
};

// ---------------------------------------------------------------------------
// Month selection & dashboard
// ---------------------------------------------------------------------------

class SelectedMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => startOfMonth(DateTime.now());

  void set(DateTime m) => state = startOfMonth(m);
  void shift(int months) => state = DateTime(state.year, state.month + months);
}

final selectedMonthProvider = NotifierProvider<SelectedMonthNotifier, DateTime>(
  SelectedMonthNotifier.new,
);

/// All non-deleted transactions of the selected month (including future-dated).
final monthTxnsProvider = StreamProvider.autoDispose<List<TxnRow>>((ref) {
  final m = ref.watch(selectedMonthProvider);
  return ref
      .watch(transactionRepositoryProvider)
      .watchRange(startOfMonth(m), startOfNextMonth(m));
});

/// Totals for the selected month. Future-dated rows are excluded here and
/// reported separately.
final monthSummaryProvider = Provider.autoDispose<AsyncValue<PeriodSummary>>((
  ref,
) {
  return ref
      .watch(monthTxnsProvider)
      .whenData((rows) => summarize(rows, asOf: DateTime.now()));
});

final budgetProgressProvider = FutureProvider.autoDispose<List<BudgetProgress>>(
  (ref) async {
    final m = ref.watch(selectedMonthProvider);
    ref.watch(monthTxnsProvider); // recompute whenever transactions change
    ref.watch(budgetsProvider);
    return ref.watch(budgetServiceProvider).progressForMonth(m);
  },
);

class DashboardExtras {
  const DashboardExtras({
    required this.committedMinor,
    required this.futureExpenseMinor,
    required this.futureIncomeMinor,
  });
  final int committedMinor;
  final int futureExpenseMinor;
  final int futureIncomeMinor;
}

/// Amount still committed in the selected month: unpaid bills/recurring
/// expenses plus future-dated expenses.
final dashboardExtrasProvider =
    Provider.autoDispose<AsyncValue<DashboardExtras>>((ref) {
      final month = ref.watch(selectedMonthProvider);
      final rowsAsync = ref.watch(monthTxnsProvider);
      final rules = ref.watch(rulesProvider).value ?? const <RuleRow>[];
      return rowsAsync.whenData((rows) {
        final now = DateTime.now();
        var futureExpense = 0, futureIncome = 0;
        for (final t in rows) {
          if (t.deletedAt != null ||
              t.type == TxnType.transfer ||
              !t.occurredAt.isAfter(now)) {
            continue;
          }
          if (t.type == TxnType.expense) {
            futureExpense += t.amountMinor;
          } else {
            futureIncome += t.amountMinor;
          }
        }
        final thisMonth = startOfMonth(now);
        var committed = futureExpense;
        if (!month.isBefore(thisMonth)) {
          final monthEnd = DateTime(
            month.year,
            month.month,
            daysInMonth(month.year, month.month),
          );
          for (final r in rules.where(
            (r) => r.active && r.type == CategoryType.expense,
          )) {
            final from = month.isAfter(thisMonth) && r.nextDue.isBefore(month)
                ? month
                : r.nextDue;
            final occ = occurrencesBetween(
              start: r.startDate,
              f: r.frequency,
              interval: r.intervalCount,
              from: from,
              to: monthEnd,
              end: r.endDate,
            );
            committed += occ.length * r.amountMinor;
          }
        }
        return DashboardExtras(
          committedMinor: committed,
          futureExpenseMinor: futureExpense,
          futureIncomeMinor: futureIncome,
        );
      });
    });

/// Safe-to-spend for the selected month.
final safeToSpendProvider = Provider.autoDispose<AsyncValue<SafeToSpend>>((
  ref,
) {
  final month = ref.watch(selectedMonthProvider);
  final summary = ref.watch(monthSummaryProvider);
  final extras = ref.watch(dashboardExtrasProvider);
  final budgets = ref.watch(budgetProgressProvider);
  final settings = ref.watch(settingsProvider);
  if (summary.hasError) {
    return AsyncValue.error(
      summary.error!,
      summary.stackTrace ?? StackTrace.empty,
    );
  }
  if (!summary.hasValue || !extras.hasValue || !budgets.hasValue) {
    return const AsyncValue.loading();
  }
  final s = summary.requireValue;
  final e = extras.requireValue;
  final overall = budgets.requireValue
      .where((p) => p.budget.categoryId == null)
      .firstOrNull;
  final now = DateTime.now();
  DateTime? periodEnd;
  final incomeDay = settings.plannedIncomeDay;
  if (incomeDay != null && isSameMonth(month, now)) {
    // Period ends the day before the next planned income date.
    var next = DateTime(
      now.year,
      now.month,
      incomeDay.clamp(1, daysInMonth(now.year, now.month)),
    );
    if (!next.isAfter(dateOnly(now))) {
      final nm = DateTime(now.year, now.month + 1);
      next = DateTime(
        nm.year,
        nm.month,
        incomeDay.clamp(1, daysInMonth(nm.year, nm.month)),
      );
    }
    final monthLast = DateTime(
      now.year,
      now.month,
      daysInMonth(now.year, now.month),
    );
    final candidate = next.subtract(const Duration(days: 1));
    periodEnd = candidate.isBefore(monthLast) ? candidate : monthLast;
  }
  return AsyncValue.data(
    computeSafeToSpend(
      today: now,
      month: month,
      overallBudgetMinor: overall?.limitMinor,
      incomeMinor: s.incomeMinor,
      spentMinor: s.expenseMinor,
      committedMinor: e.committedMinor,
      periodEndInclusive: periodEnd,
    ),
  );
});

final recentTxnsProvider = StreamProvider.autoDispose<List<TxnView>>((ref) {
  final m = ref.watch(selectedMonthProvider);
  return ref
      .watch(transactionRepositoryProvider)
      .watchViews(
        TxnFilter(
          from: startOfMonth(m),
          toExclusive: startOfNextMonth(m),
          limit: 5,
        ),
      );
});

// ---------------------------------------------------------------------------
// Transactions list
// ---------------------------------------------------------------------------

class TxnFilterNotifier extends Notifier<TxnFilter> {
  @override
  TxnFilter build() => const TxnFilter();

  void set(TxnFilter f) => state = f;
  void loadMore() => state = state.copyWith(limit: state.limit + 50);
  void reset() => state = const TxnFilter();
}

final txnFilterProvider = NotifierProvider<TxnFilterNotifier, TxnFilter>(
  TxnFilterNotifier.new,
);

final txnListProvider = StreamProvider.autoDispose<List<TxnView>>((ref) {
  final f = ref.watch(txnFilterProvider);
  return ref.watch(transactionRepositoryProvider).watchViews(f);
});

final txnViewProvider = StreamProvider.autoDispose.family<TxnView?, String>(
  (ref, id) => ref.watch(transactionRepositoryProvider).watchView(id),
);

// ---------------------------------------------------------------------------
// Startup & background sync
// ---------------------------------------------------------------------------

/// Re-schedules bill reminders whenever rules or notification settings change.
final reminderSyncProvider = Provider<void>((ref) {
  final rules = ref.watch(rulesProvider).value;
  final settings = ref.watch(settingsProvider);
  final notifications = ref.read(notificationServiceProvider);
  if (rules == null) return;
  if (settings.notificationsEnabled) {
    unawaited(
      notifications.rescheduleBillReminders(rules, hour: settings.reminderHour),
    );
  } else {
    unawaited(notifications.cancelAll());
  }
});

/// One-off start-up work. Failures never block the UI.
Future<void> runStartupTasks(ProviderContainer container) async {
  try {
    final txns = container.read(transactionRepositoryProvider);
    await txns.purgeDeletedBefore(
      DateTime.now().subtract(const Duration(days: 30)),
    );
  } catch (_) {}
  try {
    if (container.read(isProProvider)) {
      await container
          .read(recurringRepositoryProvider)
          .postDueAutoRules(DateTime.now());
    }
  } catch (_) {}
}
