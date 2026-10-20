import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/domain/enums.dart';

import '../helpers.dart';

void main() {
  group('summarize', () {
    test(
      'totals income and expenses and ignores transfers and deleted rows',
      () {
        final s = summarize([
          txn(type: TxnType.income, amount: 500000, category: 'cat_salary'),
          txn(type: TxnType.expense, amount: 12050, category: 'cat_food'),
          txn(type: TxnType.expense, amount: 30000, category: 'cat_transport'),
          txn(
            type: TxnType.transfer,
            amount: 999999,
            toWallet: 'bank',
            category: null,
          ),
          txn(
            type: TxnType.expense,
            amount: 77777,
            deletedAt: DateTime(2026, 10, 16),
          ),
        ]);
        expect(s.incomeMinor, 500000);
        expect(s.expenseMinor, 42050);
        expect(s.netMinor, 457950);
        expect(s.expenseCount, 2);
        expect(s.incomeCount, 1);
        expect(s.transactionCount, 3);
        expect(s.averageExpenseMinor, 21025);
      },
    );

    test('aggregates by category and tracks uncategorised spend', () {
      final s = summarize([
        txn(amount: 100, category: 'cat_food'),
        txn(amount: 250, category: 'cat_food'),
        txn(amount: 400, category: null),
        txn(type: TxnType.income, amount: 900, category: 'cat_salary'),
      ]);
      expect(s.expenseByCategory, {'cat_food': 350, kUncategorized: 400});
      expect(s.incomeByCategory, {'cat_salary': 900});
    });

    test('future-dated rows are excluded when asOf is given', () {
      final now = DateTime(2026, 10, 15, 18);
      final s = summarize([
        txn(amount: 1000, at: DateTime(2026, 10, 15, 12)),
        txn(amount: 5000, at: DateTime(2026, 10, 20, 12)),
      ], asOf: now);
      expect(s.expenseMinor, 1000);
    });

    test('largest expenses are sorted and capped', () {
      final s = summarize([
        for (var i = 1; i <= 8; i++) txn(amount: i * 100),
      ], topN: 3);
      expect(s.largestExpenses.map((t) => t.amountMinor), [800, 700, 600]);
    });

    test('empty input produces a zeroed summary with no division by zero', () {
      final s = summarize([]);
      expect(s.isEmpty, isTrue);
      expect(s.averageExpenseMinor, 0);
    });
  });

  group('computeBalances', () {
    final wallets = [
      walletRow('cash', opening: 10000),
      walletRow('bank', opening: 50000),
    ];

    test('income and expense move a single wallet', () {
      final b = computeBalances(wallets, const [
        WalletFlow('cash', TxnType.income, 20000),
        WalletFlow('cash', TxnType.expense, 5000),
      ], const []);
      expect(b['cash'], 25000);
      expect(b['bank'], 50000);
    });

    test('transfers move money between wallets without changing the total', () {
      final b = computeBalances(
        wallets,
        const [WalletFlow('cash', TxnType.transfer, 4000)],
        const [TransferInFlow('bank', 4000)],
      );
      expect(b['cash'], 6000);
      expect(b['bank'], 54000);
      expect(b.values.fold<int>(0, (a, c) => a + c), 60000);
    });

    test('flows for unknown wallets are ignored', () {
      final b = computeBalances(
        wallets,
        const [WalletFlow('ghost', TxnType.income, 1)],
        const [TransferInFlow('ghost', 1)],
      );
      expect(b.keys, unorderedEquals(['cash', 'bank']));
    });

    test('balances can be negative', () {
      final b = computeBalances(wallets, const [
        WalletFlow('cash', TxnType.expense, 20000),
      ], const []);
      expect(b['cash'], -10000);
    });
  });

  group('budgets', () {
    test('progress, remaining and status thresholds', () {
      BudgetProgress p(int spent) => BudgetProgress(
        budget: budgetRow(amount: 100000, warn: 80),
        spentMinor: spent,
        carryMinor: 0,
      );
      expect(p(0).status, BudgetStatus.ok);
      expect(p(79999).percentUsed, 79);
      expect(p(79999).status, BudgetStatus.ok);
      expect(p(80000).status, BudgetStatus.warning);
      expect(
        p(100000).status,
        BudgetStatus.warning,
      ); // exactly at limit is not "over"
      expect(p(100001).status, BudgetStatus.over);
      expect(p(120000).remainingMinor, -20000);
      expect(p(120000).percentUsed, 120);
    });

    test('active window respects start and end months', () {
      final b = budgetRow(start: DateTime(2026, 3), end: DateTime(2026, 5));
      expect(budgetActiveIn(b, DateTime(2026, 2, 28)), isFalse);
      expect(budgetActiveIn(b, DateTime(2026, 3, 1)), isTrue);
      expect(budgetActiveIn(b, DateTime(2026, 5, 31)), isTrue);
      expect(budgetActiveIn(b, DateTime(2026, 6, 1)), isFalse);
      expect(
        budgetActiveIn(budgetRow(start: DateTime(2026, 3)), DateTime(2030, 1)),
        isTrue,
      );
    });

    test('no rollover unless explicitly enabled', () {
      final b = budgetRow(amount: 100000, start: DateTime(2026, 1));
      expect(rolloverCarry(b, DateTime(2026, 4), (_) => 0), 0);
    });

    test('rollover carries unspent money forward month by month', () {
      final b = budgetRow(
        amount: 100000,
        start: DateTime(2026, 1),
        rollover: true,
      );
      final spent = {
        DateTime(2026, 1): 60000,
        DateTime(2026, 2): 130000,
        DateTime(2026, 3): 0,
      };
      // Jan: left 40000 -> Feb limit 140000, spent 130000 -> left 10000 -> Mar carry 10000
      expect(rolloverCarry(b, DateTime(2026, 2), (m) => spent[m] ?? 0), 40000);
      expect(rolloverCarry(b, DateTime(2026, 3), (m) => spent[m] ?? 0), 10000);
      expect(rolloverCarry(b, DateTime(2026, 4), (m) => spent[m] ?? 0), 110000);
    });

    test('overspending never produces a negative carry', () {
      final b = budgetRow(
        amount: 100000,
        start: DateTime(2026, 1),
        rollover: true,
      );
      expect(rolloverCarry(b, DateTime(2026, 2), (_) => 500000), 0);
    });
  });

  group('computeSafeToSpend', () {
    final today = DateTime(2026, 10, 10, 15);

    SafeToSpend calc({
      int? budget = 3100000,
      int income = 0,
      int spent = 0,
      int committed = 0,
      DateTime? month,
      DateTime? now,
      DateTime? periodEnd,
    }) => computeSafeToSpend(
      today: now ?? today,
      month: month ?? DateTime(2026, 10),
      overallBudgetMinor: budget,
      incomeMinor: income,
      spentMinor: spent,
      committedMinor: committed,
      periodEndInclusive: periodEnd,
    );

    test('divides what is left by the days remaining including today', () {
      final s = calc(spent: 1000000, committed: 200000);
      // Oct 10..31 = 22 days; available = 31000 - 10000 - 2000 = 19000 -> 1900000 paise
      expect(s.status, SafeStatus.ok);
      expect(s.availableMinor, 1900000);
      expect(s.daysRemaining, 22);
      expect(s.perDayMinor, 1900000 ~/ 22);
      expect(s.basedOnBudget, isTrue);
    });

    test('last day of the month leaves one day', () {
      final s = calc(now: DateTime(2026, 10, 31, 23), spent: 3000000);
      expect(s.daysRemaining, 1);
      expect(s.perDayMinor, 100000);
    });

    test('year boundary: December 31 still has one day left', () {
      final s = calc(
        now: DateTime(2026, 12, 31),
        month: DateTime(2026, 12),
        budget: 100000,
      );
      expect(s.daysRemaining, 1);
      expect(s.perDayMinor, 100000);
    });

    test('leap day handled', () {
      final s = calc(
        now: DateTime(2028, 2, 28),
        month: DateTime(2028, 2),
        budget: 29000,
      );
      expect(s.daysRemaining, 2);
    });

    test(
      'spent plus committed above the base is overspent with zero per day',
      () {
        final s = calc(spent: 3000000, committed: 200000);
        expect(s.status, SafeStatus.overspent);
        expect(s.availableMinor, -100000);
        expect(s.perDayMinor, 0);
      },
    );

    test(
      'exactly zero available counts as overspent (nothing safe to spend)',
      () {
        final s = calc(spent: 3100000);
        expect(s.status, SafeStatus.overspent);
        expect(s.perDayMinor, 0);
      },
    );

    test('without a budget it falls back to income and says so', () {
      final s = calc(budget: null, income: 2000000, spent: 500000);
      expect(s.basedOnBudget, isFalse);
      expect(s.status, SafeStatus.ok);
      expect(s.availableMinor, 1500000);
      expect(s.assumptions.first, contains('income'));
    });

    test('no budget and no income means no estimate', () {
      final s = calc(budget: null, income: 0, spent: 1000);
      expect(s.status, SafeStatus.noBase);
      expect(s.perDayMinor, 0);
    });

    test('past months are reported as ended, not projected', () {
      final s = calc(month: DateTime(2026, 9), spent: 2000000);
      expect(s.status, SafeStatus.periodEnded);
      expect(s.availableMinor, 1100000);
    });

    test('future months use the whole month', () {
      final s = calc(month: DateTime(2026, 11), budget: 3000000);
      expect(s.status, SafeStatus.ok);
      expect(s.daysRemaining, 30);
      expect(s.perDayMinor, 100000);
    });

    test('a planned income day shortens the period', () {
      final s = calc(periodEnd: DateTime(2026, 10, 24), budget: 2300000);
      expect(s.daysRemaining, 15);
      expect(s.perDayMinor, 2300000 ~/ 15);
    });

    test('always states it is an estimate, not a bank balance', () {
      expect(calc().assumptions.join(' '), contains('not a bank balance'));
    });
  });
}
