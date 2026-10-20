import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/domain/enums.dart';

int _seq = 0;

/// Builds an in-memory transaction row for pure-logic tests.
TxnRow txn({
  TxnType type = TxnType.expense,
  int amount = 10000,
  String? category = 'cat_food',
  String wallet = 'wallet_cash',
  String? toWallet,
  DateTime? at,
  DateTime? deletedAt,
  String payee = '',
  String note = '',
}) {
  final when = at ?? DateTime(2026, 10, 15, 12);
  return TxnRow(
    id: 'id${_seq++}',
    type: type,
    amountMinor: amount,
    categoryId: category,
    walletId: wallet,
    toWalletId: toWallet,
    occurredAt: when,
    hasTime: false,
    note: note,
    payee: payee,
    recurringRuleId: null,
    occurrenceKey: null,
    createdAt: when,
    updatedAt: when,
    deletedAt: deletedAt,
  );
}

BudgetRow budgetRow({
  String id = 'b1',
  String? categoryId,
  int amount = 100000,
  DateTime? start,
  DateTime? end,
  int warn = 80,
  bool rollover = false,
}) => BudgetRow(
  id: id,
  categoryId: categoryId,
  amountMinor: amount,
  startMonth: start ?? DateTime(2026, 10),
  endMonth: end,
  warnPercent: warn,
  rollover: rollover,
  createdAt: DateTime(2026, 1, 1),
);

WalletRow walletRow(String id, {int opening = 0}) => WalletRow(
  id: id,
  name: id,
  kind: WalletKind.cash,
  openingBalanceMinor: opening,
  colorValue: 0xFF000000,
  archived: false,
  sortOrder: 0,
  createdAt: DateTime(2026, 1, 1),
);

/// A provider container backed by a fresh in-memory database.
Future<ProviderContainer> makeContainer({
  List overrides = const [],
  Map<String, Object> prefs = const {},
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases =
      true; // each test owns its own in-memory database
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final db = AppDatabase.memory();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(sp),
      databaseProvider.overrideWithValue(db),
      ...overrides,
    ],
  );
  return container;
}
