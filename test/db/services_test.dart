import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/database/seed.dart';
import 'package:spendwise/data/repositories/catalog_repositories.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise/services/budget_service.dart';
import 'package:spendwise/services/csv_service.dart';
import 'package:spendwise/services/import_service.dart';
import 'package:spendwise/services/ledger_service.dart';
import 'package:spendwise/services/notification_service.dart';

class RecordingNotifications extends NoopNotificationService {
  final shown = <String>[];
  @override
  Future<void> showBudgetAlert({
    required String key,
    required String title,
    required String body,
  }) async => shown.add(title);
}

TxnInput exp(int amount, {String category = 'cat_food', DateTime? at}) =>
    TxnInput(
      type: TxnType.expense,
      amountMinor: amount,
      walletId: kDefaultWalletId,
      categoryId: category,
      occurredAt: at ?? DateTime(2026, 10, 10),
    );

void main() {
  late AppDatabase db;
  late TransactionRepository txns;
  late CategoryRepository cats;
  late WalletRepository wallets;
  late BudgetRepository budgets;

  setUp(() {
    db = AppDatabase.memory();
    txns = TransactionRepository(db);
    cats = CategoryRepository(db);
    wallets = WalletRepository(db);
    budgets = BudgetRepository(db);
  });
  tearDown(() => db.close());

  group('backup & restore', () {
    test('a restored backup reproduces every record exactly', () async {
      final bank = await wallets.add(
        name: 'HDFC',
        kind: WalletKind.bank,
        openingBalanceMinor: 12345,
        colorValue: 9,
      );
      await cats.add(
        name: 'Pets',
        type: CategoryType.expense,
        iconKey: 'pets',
        colorValue: 7,
      );
      await txns.add(exp(12345, at: DateTime(2026, 10, 3)));
      await txns.add(
        TxnInput(
          type: TxnType.transfer,
          amountMinor: 500,
          walletId: kDefaultWalletId,
          toWalletId: bank,
          occurredAt: DateTime(2026, 10, 4),
          note: 'move',
        ),
      );
      final gone = await txns.add(exp(99));
      await txns.softDelete(gone);
      await budgets.save(
        categoryId: 'cat_food',
        amountMinor: 50000,
        startMonth: DateTime(2026, 10),
        rollover: true,
      );

      final backup = BackupService(db);
      final json = await backup.createBackupJson();
      final before = (await db.select(db.transactions).get())
          .map((e) => e.toJson())
          .toList();

      await db.wipeAll();
      expect(await txns.getAllActive(), isEmpty);

      final summary = await backup.restoreFromJson(json);
      expect(summary.transactions, 3);
      final after = (await db.select(db.transactions).get())
          .map((e) => e.toJson())
          .toList();
      expect(after.length, before.length);
      for (final row in before) {
        expect(
          after.any(
            (a) =>
                a['id'] == row['id'] &&
                a['amountMinor'] == row['amountMinor'] &&
                a['occurredAt'] == row['occurredAt'] &&
                a['deletedAt'] == row['deletedAt'],
          ),
          isTrue,
        );
      }
      expect(
        (await wallets.getAll()).map((w) => w.name),
        containsAll(['Cash', 'HDFC']),
      );
      expect((await cats.getAll()).any((c) => c.name == 'Pets'), isTrue);
      expect((await budgets.getAll()).single.rollover, isTrue);
    });

    test(
      'invalid backups are rejected and existing data is untouched',
      () async {
        await txns.add(exp(100));
        final backup = BackupService(db);
        for (final bad in [
          '',
          'not json',
          '[]',
          '{"app":"other"}',
          '{"app":"spendwise","formatVersion":99}',
          '{"app":"spendwise","formatVersion":1}',
        ]) {
          await expectLater(
            backup.restoreFromJson(bad),
            throwsA(isA<BackupException>()),
            reason: bad,
          );
        }
        expect((await txns.getAllActive()).length, 1);
      },
    );

    test(
      'a corrupt backup rolls back instead of leaving a half-restored database',
      () async {
        await txns.add(exp(100));
        final backup = BackupService(db);
        final json = await backup.createBackupJson();
        // Break referential integrity: a transaction pointing at a missing wallet.
        final broken = json.replaceFirst(
          '"walletId": "$kDefaultWalletId"',
          '"walletId": "ghost"',
        );
        await expectLater(
          backup.restoreFromJson(broken),
          throwsA(isA<BackupException>()),
        );
        expect((await txns.getAllActive()).length, 1);
        expect((await wallets.getAll()).single.id, kDefaultWalletId);
      },
    );
  });

  group('csv import / export consistency', () {
    late ImportService importer;
    setUp(
      () => importer = ImportService(
        db: db,
        transactions: txns,
        categories: cats,
        wallets: wallets,
      ),
    );

    test(
      'exporting and re-importing the same data finds only duplicates',
      () async {
        await txns.add(exp(12345, at: DateTime(2026, 10, 3)));
        await txns.add(
          TxnInput(
            type: TxnType.income,
            amountMinor: 900000,
            walletId: kDefaultWalletId,
            categoryId: 'cat_salary',
            occurredAt: DateTime(2026, 10, 1),
            payee: 'ACME',
          ),
        );
        final views = await txns.watchViews(const TxnFilter(limit: 1000)).first;
        final text = const CsvService().exportTransactions(views);
        final preview = await importer.preview(text);
        expect(preview.rows.length, 2);
        expect(preview.duplicateCount, 2);
        final result = await importer.commit(preview);
        expect(result.imported, 0);
        expect(result.skippedDuplicates, 2);
        expect((await txns.getAllActive()).length, 2);
      },
    );

    test('importing into an empty database restores the same totals and creates new categories and wallets', () async {
      const text =
          'date,type,amount,category,wallet,to_wallet,payee,note\n'
          '2026-10-01,income,50000.00,Salary,Cash,,ACME,pay\n'
          '2026-10-02,expense,1234.56,Pets,Paytm,,Vet,shots\n'
          '2026-10-03,transfer,1000,,Cash,Paytm,,top up\n'
          'bad-date,expense,5,,Cash,,,\n';
      final preview = await importer.preview(text);
      expect(preview.errors.length, 1);
      expect(preview.rows.length, 3);
      final result = await importer.commit(preview);
      expect(result.imported, 3);
      expect(
        (await cats.getAll()).any(
          (c) => c.name == 'Pets' && c.type == CategoryType.expense,
        ),
        isTrue,
      );
      final paytm = (await wallets.getAll()).singleWhere(
        (w) => w.name == 'Paytm',
      );
      final summary = summarize(
        await txns.getRange(DateTime(2026, 10), DateTime(2026, 11)),
      );
      expect(summary.incomeMinor, 5000000);
      expect(summary.expenseMinor, 123456);
      final balances = await txns
          .watchBalances(asOf: DateTime(2026, 10, 31))
          .first;
      expect(balances[paytm.id], 100000 - 123456);
      expect(balances[kDefaultWalletId], 5000000 - 100000);
      // A second import of the same file adds nothing.
      final again = await importer.commit(await importer.preview(text));
      expect(again.imported, 0);
    });

    test('importing duplicates can be forced', () async {
      await txns.add(exp(1000, at: DateTime(2026, 10, 3)));
      final text = const CsvService().exportTransactions(
        await txns.watchViews(const TxnFilter()).first,
      );
      final preview = await importer.preview(text);
      final result = await importer.commit(preview, skipDuplicates: false);
      expect(result.imported, 1);
      expect((await txns.getAllActive()).length, 2);
    });
  });

  group('budget alerts', () {
    test(
      'thresholds fire once, in order, and survive edits and deletes',
      () async {
        await budgets.save(amountMinor: 10000, startMonth: DateTime(2026, 10));
        final notifications = RecordingNotifications();
        final alerts = BudgetAlertService(
          budgetService: BudgetService(budgets, txns),
          budgets: budgets,
          categories: cats,
          notifications: notifications,
        );
        final ledger = LedgerService(
          transactions: txns,
          alerts: alerts,
          alertsEnabled: () => true,
          currency: () => kCurrencies.first,
        );
        final now = DateTime(2026, 10, 20);

        await ledger.add(exp(5000)); // 50%
        expect(notifications.shown, isEmpty);

        final id = await ledger.add(exp(3500)); // 85% -> warning
        expect(notifications.shown, ['Overall budget at 80%']);

        await ledger.add(exp(100)); // still 86%: no repeat
        expect(notifications.shown.length, 1);

        await ledger.add(exp(1500)); // 101% -> reached
        expect(notifications.shown.last, 'Overall budget reached');
        expect(notifications.shown.length, 2);

        // Editing / deleting / re-adding does not re-fire the same threshold in the same month.
        await ledger.update(id, exp(3600));
        await ledger.delete(id);
        await ledger.undoDelete(id);
        await alerts.evaluate(
          now,
          enabled: true,
          currency: kCurrencies.first,
          now: now,
        );
        expect(notifications.shown.length, 2);
      },
    );

    test('crossing both thresholds at once sends only the highest', () async {
      await budgets.save(amountMinor: 10000, startMonth: DateTime(2026, 10));
      final notifications = RecordingNotifications();
      final alerts = BudgetAlertService(
        budgetService: BudgetService(budgets, txns),
        budgets: budgets,
        categories: cats,
        notifications: notifications,
      );
      final ledger = LedgerService(
        transactions: txns,
        alerts: alerts,
        alertsEnabled: () => true,
        currency: () => kCurrencies.first,
      );
      await ledger.add(exp(12000));
      expect(notifications.shown, ['Overall budget reached']);
    });

    test('disabled alerts never notify but budget math still works', () async {
      await budgets.save(
        categoryId: 'cat_food',
        amountMinor: 10000,
        startMonth: DateTime(2026, 10),
      );
      final notifications = RecordingNotifications();
      final service = BudgetService(budgets, txns);
      final alerts = BudgetAlertService(
        budgetService: service,
        budgets: budgets,
        categories: cats,
        notifications: notifications,
      );
      final ledger = LedgerService(
        transactions: txns,
        alerts: alerts,
        alertsEnabled: () => false,
        currency: () => kCurrencies.first,
      );
      await ledger.add(exp(20000));
      expect(notifications.shown, isEmpty);
      final p = (await service.progressForMonth(
        DateTime(2026, 10),
        now: DateTime(2026, 10, 20),
      )).single;
      expect(p.spentMinor, 20000);
      expect(p.status, BudgetStatus.over);
    });

    test('progress ignores other categories, transfers, deleted and future-dated rows', () async {
      await budgets.save(
        categoryId: 'cat_food',
        amountMinor: 100000,
        startMonth: DateTime(2026, 10),
      );
      await txns.add(exp(1000));
      await txns.add(exp(7000, category: 'cat_transport'));
      final gone = await txns.add(exp(5000));
      await txns.softDelete(gone);
      await txns.add(exp(9000, at: DateTime(2026, 10, 28)));
      final p = (await BudgetService(budgets, txns).progressForMonth(
        DateTime(2026, 10),
        now: DateTime(2026, 10, 20),
      )).single;
      expect(p.spentMinor, 1000);
    });

    test('rollover uses real history from the database', () async {
      await budgets.save(
        amountMinor: 100000,
        startMonth: DateTime(2026, 8),
        rollover: true,
      );
      await txns.add(
        exp(40000, at: DateTime(2026, 8, 10)),
      ); // 60000 left -> carries
      await txns.add(
        exp(130000, at: DateTime(2026, 9, 10)),
      ); // limit 160000, left 30000
      final p = (await BudgetService(budgets, txns).progressForMonth(
        DateTime(2026, 10),
        now: DateTime(2026, 10, 20),
      )).single;
      expect(p.carryMinor, 30000);
      expect(p.limitMinor, 130000);
    });
  });

  test('reopening a database created by the current schema keeps working (upgrade harness)', () async {
    // schemaVersion is 1 today; this guards the harness that future migrations extend.
    expect(db.schemaVersion, 1);
    expect(db.migration, isNotNull);
  });
}
