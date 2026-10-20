import 'package:spendwise/core/dates.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/domain/enums.dart';

/// Totals for a set of transactions. Transfers and soft-deleted rows never
/// count as income or spending.
class PeriodSummary {
  const PeriodSummary({
    required this.incomeMinor,
    required this.expenseMinor,
    required this.incomeCount,
    required this.expenseCount,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.largestExpenses,
  });

  final int incomeMinor;
  final int expenseMinor;
  final int incomeCount;
  final int expenseCount;
  final Map<String, int> expenseByCategory;
  final Map<String, int> incomeByCategory;
  final List<TxnRow> largestExpenses;

  static const empty = PeriodSummary(
    incomeMinor: 0,
    expenseMinor: 0,
    incomeCount: 0,
    expenseCount: 0,
    expenseByCategory: {},
    incomeByCategory: {},
    largestExpenses: [],
  );

  int get netMinor => incomeMinor - expenseMinor;
  int get transactionCount => incomeCount + expenseCount;

  /// Average expense in minor units (integer division, rounded down).
  int get averageExpenseMinor =>
      expenseCount == 0 ? 0 : expenseMinor ~/ expenseCount;

  bool get isEmpty => transactionCount == 0;
}

const String kUncategorized = '_uncategorized';

/// Summarises [txns]. When [asOf] is given, future-dated rows are ignored.
PeriodSummary summarize(Iterable<TxnRow> txns, {DateTime? asOf, int topN = 5}) {
  var income = 0;
  var expense = 0;
  var incomeCount = 0;
  var expenseCount = 0;
  final byExpense = <String, int>{};
  final byIncome = <String, int>{};
  final expenses = <TxnRow>[];
  for (final t in txns) {
    if (t.deletedAt != null || t.type == TxnType.transfer) continue;
    if (asOf != null && t.occurredAt.isAfter(asOf)) continue;
    final key = t.categoryId ?? kUncategorized;
    if (t.type == TxnType.income) {
      income += t.amountMinor;
      incomeCount++;
      byIncome[key] = (byIncome[key] ?? 0) + t.amountMinor;
    } else {
      expense += t.amountMinor;
      expenseCount++;
      byExpense[key] = (byExpense[key] ?? 0) + t.amountMinor;
      expenses.add(t);
    }
  }
  expenses.sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
  return PeriodSummary(
    incomeMinor: income,
    expenseMinor: expense,
    incomeCount: incomeCount,
    expenseCount: expenseCount,
    expenseByCategory: byExpense,
    incomeByCategory: byIncome,
    largestExpenses: expenses.take(topN).toList(),
  );
}

/// Aggregated movement for one wallet, produced by a SQL GROUP BY.
class WalletFlow {
  const WalletFlow(this.walletId, this.type, this.sumMinor);
  final String walletId;
  final TxnType type;
  final int sumMinor;
}

/// Sum of transfers received by a wallet.
class TransferInFlow {
  const TransferInFlow(this.walletId, this.sumMinor);
  final String walletId;
  final int sumMinor;
}

/// balance = opening + income - expense - transfersOut + transfersIn.
/// Transfers move money between wallets and never change the combined total.
Map<String, int> computeBalances(
  Iterable<WalletRow> wallets,
  Iterable<WalletFlow> flows,
  Iterable<TransferInFlow> transfersIn,
) {
  final result = {for (final w in wallets) w.id: w.openingBalanceMinor};
  for (final f in flows) {
    if (!result.containsKey(f.walletId)) continue;
    final sign = f.type == TxnType.income
        ? 1
        : -1; // expense & transfer-out reduce
    result[f.walletId] = result[f.walletId]! + sign * f.sumMinor;
  }
  for (final t in transfersIn) {
    if (!result.containsKey(t.walletId)) continue;
    result[t.walletId] = result[t.walletId]! + t.sumMinor;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Budgets
// ---------------------------------------------------------------------------

enum BudgetStatus { ok, warning, over }

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.spentMinor,
    required this.carryMinor,
  });

  final BudgetRow budget;
  final int spentMinor;
  final int carryMinor;

  int get limitMinor => budget.amountMinor + carryMinor;
  int get remainingMinor => limitMinor - spentMinor;

  /// Whole-number percentage of the limit that has been used (may exceed 100).
  int get percentUsed => limitMinor <= 0 ? 0 : (spentMinor * 100) ~/ limitMinor;

  BudgetStatus get status {
    if (spentMinor > limitMinor) return BudgetStatus.over;
    if (percentUsed >= budget.warnPercent) return BudgetStatus.warning;
    return BudgetStatus.ok;
  }
}

bool budgetActiveIn(BudgetRow b, DateTime month) {
  final m = startOfMonth(month);
  if (m.isBefore(startOfMonth(b.startMonth))) return false;
  final end = b.endMonth;
  if (end != null && m.isAfter(startOfMonth(end))) return false;
  return true;
}

/// Unspent amount carried into [month]. Only non-zero when [BudgetRow.rollover]
/// is explicitly enabled. [spentIn] returns spending for a given month start.
int rolloverCarry(
  BudgetRow b,
  DateTime month,
  int Function(DateTime monthStart) spentIn,
) {
  if (!b.rollover) return 0;
  final target = startOfMonth(month);
  var cursor = startOfMonth(b.startMonth);
  // Guard against very old start months: only look back 36 months.
  final earliest = DateTime(target.year, target.month - 36);
  if (cursor.isBefore(earliest)) cursor = earliest;
  var carry = 0;
  while (cursor.isBefore(target)) {
    final limit = b.amountMinor + carry;
    final left = limit - spentIn(cursor);
    carry = left > 0 ? left : 0;
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return carry;
}

// ---------------------------------------------------------------------------
// Safe to spend
// ---------------------------------------------------------------------------

enum SafeStatus { noBase, overspent, ok, periodEnded }

class SafeToSpend {
  const SafeToSpend({
    required this.status,
    required this.baseMinor,
    required this.spentMinor,
    required this.committedMinor,
    required this.availableMinor,
    required this.perDayMinor,
    required this.daysRemaining,
    required this.basedOnBudget,
    required this.assumptions,
  });

  final SafeStatus status;
  final int baseMinor;
  final int spentMinor;
  final int committedMinor;
  final int availableMinor;
  final int perDayMinor;
  final int daysRemaining;
  final bool basedOnBudget;
  final List<String> assumptions;
}

/// Transparent safe-to-spend estimate:
///   available = base - spent - committed
///   perDay    = available / days remaining (including today)
/// where base is the overall monthly budget (incl. any explicit rollover) or,
/// when no budget exists, income recorded for the month. It is an estimate of
/// *your own records*, not a bank balance.
SafeToSpend computeSafeToSpend({
  required DateTime today,
  required DateTime month,
  required int? overallBudgetMinor,
  required int incomeMinor,
  required int spentMinor,
  required int committedMinor,
  DateTime? periodEndInclusive,
}) {
  final todayD = dateOnly(today);
  final monthStart = startOfMonth(month);
  final thisMonth = startOfMonth(todayD);
  final basedOnBudget = overallBudgetMinor != null;
  final base = overallBudgetMinor ?? (incomeMinor > 0 ? incomeMinor : 0);
  final assumptions = <String>[
    if (basedOnBudget)
      'Base: your overall monthly budget.'
    else
      'Base: income recorded this month (no overall budget set).',
    'Spent: expenses recorded up to today; transfers are ignored.',
    if (committedMinor > 0)
      'Committed: bills and recurring expenses still due this period.',
    'This is an estimate from your own records, not a bank balance.',
  ];

  SafeToSpend build(SafeStatus s, int available, int perDay, int days) =>
      SafeToSpend(
        status: s,
        baseMinor: base,
        spentMinor: spentMinor,
        committedMinor: committedMinor,
        availableMinor: available,
        perDayMinor: perDay,
        daysRemaining: days,
        basedOnBudget: basedOnBudget,
        assumptions: assumptions,
      );

  if (base <= 0) return build(SafeStatus.noBase, 0, 0, 0);

  final available = base - spentMinor - committedMinor;
  if (monthStart.isBefore(thisMonth)) {
    return build(SafeStatus.periodEnded, available, 0, 0);
  }

  late final DateTime periodStart;
  late final DateTime end;
  if (monthStart.isAfter(thisMonth)) {
    periodStart = monthStart;
    end = DateTime(
      monthStart.year,
      monthStart.month,
      daysInMonth(monthStart.year, monthStart.month),
    );
  } else {
    periodStart = todayD;
    end = periodEndInclusive != null
        ? dateOnly(periodEndInclusive)
        : DateTime(
            todayD.year,
            todayD.month,
            daysInMonth(todayD.year, todayD.month),
          );
  }
  var days = end.difference(periodStart).inDays + 1;
  if (days < 1) days = 1;
  if (available <= 0) return build(SafeStatus.overspent, available, 0, days);
  return build(SafeStatus.ok, available, available ~/ days, days);
}
