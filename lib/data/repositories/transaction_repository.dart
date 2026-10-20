import 'package:drift/drift.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/ids.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/domain/enums.dart';

class ValidationException implements Exception {
  ValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum TxnSort { dateDesc, dateAsc, amountDesc, amountAsc }

class TxnFilter {
  const TxnFilter({
    this.query = '',
    this.type,
    this.categoryId,
    this.walletId,
    this.from,
    this.toExclusive,
    this.sort = TxnSort.dateDesc,
    this.limit = 50,
  });

  final String query;
  final TxnType? type;
  final String? categoryId;
  final String? walletId;
  final DateTime? from;
  final DateTime? toExclusive;
  final TxnSort sort;
  final int limit;

  bool get hasFilters =>
      query.isNotEmpty ||
      type != null ||
      categoryId != null ||
      walletId != null ||
      from != null ||
      toExclusive != null;

  TxnFilter copyWith({
    String? query,
    Object? type = _keep,
    Object? categoryId = _keep,
    Object? walletId = _keep,
    Object? from = _keep,
    Object? toExclusive = _keep,
    TxnSort? sort,
    int? limit,
  }) => TxnFilter(
    query: query ?? this.query,
    type: identical(type, _keep) ? this.type : type as TxnType?,
    categoryId: identical(categoryId, _keep)
        ? this.categoryId
        : categoryId as String?,
    walletId: identical(walletId, _keep) ? this.walletId : walletId as String?,
    from: identical(from, _keep) ? this.from : from as DateTime?,
    toExclusive: identical(toExclusive, _keep)
        ? this.toExclusive
        : toExclusive as DateTime?,
    sort: sort ?? this.sort,
    limit: limit ?? this.limit,
  );

  static const Object _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is TxnFilter &&
      other.query == query &&
      other.type == type &&
      other.categoryId == categoryId &&
      other.walletId == walletId &&
      other.from == from &&
      other.toExclusive == toExclusive &&
      other.sort == sort &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
    query,
    type,
    categoryId,
    walletId,
    from,
    toExclusive,
    sort,
    limit,
  );
}

/// A transaction together with the related rows needed to display it.
class TxnView {
  const TxnView(this.txn, this.category, this.wallet, this.toWallet);
  final TxnRow txn;
  final CategoryRow? category;
  final WalletRow wallet;
  final WalletRow? toWallet;
}

class TxnInput {
  const TxnInput({
    required this.type,
    required this.amountMinor,
    required this.walletId,
    required this.occurredAt,
    this.categoryId,
    this.toWalletId,
    this.hasTime = false,
    this.note = '',
    this.payee = '',
    this.recurringRuleId,
    this.occurrenceKey,
  });

  final TxnType type;
  final int amountMinor;
  final String walletId;
  final String? toWalletId;
  final String? categoryId;
  final DateTime occurredAt;
  final bool hasTime;
  final String note;
  final String payee;
  final String? recurringRuleId;
  final String? occurrenceKey;
}

class TransactionRepository {
  TransactionRepository(this.db);
  final AppDatabase db;

  Future<void> _validate(TxnInput i) async {
    if (i.amountMinor <= 0) {
      throw ValidationException('Enter an amount greater than zero.');
    }
    if (i.amountMinor > kMaxAmountMinor) {
      throw ValidationException('That amount is too large.');
    }
    if (i.note.length > 500) {
      throw ValidationException('Notes can be at most 500 characters.');
    }
    if (i.payee.length > 100) {
      throw ValidationException('Payee can be at most 100 characters.');
    }
    final wallet = await (db.select(
      db.wallets,
    )..where((w) => w.id.equals(i.walletId))).getSingleOrNull();
    if (wallet == null) throw ValidationException('Choose a wallet.');
    if (i.type == TxnType.transfer) {
      if (i.toWalletId == null) {
        throw ValidationException('Choose the wallet to transfer to.');
      }
      if (i.toWalletId == i.walletId) {
        throw ValidationException('Choose two different wallets.');
      }
      final to = await (db.select(
        db.wallets,
      )..where((w) => w.id.equals(i.toWalletId!))).getSingleOrNull();
      if (to == null) {
        throw ValidationException('The destination wallet no longer exists.');
      }
    } else if (i.categoryId != null) {
      final cat = await (db.select(
        db.categories,
      )..where((c) => c.id.equals(i.categoryId!))).getSingleOrNull();
      if (cat == null) {
        throw ValidationException('That category no longer exists.');
      }
      final expected = i.type == TxnType.income
          ? CategoryType.income
          : CategoryType.expense;
      if (cat.type != expected) {
        throw ValidationException(
          'Category does not match the transaction type.',
        );
      }
    }
  }

  /// Date-only entries are stored at local noon so time-zone/DST shifts can
  /// never move them to a neighbouring day.
  static DateTime normalizeDate(DateTime d, bool hasTime) =>
      hasTime ? d : DateTime(d.year, d.month, d.day, 12);

  TxnRow _row(String id, TxnInput i, DateTime now, {DateTime? createdAt}) =>
      TxnRow(
        id: id,
        type: i.type,
        amountMinor: i.amountMinor,
        categoryId: i.type == TxnType.transfer ? null : i.categoryId,
        walletId: i.walletId,
        toWalletId: i.type == TxnType.transfer ? i.toWalletId : null,
        occurredAt: normalizeDate(i.occurredAt, i.hasTime),
        hasTime: i.hasTime,
        note: i.note.trim(),
        payee: i.payee.trim(),
        recurringRuleId: i.recurringRuleId,
        occurrenceKey: i.occurrenceKey,
        createdAt: createdAt ?? now,
        updatedAt: now,
        deletedAt: null,
      );

  Future<String> add(TxnInput input, {DateTime? now}) async {
    await _validate(input);
    final id = newId();
    await db
        .into(db.transactions)
        .insert(_row(id, input, now ?? DateTime.now()));
    return id;
  }

  Future<void> update(String id, TxnInput input, {DateTime? now}) async {
    await _validate(input);
    final existing = await getById(id);
    if (existing == null) {
      throw ValidationException('This transaction no longer exists.');
    }
    final row =
        _row(
          id,
          input,
          now ?? DateTime.now(),
          createdAt: existing.createdAt,
        ).copyWith(
          recurringRuleId: Value(existing.recurringRuleId),
          occurrenceKey: Value(existing.occurrenceKey),
        );
    await db.update(db.transactions).replace(row);
  }

  Future<void> softDelete(String id) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(deletedAt: Value(DateTime.now())),
    );
  }

  Future<void> restore(String id) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      const TransactionsCompanion(deletedAt: Value(null)),
    );
  }

  Future<void> deleteForever(String id) =>
      (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();

  /// Permanently removes rows that were soft-deleted before [cutoff].
  Future<int> purgeDeletedBefore(DateTime cutoff) =>
      (db.delete(db.transactions)..where(
            (t) =>
                t.deletedAt.isNotNull() &
                t.deletedAt.isSmallerThanValue(cutoff),
          ))
          .go();

  Future<TxnRow?> getById(String id) => (db.select(
    db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<TxnView?> watchView(String id) {
    return _viewQuery(
      TxnFilter(),
      includeDeleted: true,
      onlyId: id,
    ).watch().map((rows) => rows.isEmpty ? null : _toView(rows.first));
  }

  JoinedSelectStatement<HasResultSet, dynamic> _viewQuery(
    TxnFilter f, {
    bool includeDeleted = false,
    String? onlyId,
  }) {
    final toW = db.alias(db.wallets, 'to_w');
    final q = db.select(db.transactions).join([
      leftOuterJoin(
        db.categories,
        db.categories.id.equalsExp(db.transactions.categoryId),
      ),
      innerJoin(db.wallets, db.wallets.id.equalsExp(db.transactions.walletId)),
      leftOuterJoin(toW, toW.id.equalsExp(db.transactions.toWalletId)),
    ]);
    Expression<bool> cond = const Constant(true);
    if (onlyId != null) cond = cond & db.transactions.id.equals(onlyId);
    if (!includeDeleted) cond = cond & db.transactions.deletedAt.isNull();
    if (f.type != null) cond = cond & db.transactions.type.equalsValue(f.type!);
    if (f.categoryId != null) {
      cond = cond & db.transactions.categoryId.equals(f.categoryId!);
    }
    if (f.walletId != null) {
      cond =
          cond &
          (db.transactions.walletId.equals(f.walletId!) |
              db.transactions.toWalletId.equals(f.walletId!));
    }
    if (f.from != null) {
      cond = cond & db.transactions.occurredAt.isBiggerOrEqualValue(f.from!);
    }
    if (f.toExclusive != null) {
      cond =
          cond & db.transactions.occurredAt.isSmallerThanValue(f.toExclusive!);
    }
    final text = f.query.trim();
    if (text.isNotEmpty) {
      final needle = Variable<String>(text.toLowerCase());
      // instr() is a plain substring test, so % and _ in the query are literal characters.
      Expression<bool> has(Expression<String> col) =>
          FunctionCallExpression<int>('instr', [
            col.lower(),
            needle,
          ]).isBiggerThanValue(0);
      cond =
          cond &
          (has(db.transactions.note) |
              has(db.transactions.payee) |
              has(db.categories.name));
    }
    q.where(cond);
    switch (f.sort) {
      case TxnSort.dateDesc:
        q.orderBy([
          OrderingTerm.desc(db.transactions.occurredAt),
          OrderingTerm.desc(db.transactions.createdAt),
        ]);
      case TxnSort.dateAsc:
        q.orderBy([
          OrderingTerm.asc(db.transactions.occurredAt),
          OrderingTerm.asc(db.transactions.createdAt),
        ]);
      case TxnSort.amountDesc:
        q.orderBy([
          OrderingTerm.desc(db.transactions.amountMinor),
          OrderingTerm.desc(db.transactions.occurredAt),
        ]);
      case TxnSort.amountAsc:
        q.orderBy([
          OrderingTerm.asc(db.transactions.amountMinor),
          OrderingTerm.desc(db.transactions.occurredAt),
        ]);
    }
    if (onlyId == null) q.limit(f.limit);
    return q;
  }

  TxnView _toView(TypedResult r) {
    final toW = db.alias(db.wallets, 'to_w');
    return TxnView(
      r.readTable(db.transactions),
      r.readTableOrNull(db.categories),
      r.readTable(db.wallets),
      r.readTableOrNull(toW),
    );
  }

  Stream<List<TxnView>> watchViews(TxnFilter f) =>
      _viewQuery(f).watch().map((rows) => rows.map(_toView).toList());

  Stream<List<TxnRow>> watchRange(DateTime from, DateTime toExclusive) {
    final q = db.select(db.transactions)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.occurredAt.isBiggerOrEqualValue(from) &
            t.occurredAt.isSmallerThanValue(toExclusive),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return q.watch();
  }

  Future<List<TxnRow>> getRange(DateTime from, DateTime toExclusive) {
    final q = db.select(db.transactions)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.occurredAt.isBiggerOrEqualValue(from) &
            t.occurredAt.isSmallerThanValue(toExclusive),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return q.get();
  }

  Future<List<TxnRow>> getAllActive() {
    final q = db.select(db.transactions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return q.get();
  }

  Stream<List<TxnRow>> watchDeleted() {
    final q = db.select(db.transactions)
      ..where((t) => t.deletedAt.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]);
    return q.watch();
  }

  Stream<int> watchCount() => db
      .customSelect(
        'SELECT COUNT(*) AS c FROM transactions WHERE deleted_at IS NULL',
        readsFrom: {db.transactions},
      )
      .watch()
      .map((rows) => rows.first.read<int>('c'));

  /// Wallet balances as of the end of [asOfDay] (future-dated rows excluded).
  Stream<Map<String, int>> watchBalances({DateTime? asOf}) {
    final limit = DateTime(
      (asOf ?? DateTime.now()).year,
      (asOf ?? DateTime.now()).month,
      (asOf ?? DateTime.now()).day + 1,
    );
    final flows = db
        .customSelect(
          'SELECT wallet_id AS w, type AS t, SUM(amount_minor) AS s FROM transactions '
          'WHERE deleted_at IS NULL AND occurred_at < ? GROUP BY wallet_id, type',
          variables: [Variable.withDateTime(limit)],
          readsFrom: {db.transactions, db.wallets},
        )
        .watch();
    return flows.asyncMap((rows) async {
      final wallets = await db.select(db.wallets).get();
      final ins = await db
          .customSelect(
            'SELECT to_wallet_id AS w, SUM(amount_minor) AS s FROM transactions '
            "WHERE deleted_at IS NULL AND type = 'transfer' AND occurred_at < ? GROUP BY to_wallet_id",
            variables: [Variable.withDateTime(limit)],
          )
          .get();
      return computeBalances(
        wallets,
        rows.map(
          (r) => WalletFlow(
            r.read<String>('w'),
            TxnType.values.byName(r.read<String>('t')),
            r.read<int>('s'),
          ),
        ),
        ins.map((r) => TransferInFlow(r.read<String>('w'), r.read<int>('s'))),
      );
    });
  }

  /// Month spend per category (expenses only), up to the end of today.
  Future<Map<String, int>> expenseByCategory(DateTime monthStart) async {
    final rows = await getRange(
      startOfMonth(monthStart),
      startOfNextMonth(monthStart),
    );
    return summarize(rows, asOf: DateTime.now()).expenseByCategory;
  }
}
