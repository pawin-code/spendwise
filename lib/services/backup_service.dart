import 'dart:convert';

import 'package:spendwise/data/database/app_database.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// JSON backup of all user records. The file is NOT encrypted: it contains
/// readable financial data, so users are warned to store it somewhere safe.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  static const int formatVersion = 1;
  static const int maxBytes = 50 * 1024 * 1024;

  Future<String> createBackupJson() async {
    final data = <String, dynamic>{
      'app': 'spendwise',
      'formatVersion': formatVersion,
      'schemaVersion': db.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'wallets': (await db.select(db.wallets).get())
          .map((e) => e.toJson())
          .toList(),
      'categories': (await db.select(db.categories).get())
          .map((e) => e.toJson())
          .toList(),
      'transactions': (await db.select(db.transactions).get())
          .map((e) => e.toJson())
          .toList(),
      'budgets': (await db.select(db.budgets).get())
          .map((e) => e.toJson())
          .toList(),
      'budgetAlerts': (await db.select(db.budgetAlerts).get())
          .map((e) => e.toJson())
          .toList(),
      'recurringRules': (await db.select(db.recurringRules).get())
          .map((e) => e.toJson())
          .toList(),
    };
    return const JsonEncoder.withIndent(' ').convert(data);
  }

  /// Validates then replaces ALL existing data. Everything happens inside one
  /// transaction: any failure rolls back and leaves current data untouched.
  Future<BackupSummary> restoreFromJson(String text) async {
    if (text.length > maxBytes) {
      throw BackupException('Backup file is too large.');
    }
    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) throw const FormatException('root');
      data = decoded;
    } catch (_) {
      throw BackupException('This is not a valid SpendWise backup file.');
    }
    if (data['app'] != 'spendwise') {
      throw BackupException('This file was not created by SpendWise.');
    }
    final version = data['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw BackupException(
        'This backup was made by a newer version of SpendWise. Update the app and try again.',
      );
    }
    List<Map<String, dynamic>> list(String key) {
      final v = data[key];
      if (v is! List) throw BackupException('Backup is missing "$key".');
      return v.cast<Map<String, dynamic>>();
    }

    try {
      final wallets = list('wallets').map(WalletRow.fromJson).toList();
      final categories = list('categories').map(CategoryRow.fromJson).toList();
      final txns = list('transactions').map(TxnRow.fromJson).toList();
      final budgets = list('budgets').map(BudgetRow.fromJson).toList();
      final alerts = list('budgetAlerts').map(BudgetAlertRow.fromJson).toList();
      final rules = list('recurringRules').map(RuleRow.fromJson).toList();
      if (wallets.isEmpty) throw BackupException('Backup contains no wallets.');
      await db.transaction(() async {
        await db.customStatement('PRAGMA defer_foreign_keys = ON');
        await db.delete(db.budgetAlerts).go();
        await db.delete(db.transactions).go();
        await db.delete(db.recurringRules).go();
        await db.delete(db.budgets).go();
        await db.delete(db.categories).go();
        await db.delete(db.wallets).go();
        await db.batch((b) {
          b.insertAll(db.wallets, wallets);
          b.insertAll(db.categories, categories);
          b.insertAll(db.budgets, budgets);
          b.insertAll(db.recurringRules, rules);
          b.insertAll(db.transactions, txns);
          b.insertAll(db.budgetAlerts, alerts);
        });
      });
      return BackupSummary(
        transactions: txns.length,
        wallets: wallets.length,
        categories: categories.length,
        budgets: budgets.length,
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      throw BackupException(
        'The backup file is damaged or incompatible. Your current data was not changed.',
      );
    }
  }
}

class BackupSummary {
  const BackupSummary({
    required this.transactions,
    required this.wallets,
    required this.categories,
    required this.budgets,
  });
  final int transactions;
  final int wallets;
  final int categories;
  final int budgets;
}
