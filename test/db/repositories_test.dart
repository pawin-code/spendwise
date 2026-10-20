import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/database/seed.dart';
import 'package:spendwise/data/repositories/catalog_repositories.dart';
import 'package:spendwise/data/repositories/recurring_repository.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/domain/enums.dart';

TxnInput expense(
  int amount, {
  String? category = 'cat_food',
  DateTime? at,
  String wallet = kDefaultWalletId,
  String note = '',
  String payee = '',
}) => TxnInput(
  type: TxnType.expense,
  amountMinor: amount,
  walletId: wallet,
  categoryId: category,
  occurredAt: at ?? DateTime(2026, 10, 15),
  note: note,
  payee: payee,
);

TxnInput income(int amount, {DateTime? at}) => TxnInput(
  type: TxnType.income,
  amountMinor: amount,
  walletId: kDefaultWalletId,
  categoryId: 'cat_salary',
  occurredAt: at ?? DateTime(2026, 10, 1),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases =
      true; // the persistence test deliberately reopens one file sequentially
  late AppDatabase db;
  late TransactionRepository txns;
  late CategoryRepository cats;
  late WalletRepository wallets;
  late BudgetRepository budgets;
  late RecurringRepository recurring;

  setUp(() {
    db = AppDatabase.memory();
    txns = TransactionRepository(db);
    cats = CategoryRepository(db);
    wallets = WalletRepository(db);
    budgets = BudgetRepository(db);
    recurring = RecurringRepository(db, txns);
  });

  tearDown(() => db.close());

  group('seeding', () {
    test(
      'a new database has the default categories and a Cash wallet',
      () async {
        final all = await cats.getAll();
        expect(all.length, kDefaultCategories.length);
        expect(all.where((c) => c.type == CategoryType.expense).length, 12);
        expect(all.where((c) => c.type == CategoryType.income).length, 6);
        expect((await wallets.getAll()).single.name, 'Cash');
      },
    );
  });

  group('transaction CRUD', () {
    test('create and read back every field', () async {
      final id = await txns.add(
        expense(
          12345,
          note: 'milk',
          payee: 'Dairy',
          at: DateTime(2026, 10, 3, 18, 30),
        ).copyTime(),
      );
      final t = (await txns.getById(id))!;
      expect(t.amountMinor, 12345);
      expect(t.type, TxnType.expense);
      expect(t.categoryId, 'cat_food');
      expect(t.walletId, kDefaultWalletId);
      expect(t.note, 'milk');
      expect(t.payee, 'Dairy');
      expect(t.hasTime, isTrue);
      expect(t.occurredAt, DateTime(2026, 10, 3, 18, 30));
      expect(t.deletedAt, isNull);
    });

    test('date-only entries are stored at local noon', () async {
      final id = await txns.add(expense(100, at: DateTime(2026, 10, 3)));
      expect((await txns.getById(id))!.occurredAt, DateTime(2026, 10, 3, 12));
    });

    test('update changes fields and keeps created time', () async {
      final id = await txns.add(expense(100), now: DateTime(2026, 10, 1));
      await txns.update(
        id,
        expense(250, category: 'cat_transport', note: 'bus'),
        now: DateTime(2026, 10, 2),
      );
      final t = (await txns.getById(id))!;
      expect(t.amountMinor, 250);
      expect(t.categoryId, 'cat_transport');
      expect(t.createdAt, DateTime(2026, 10, 1));
      expect(t.updatedAt, DateTime(2026, 10, 2));
    });

    test('soft delete hides from queries and restore brings it back', () async {
      final id = await txns.add(expense(500));
      await txns.softDelete(id);
      expect(await txns.getAllActive(), isEmpty);
      expect((await txns.watchDeleted().first).single.id, id);
      await txns.restore(id);
      expect((await txns.getAllActive()).single.id, id);
    });

    test('purge removes only rows deleted before the cutoff', () async {
      final a = await txns.add(expense(1));
      final b = await txns.add(expense(2));
      await txns.softDelete(a);
      await txns.softDelete(b);
      expect(
        await txns.purgeDeletedBefore(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
        0,
      );
      expect(
        await txns.purgeDeletedBefore(
          DateTime.now().add(const Duration(days: 1)),
        ),
        2,
      );
    });

    test('invalid input is rejected with a readable message', () async {
      Future<void> expectInvalid(TxnInput i, String text) async {
        await expectLater(
          txns.add(i),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              contains(text),
            ),
          ),
        );
      }

      await expectInvalid(expense(0), 'greater than zero');
      await expectInvalid(expense(-5), 'greater than zero');
      await expectInvalid(expense(100, wallet: 'nope'), 'wallet');
      await expectInvalid(
        expense(100, category: 'cat_salary'),
        'does not match',
      );
      await expectInvalid(expense(100, category: 'ghost'), 'no longer exists');
      await expectInvalid(expense(100, note: 'x' * 501), 'Notes');
      await expectInvalid(
        TxnInput(
          type: TxnType.transfer,
          amountMinor: 100,
          walletId: kDefaultWalletId,
          occurredAt: DateTime.now(),
        ),
        'transfer to',
      );
      await expectInvalid(
        TxnInput(
          type: TxnType.transfer,
          amountMinor: 100,
          walletId: kDefaultWalletId,
          toWalletId: kDefaultWalletId,
          occurredAt: DateTime.now(),
        ),
        'two different',
      );
      expect(await txns.getAllActive(), isEmpty);
    });

    test('the database itself refuses zero amounts', () async {
      await expectLater(
        db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: 'x',
                type: TxnType.expense,
                amountMinor: 0,
                walletId: kDefaultWalletId,
                occurredAt: DateTime.now(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ),
        throwsA(anything),
      );
    });

    test('foreign keys are enforced', () async {
      await expectLater(
        db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: 'x',
                type: TxnType.expense,
                amountMinor: 5,
                walletId: 'missing-wallet',
                occurredAt: DateTime.now(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ),
        throwsA(anything),
      );
    });
  });

  group('wallets, transfers and balances', () {
    test(
      'balances combine opening balance, income, expenses and transfers',
      () async {
        final bank = await wallets.add(
          name: 'HDFC',
          kind: WalletKind.bank,
          openingBalanceMinor: 100000,
          colorValue: 1,
        );
        await txns.add(income(500000, at: DateTime(2026, 10, 1)));
        await txns.add(expense(120000, at: DateTime(2026, 10, 2)));
        await txns.add(
          TxnInput(
            type: TxnType.transfer,
            amountMinor: 200000,
            walletId: kDefaultWalletId,
            toWalletId: bank,
            occurredAt: DateTime(2026, 10, 3),
          ),
        );
        final b = await txns.watchBalances(asOf: DateTime(2026, 10, 31)).first;
        expect(b[kDefaultWalletId], 500000 - 120000 - 200000);
        expect(b[bank], 100000 + 200000);
        expect(
          b.values.fold<int>(0, (a, c) => a + c),
          100000 + 500000 - 120000,
        );
      },
    );

    test('transfers never count as income or spending', () async {
      final bank = await wallets.add(
        name: 'HDFC',
        kind: WalletKind.bank,
        colorValue: 1,
      );
      await txns.add(
        TxnInput(
          type: TxnType.transfer,
          amountMinor: 999900,
          walletId: kDefaultWalletId,
          toWalletId: bank,
          occurredAt: DateTime(2026, 10, 3),
        ),
      );
      await txns.add(expense(1000, at: DateTime(2026, 10, 4)));
      final s = summarize(
        await txns.getRange(DateTime(2026, 10), DateTime(2026, 11)),
      );
      expect(s.expenseMinor, 1000);
      expect(s.incomeMinor, 0);
    });

    test(
      'future-dated transactions are excluded from the current balance',
      () async {
        await txns.add(income(100000, at: DateTime(2026, 10, 1)));
        await txns.add(expense(40000, at: DateTime(2026, 10, 25)));
        final b = await txns.watchBalances(asOf: DateTime(2026, 10, 20)).first;
        expect(b[kDefaultWalletId], 100000);
        final later = await txns
            .watchBalances(asOf: DateTime(2026, 10, 25))
            .first;
        expect(later[kDefaultWalletId], 60000);
      },
    );

    test('wallet validation and archive rules', () async {
      await expectLater(
        wallets.add(name: '  ', kind: WalletKind.cash, colorValue: 1),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        wallets.add(name: 'cash', kind: WalletKind.cash, colorValue: 1),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        wallets.setArchived(kDefaultWalletId, true),
        throwsA(isA<ValidationException>()),
      );
      final w = await wallets.add(
        name: 'UPI',
        kind: WalletKind.digital,
        colorValue: 1,
      );
      await wallets.setArchived(w, true);
      expect(
        (await wallets.watchAll().first).map((e) => e.id),
        isNot(contains(w)),
      );
      expect(
        (await wallets.watchAll(includeArchived: true).first).map((e) => e.id),
        contains(w),
      );
    });
  });

  group('categories', () {
    test('custom categories can be added, renamed and archived without touching history', () async {
      final id = await cats.add(
        name: 'Pets',
        type: CategoryType.expense,
        iconKey: 'pets',
        colorValue: 5,
      );
      final t = await txns.add(expense(700, category: id));
      await cats.update(id, name: 'Pet care');
      await cats.setArchived(id, true);
      expect(
        (await cats.watchAll().first).map((c) => c.id),
        isNot(contains(id)),
      );
      expect((await txns.getById(t))!.categoryId, id);
      expect(await cats.usageCount(id), 1);
    });

    test('duplicate and empty names are rejected per type', () async {
      await expectLater(
        cats.add(
          name: 'food & GROCERIES',
          type: CategoryType.expense,
          iconKey: 'x',
          colorValue: 1,
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        cats.add(
          name: ' ',
          type: CategoryType.expense,
          iconKey: 'x',
          colorValue: 1,
        ),
        throwsA(isA<ValidationException>()),
      );
      await cats.add(
        name: 'Food & groceries',
        type: CategoryType.income,
        iconKey: 'x',
        colorValue: 1,
      ); // different type is fine
    });

    test(
      'category totals reflect only live, non-transfer rows in the period',
      () async {
        await txns.add(expense(100, at: DateTime(2026, 10, 2)));
        await txns.add(expense(250, at: DateTime(2026, 10, 3)));
        final gone = await txns.add(expense(999, at: DateTime(2026, 10, 3)));
        await txns.softDelete(gone);
        await txns.add(expense(5000, at: DateTime(2026, 11, 3)));
        final totals = await cats
            .watchTotals(DateTime(2026, 10), DateTime(2026, 11))
            .first;
        expect(totals['cat_food'], 350);
      },
    );
  });

  group('queries', () {
    setUp(() async {
      await txns.add(
        expense(
          1000,
          note: 'Lunch at cafe',
          payee: 'Cafe Blue',
          at: DateTime(2026, 10, 1),
        ),
      );
      await txns.add(
        expense(
          5000,
          category: 'cat_transport',
          note: 'Metro card',
          at: DateTime(2026, 10, 5),
        ),
      );
      await txns.add(income(90000, at: DateTime(2026, 10, 7)));
      await txns.add(
        expense(250, note: '100% fun_day', at: DateTime(2026, 9, 28)),
      );
    });

    Future<List<TxnView>> q(TxnFilter f) => txns.watchViews(f).first;

    test('search matches note, payee and category name case-insensitively and treats wildcards literally', () async {
      expect((await q(const TxnFilter(query: 'CAFE'))).length, 1);
      expect((await q(const TxnFilter(query: 'cafe blue'))).length, 1);
      expect(
        (await q(const TxnFilter(query: 'transport'))).single.txn.amountMinor,
        5000,
      );
      expect((await q(const TxnFilter(query: '100%'))).length, 1);
      expect((await q(const TxnFilter(query: '%'))).length, 1);
      expect((await q(const TxnFilter(query: '_'))).length, 1);
      expect(await q(const TxnFilter(query: 'zzz')), isEmpty);
    });

    test('filters by type, category, wallet and dates', () async {
      expect((await q(const TxnFilter(type: TxnType.income))).length, 1);
      expect((await q(const TxnFilter(categoryId: 'cat_food'))).length, 2);
      expect((await q(const TxnFilter(walletId: kDefaultWalletId))).length, 4);
      expect((await q(const TxnFilter(walletId: 'none'))).length, 0);
      expect(
        (await q(
          TxnFilter(
            from: DateTime(2026, 10, 1),
            toExclusive: DateTime(2026, 10, 6),
          ),
        )).length,
        2,
      );
    });

    test('sorts by date and amount', () async {
      final newest = await q(const TxnFilter());
      expect(newest.first.txn.amountMinor, 90000);
      expect(
        (await q(const TxnFilter(sort: TxnSort.dateAsc))).first.txn.amountMinor,
        250,
      );
      expect(
        (await q(const TxnFilter(sort: TxnSort.amountDesc)))
            .map((v) => v.txn.amountMinor),
        [90000, 5000, 1000, 250],
      );
      expect(
        (await q(const TxnFilter(sort: TxnSort.amountAsc)))
            .first
            .txn
            .amountMinor,
        250,
      );
    });

    test('paging limits the result size', () async {
      expect((await q(const TxnFilter(limit: 2))).length, 2);
    });

    test('large histories stay fast and complete', () async {
      await db.batch((b) {
        b.insertAll(db.transactions, [
          for (var i = 0; i < 5000; i++)
            TransactionsCompanion.insert(
              id: 'bulk$i',
              type: TxnType.expense,
              amountMinor: 100 + i,
              categoryId: const Value('cat_food'),
              walletId: kDefaultWalletId,
              occurredAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
        ]);
      });
      final sw = Stopwatch()..start();
      final page = await q(const TxnFilter(limit: 50));
      final searched = await q(const TxnFilter(query: 'lunch'));
      sw.stop();
      expect(page.length, 50);
      expect(searched.length, 1);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('budgets', () {
    test('overlapping budgets for the same scope are rejected, different scopes allowed', () async {
      await budgets.save(amountMinor: 100000, startMonth: DateTime(2026, 10));
      await expectLater(
        budgets.save(amountMinor: 200000, startMonth: DateTime(2027, 3)),
        throwsA(isA<ValidationException>()),
      );
      await budgets.save(
        categoryId: 'cat_food',
        amountMinor: 30000,
        startMonth: DateTime(2026, 10),
      );
    });

    test('ended budgets leave room for a new one and validation messages are clear', () async {
      final id = await budgets.save(
        amountMinor: 100000,
        startMonth: DateTime(2026, 1),
        endMonth: DateTime(2026, 6),
      );
      await budgets.save(amountMinor: 120000, startMonth: DateTime(2026, 7));
      await expectLater(
        budgets.save(amountMinor: 0, startMonth: DateTime(2030)),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        budgets.save(
          amountMinor: 5,
          startMonth: DateTime(2030, 5),
          endMonth: DateTime(2030, 1),
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        budgets.save(
          categoryId: 'cat_food',
          amountMinor: 5,
          startMonth: DateTime(2030),
          warnPercent: 0,
        ),
        throwsA(isA<ValidationException>()),
      );
      await budgets.delete(id);
      expect((await budgets.getAll()).length, 1);
    });

    test('alerts are recorded once per budget, period and threshold', () async {
      final id = await budgets.save(
        amountMinor: 100000,
        startMonth: DateTime(2026, 10),
      );
      expect(await budgets.tryRecordAlert(id, '2026-10', 80), isTrue);
      expect(await budgets.tryRecordAlert(id, '2026-10', 80), isFalse);
      expect(await budgets.tryRecordAlert(id, '2026-10', 100), isTrue);
      expect(await budgets.tryRecordAlert(id, '2026-11', 80), isTrue);
    });
  });

  group('recurring items', () {
    RuleInput rule({
      DateTime? start,
      Frequency f = Frequency.monthly,
      bool auto = false,
      DateTime? end,
    }) => RuleInput(
      title: 'Rent',
      kind: ReminderKind.rent,
      type: CategoryType.expense,
      amountMinor: 1500000,
      walletId: kDefaultWalletId,
      categoryId: 'cat_rent',
      frequency: f,
      startDate: start ?? DateTime(2026, 10, 5),
      endDate: end,
      autoPost: auto,
    );

    test(
      'mark paid records one transaction and advances the schedule',
      () async {
        final id = await recurring.add(rule());
        expect(
          await recurring.markPaid(id, paidOn: DateTime(2026, 10, 6)),
          isTrue,
        );
        final r = (await recurring.getById(id))!;
        expect(r.nextDue, DateTime(2026, 11, 5));
        final rows = await txns.getAllActive();
        expect(rows.length, 1);
        expect(rows.single.amountMinor, 1500000);
        expect(rows.single.recurringRuleId, id);
        expect(rows.single.occurrenceKey, '$id|2026-10-05');
      },
    );

    test(
      'an occurrence can never be posted twice (idempotent by key)',
      () async {
        final id = await recurring.add(rule());
        await recurring.markPaid(id);
        // Rewind the schedule to simulate a repeated launch / sync of the same occurrence.
        await (db.update(
          db.recurringRules,
        )..where((r) => r.id.equals(id))).write(
          RecurringRulesCompanion(nextDue: Value(DateTime(2026, 10, 5))),
        );
        await recurring.markPaid(id);
        expect((await txns.getAllActive()).length, 1);
      },
    );

    test('the unique index rejects duplicate occurrence keys at the database level', () async {
      final id = await recurring.add(rule());
      await recurring.markPaid(id);
      await expectLater(
        txns.add(
          TxnInput(
            type: TxnType.expense,
            amountMinor: 1,
            walletId: kDefaultWalletId,
            occurredAt: DateTime.now(),
            occurrenceKey: '$id|2026-10-05',
          ),
        ),
        throwsA(anything),
      );
    });

    test('one-off reminders finish after being paid', () async {
      final id = await recurring.add(rule(f: Frequency.once));
      await recurring.markPaid(id);
      final r = (await recurring.getById(id))!;
      expect(r.active, isFalse);
      expect((await txns.getAllActive()).length, 1);
      expect(
        await recurring.markPaid(id),
        isFalse,
      ); // inactive: nothing more to record
      expect((await txns.getAllActive()).length, 1);
    });

    test('auto-posting catches up missed occurrences exactly once and is safe to repeat', () async {
      final id = await recurring.add(
        rule(start: DateTime(2026, 8, 5), auto: true),
      );
      final first = await recurring.postDueAutoRules(DateTime(2026, 10, 20));
      expect(first, 3); // Aug 5, Sep 5, Oct 5
      expect(await recurring.postDueAutoRules(DateTime(2026, 10, 20)), 0);
      expect(await recurring.postDueAutoRules(DateTime(2026, 10, 21)), 0);
      expect((await txns.getAllActive()).length, 3);
      expect((await recurring.getById(id))!.nextDue, DateTime(2026, 11, 5));
    });

    test('rules without auto-post are never posted silently', () async {
      await recurring.add(rule(start: DateTime(2026, 8, 5), auto: false));
      expect(await recurring.postDueAutoRules(DateTime(2026, 10, 20)), 0);
      expect(await txns.getAllActive(), isEmpty);
    });

    test('end dates stop the schedule', () async {
      final id = await recurring.add(
        rule(
          start: DateTime(2026, 8, 5),
          end: DateTime(2026, 9, 10),
          auto: true,
        ),
      );
      expect(await recurring.postDueAutoRules(DateTime(2026, 12, 1)), 2);
      expect((await recurring.getById(id))!.active, isFalse);
    });

    test('skip advances without recording and delete keeps history', () async {
      final id = await recurring.add(rule());
      await recurring.skip(id);
      expect((await recurring.getById(id))!.nextDue, DateTime(2026, 11, 5));
      expect(await txns.getAllActive(), isEmpty);
      await recurring.markPaid(id);
      await recurring.delete(id);
      expect(await recurring.getById(id), isNull);
      expect((await txns.getAllActive()).single.recurringRuleId, isNull);
    });

    test('validation', () async {
      await expectLater(
        recurring.add(
          RuleInput(
            title: '',
            kind: ReminderKind.other,
            type: CategoryType.expense,
            amountMinor: 1,
            walletId: kDefaultWalletId,
            frequency: Frequency.once,
            startDate: someDate,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('persistence', () {
    test('records survive closing and reopening the database file', () async {
      final dir = await Directory.systemTemp.createTemp('spendwise_db_test');
      final file = File(p.join(dir.path, 'app.sqlite'));
      try {
        final first = AppDatabase.file(file);
        final repo1 = TransactionRepository(first);
        final id = await repo1.add(expense(4242, note: 'persist me'));
        await BudgetRepository(first)
            .save(amountMinor: 777, startMonth: DateTime(2026, 10));
        await first.close();

        final second = AppDatabase.file(file);
        final repo2 = TransactionRepository(second);
        final t = (await repo2.getById(id))!;
        expect(t.amountMinor, 4242);
        expect(t.note, 'persist me');
        expect(
          (await BudgetRepository(second).getAll()).single.amountMinor,
          777,
        );
        // Seed data is not duplicated on reopen.
        expect(
          (await CategoryRepository(second).getAll()).length,
          kDefaultCategories.length,
        );
        expect((await WalletRepository(second).getAll()).length, 1);
        await second.close();
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('wipeAll removes user data and restores defaults', () async {
      await txns.add(expense(100));
      await cats.add(
        name: 'Mine',
        type: CategoryType.expense,
        iconKey: 'x',
        colorValue: 1,
      );
      await wallets.add(name: 'Extra', kind: WalletKind.bank, colorValue: 1);
      await budgets.save(amountMinor: 1, startMonth: DateTime(2026, 10));
      await db.wipeAll();
      expect(await txns.getAllActive(), isEmpty);
      expect((await cats.getAll()).length, kDefaultCategories.length);
      expect((await wallets.getAll()).single.id, kDefaultWalletId);
      expect(await budgets.getAll(), isEmpty);
    });
  });

  test('dateOnly helper sanity (used by recurring)', () {
    expect(dateOnly(DateTime(2026, 10, 5, 23, 59)), DateTime(2026, 10, 5));
  });
}

final someDate = DateTime(2026, 10, 5);

extension on TxnInput {
  /// Same input but flagged as having a time component.
  TxnInput copyTime() => TxnInput(
    type: type,
    amountMinor: amountMinor,
    walletId: walletId,
    categoryId: categoryId,
    occurredAt: occurredAt,
    hasTime: true,
    note: note,
    payee: payee,
  );
}
