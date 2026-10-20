// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';
import 'package:spendwise/domain/enums.dart';

@DataClassName('WalletRow')
class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get kind => textEnum<WalletKind>()();
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();
  IntColumn get colorValue => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get type => textEnum<CategoryType>()();
  TextColumn get iconKey => text()();
  IntColumn get colorValue => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TxnRow')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<TxnType>()();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get walletId => text().references(Wallets, #id)();
  @ReferenceName('incomingTransfers')
  TextColumn get toWalletId => text().nullable().references(Wallets, #id)();
  DateTimeColumn get occurredAt => dateTime()();
  BoolColumn get hasTime => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get payee => text().withDefault(const Constant(''))();
  TextColumn get recurringRuleId => text().nullable()();

  /// Format: ruleId, a pipe, then the occurrence date as yyyy-MM-dd. Unique, so an occurrence can never be posted twice.
  TextColumn get occurrenceKey => text().nullable().unique()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (type != 'transfer' OR (to_wallet_id IS NOT NULL AND to_wallet_id != wallet_id))",
  ];
}

@DataClassName('BudgetRow')
class Budgets extends Table {
  TextColumn get id => text()();

  /// Null means the overall monthly budget.
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();

  /// First day of the first month this budget applies to.
  DateTimeColumn get startMonth => dateTime()();

  /// First day of the last month it applies to; null = ongoing.
  DateTimeColumn get endMonth => dateTime().nullable()();
  IntColumn get warnPercent => integer().withDefault(const Constant(80))();
  BoolColumn get rollover => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BudgetAlertRow')
class BudgetAlerts extends Table {
  TextColumn get budgetId => text()();
  TextColumn get periodKey => text()();
  IntColumn get threshold => integer()();
  DateTimeColumn get firedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {budgetId, periodKey, threshold};
}

@DataClassName('RuleRow')
class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 80)();
  TextColumn get kind => textEnum<ReminderKind>()();
  TextColumn get type => textEnum<CategoryType>()();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get frequency => textEnum<Frequency>()();
  IntColumn get intervalCount => integer().withDefault(const Constant(1))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get nextDue => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// Pro feature: post due occurrences automatically (explicit opt-in per rule).
  BoolColumn get autoPost => boolean().withDefault(const Constant(false))();
  BoolColumn get remind => boolean().withDefault(const Constant(true))();
  IntColumn get remindDaysBefore => integer().withDefault(const Constant(1))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
