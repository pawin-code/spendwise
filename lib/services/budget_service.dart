import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/catalog_repositories.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/services/notification_service.dart';

/// Computes budget progress from stored transactions.
class BudgetService {
  BudgetService(this.budgets, this.transactions);
  final BudgetRepository budgets;
  final TransactionRepository transactions;

  Future<List<BudgetProgress>> progressForMonth(
    DateTime month, {
    DateTime? now,
  }) async {
    final asOf = now ?? DateTime.now();
    final all = (await budgets.getAll())
        .where((b) => budgetActiveIn(b, month))
        .toList();
    if (all.isEmpty) return const [];
    final summaryCache = <String, PeriodSummary>{};
    Future<PeriodSummary> summaryFor(DateTime m) async {
      final key = monthKey(m);
      return summaryCache[key] ??= summarize(
        await transactions.getRange(startOfMonth(m), startOfNextMonth(m)),
        asOf: asOf,
      );
    }

    // Pre-load previous months needed for explicit rollover budgets.
    final target = startOfMonth(month);
    for (final b in all.where((b) => b.rollover)) {
      var c = startOfMonth(b.startMonth);
      final earliest = DateTime(target.year, target.month - 36);
      if (c.isBefore(earliest)) c = earliest;
      while (c.isBefore(target)) {
        await summaryFor(c);
        c = DateTime(c.year, c.month + 1);
      }
    }
    final current = await summaryFor(target);

    int spentOf(BudgetRow b, PeriodSummary s) => b.categoryId == null
        ? s.expenseMinor
        : (s.expenseByCategory[b.categoryId] ?? 0);

    return [
      for (final b in all)
        BudgetProgress(
          budget: b,
          spentMinor: spentOf(b, current),
          carryMinor: rolloverCarry(
            b,
            target,
            (m) => spentOf(b, summaryCache[monthKey(m)] ?? PeriodSummary.empty),
          ),
        ),
    ];
  }
}

/// Fires threshold notifications at most once per budget, period and threshold.
class BudgetAlertService {
  BudgetAlertService({
    required this.budgetService,
    required this.budgets,
    required this.categories,
    required this.notifications,
  });

  final BudgetService budgetService;
  final BudgetRepository budgets;
  final CategoryRepository categories;
  final NotificationService notifications;

  /// Evaluates the month containing [when]. Returns the thresholds notified.
  Future<List<String>> evaluate(
    DateTime when, {
    required bool enabled,
    required CurrencyInfo currency,
    DateTime? now,
  }) async {
    final fired = <String>[];
    final progress = await budgetService.progressForMonth(when, now: now);
    final catNames = {for (final c in await categories.getAll()) c.id: c.name};
    final period = monthKey(when);
    for (final p in progress) {
      final thresholds = <int>{p.budget.warnPercent, 100}.toList()..sort();
      for (final t in thresholds) {
        final reached = t >= 100
            ? p.spentMinor >= p.limitMinor
            : p.percentUsed >= t;
        if (!reached || p.limitMinor <= 0) continue;
        // Only the highest reached threshold is announced if several are crossed at once.
        final isHighestReached = thresholds.where((x) => x > t).every((x) {
          final r = x >= 100
              ? p.spentMinor >= p.limitMinor
              : p.percentUsed >= x;
          return !r;
        });
        final isNew = await budgets.tryRecordAlert(p.budget.id, period, t);
        if (!isNew || !enabled || !isHighestReached) continue;
        final scope = p.budget.categoryId == null
            ? 'Overall budget'
            : '${catNames[p.budget.categoryId] ?? 'Category'} budget';
        final title = t >= 100 ? '$scope reached' : '$scope at $t%';
        final body = t >= 100
            ? 'You have spent ${formatMinor(p.spentMinor, currency: currency)} of ${formatMinor(p.limitMinor, currency: currency)}.'
            : '${formatMinor(p.remainingMinor, currency: currency)} left this month.';
        await notifications.showBudgetAlert(
          key: '${p.budget.id}:$period:$t',
          title: title,
          body: body,
        );
        fired.add('${p.budget.id}:$t');
      }
    }
    return fired;
  }
}
