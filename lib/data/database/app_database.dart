import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:spendwise/data/database/seed.dart';
import 'package:spendwise/data/database/tables.dart';
import 'package:spendwise/domain/enums.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Wallets,
    Categories,
    Transactions,
    Budgets,
    BudgetAlerts,
    RecurringRules,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens (creating if needed) the on-device database file. The work is done
  /// on a background isolate so the UI thread is never blocked.
  AppDatabase.file(File file) : super(NativeDatabase.createInBackground(file));

  AppDatabase.memory() : super(NativeDatabase.memory());

  /// Bump when tables change and add a step to [migration.onUpgrade].
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seed();
    },
    onUpgrade: (m, from, to) async {
      // No released upgrades yet. Future versions add steps here, e.g.
      // if (from < 2) { await m.addColumn(transactions, transactions.xyz); }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_txn_date ON transactions (occurred_at)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_txn_wallet ON transactions (wallet_id)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_txn_category ON transactions (category_id)',
      );
    },
  );

  Future<void> _seed() async {
    await batch((b) {
      b.insertAll(categories, [
        for (var i = 0; i < kDefaultCategories.length; i++)
          CategoriesCompanion.insert(
            id: kDefaultCategories[i].id,
            name: kDefaultCategories[i].name,
            type: kDefaultCategories[i].type,
            iconKey: kDefaultCategories[i].icon,
            colorValue: kDefaultCategories[i].color,
            isDefault: const Value(true),
            sortOrder: Value(i),
          ),
      ]);
      b.insert(
        wallets,
        WalletsCompanion.insert(
          id: kDefaultWalletId,
          name: 'Cash',
          kind: WalletKind.cash,
          colorValue: 0xFF047857,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  /// Removes every user record and re-seeds defaults. Used by "Erase all data".
  Future<void> wipeAll() async {
    await transaction(() async {
      await customStatement('PRAGMA defer_foreign_keys = ON');
      await delete(budgetAlerts).go();
      await delete(transactions).go();
      await delete(recurringRules).go();
      await delete(budgets).go();
      await delete(categories).go();
      await delete(wallets).go();
      await _seed();
    });
  }
}
