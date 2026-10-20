import 'package:drift/drift.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/ids.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

class CategoryRepository {
  CategoryRepository(this.db);
  final AppDatabase db;

  Stream<List<CategoryRow>> watchAll({bool includeArchived = false}) {
    final q = db.select(db.categories)
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.name),
      ]);
    if (!includeArchived) q.where((c) => c.archived.equals(false));
    return q.watch();
  }

  Future<List<CategoryRow>> getAll() => (db.select(
    db.categories,
  )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();

  Future<String> add({
    required String name,
    required CategoryType type,
    required String iconKey,
    required int colorValue,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ValidationException('Enter a category name.');
    if (clean.length > 40) {
      throw ValidationException('Category names can be at most 40 characters.');
    }
    await _ensureUniqueName(clean, type, null);
    final id = newId();
    final max = await (db.selectOnly(
      db.categories,
    )..addColumns([db.categories.sortOrder.max()])).getSingle();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            name: clean,
            type: type,
            iconKey: iconKey,
            colorValue: colorValue,
            sortOrder: Value(
              (max.read(db.categories.sortOrder.max()) ?? 0) + 1,
            ),
          ),
        );
    return id;
  }

  Future<void> _ensureUniqueName(
    String name,
    CategoryType type,
    String? exceptId,
  ) async {
    final existing = await (db.select(
      db.categories,
    )..where((c) => c.type.equalsValue(type))).get();
    final clash = existing.any(
      (c) => c.id != exceptId && c.name.toLowerCase() == name.toLowerCase(),
    );
    if (clash) {
      throw ValidationException('A category named "$name" already exists.');
    }
  }

  Future<void> update(
    String id, {
    String? name,
    String? iconKey,
    int? colorValue,
  }) async {
    final row = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    if (name != null) {
      final clean = name.trim();
      if (clean.isEmpty) throw ValidationException('Enter a category name.');
      if (clean.length > 40) {
        throw ValidationException(
          'Category names can be at most 40 characters.',
        );
      }
      await _ensureUniqueName(clean, row.type, id);
    }
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        iconKey: iconKey == null ? const Value.absent() : Value(iconKey),
        colorValue: colorValue == null
            ? const Value.absent()
            : Value(colorValue),
      ),
    );
  }

  Future<void> setArchived(String id, bool archived) =>
      (db.update(db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(archived: Value(archived)),
      );

  /// Number of (non-deleted) transactions using the category.
  Future<int> usageCount(String id) async {
    final c = db.transactions.id.count();
    final r =
        await (db.selectOnly(db.transactions)
              ..addColumns([c])
              ..where(
                db.transactions.categoryId.equals(id) &
                    db.transactions.deletedAt.isNull(),
              ))
            .getSingle();
    return r.read(c) ?? 0;
  }

  /// Totals per category for the given period (non-deleted, non-transfer).
  Stream<Map<String, int>> watchTotals(DateTime from, DateTime toExclusive) {
    final sum = db.transactions.amountMinor.sum();
    final q = db.selectOnly(db.transactions)
      ..addColumns([db.transactions.categoryId, sum])
      ..where(
        db.transactions.deletedAt.isNull() &
            db.transactions.type.isNotValue(TxnType.transfer.name) &
            db.transactions.occurredAt.isBiggerOrEqualValue(from) &
            db.transactions.occurredAt.isSmallerThanValue(toExclusive),
      )
      ..groupBy([db.transactions.categoryId]);
    return q.watch().map(
      (rows) => {
        for (final r in rows)
          if (r.read(db.transactions.categoryId) != null)
            r.read(db.transactions.categoryId)!: r.read(sum) ?? 0,
      },
    );
  }
}

class WalletRepository {
  WalletRepository(this.db);
  final AppDatabase db;

  Stream<List<WalletRow>> watchAll({bool includeArchived = false}) {
    final q = db.select(db.wallets)
      ..orderBy([
        (w) => OrderingTerm.asc(w.sortOrder),
        (w) => OrderingTerm.asc(w.createdAt),
      ]);
    if (!includeArchived) q.where((w) => w.archived.equals(false));
    return q.watch();
  }

  Future<List<WalletRow>> getAll() => (db.select(
    db.wallets,
  )..orderBy([(w) => OrderingTerm.asc(w.sortOrder)])).get();

  Future<String> add({
    required String name,
    required WalletKind kind,
    int openingBalanceMinor = 0,
    required int colorValue,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ValidationException('Enter a wallet name.');
    if (clean.length > 60) {
      throw ValidationException('Wallet names can be at most 60 characters.');
    }
    final exists = (await getAll()).any(
      (w) => w.name.toLowerCase() == clean.toLowerCase(),
    );
    if (exists) {
      throw ValidationException('A wallet named "$clean" already exists.');
    }
    final id = newId();
    await db
        .into(db.wallets)
        .insert(
          WalletsCompanion.insert(
            id: id,
            name: clean,
            kind: kind,
            openingBalanceMinor: Value(openingBalanceMinor),
            colorValue: colorValue,
            createdAt: DateTime.now(),
          ),
        );
    return id;
  }

  Future<void> update(
    String id, {
    String? name,
    WalletKind? kind,
    int? openingBalanceMinor,
    int? colorValue,
  }) async {
    if (name != null) {
      final clean = name.trim();
      if (clean.isEmpty) throw ValidationException('Enter a wallet name.');
      final exists = (await getAll()).any(
        (w) => w.id != id && w.name.toLowerCase() == clean.toLowerCase(),
      );
      if (exists) {
        throw ValidationException('A wallet named "$clean" already exists.');
      }
    }
    await (db.update(db.wallets)..where((w) => w.id.equals(id))).write(
      WalletsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        kind: kind == null ? const Value.absent() : Value(kind),
        openingBalanceMinor: openingBalanceMinor == null
            ? const Value.absent()
            : Value(openingBalanceMinor),
        colorValue: colorValue == null
            ? const Value.absent()
            : Value(colorValue),
      ),
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    if (archived) {
      final active = (await getAll()).where((w) => !w.archived && w.id != id);
      if (active.isEmpty) {
        throw ValidationException('Keep at least one active wallet.');
      }
    }
    await (db.update(db.wallets)..where((w) => w.id.equals(id))).write(
      WalletsCompanion(archived: Value(archived)),
    );
  }
}

class BudgetRepository {
  BudgetRepository(this.db);
  final AppDatabase db;

  Stream<List<BudgetRow>> watchAll() => (db.select(
    db.budgets,
  )..orderBy([(b) => OrderingTerm.desc(b.startMonth)])).watch();

  Future<List<BudgetRow>> getAll() => (db.select(
    db.budgets,
  )..orderBy([(b) => OrderingTerm.desc(b.startMonth)])).get();

  Future<String> save({
    String? id,
    String? categoryId,
    required int amountMinor,
    required DateTime startMonth,
    DateTime? endMonth,
    int warnPercent = 80,
    bool rollover = false,
  }) async {
    if (amountMinor <= 0) {
      throw ValidationException('Enter a budget amount greater than zero.');
    }
    if (warnPercent < 1 || warnPercent > 100) {
      throw ValidationException(
        'Warning threshold must be between 1% and 100%.',
      );
    }
    final start = startOfMonth(startMonth);
    final end = endMonth == null ? null : startOfMonth(endMonth);
    if (end != null && end.isBefore(start)) {
      throw ValidationException(
        'End month must not be before the start month.',
      );
    }
    // Prevent overlapping budgets for the same scope.
    final others = (await getAll()).where(
      (b) => b.id != id && b.categoryId == categoryId,
    );
    for (final o in others) {
      final oStart = startOfMonth(o.startMonth);
      final oEnd = o.endMonth == null ? null : startOfMonth(o.endMonth!);
      final overlaps =
          (oEnd == null || !start.isAfter(oEnd)) &&
          (end == null || !end.isBefore(oStart));
      if (overlaps) {
        throw ValidationException(
          'A budget for this scope already covers part of that period. Edit it or change its end month.',
        );
      }
    }
    final budgetId = id ?? newId();
    await db
        .into(db.budgets)
        .insertOnConflictUpdate(
          BudgetsCompanion.insert(
            id: budgetId,
            categoryId: Value(categoryId),
            amountMinor: amountMinor,
            startMonth: start,
            endMonth: Value(end),
            warnPercent: Value(warnPercent),
            rollover: Value(rollover),
            createdAt: DateTime.now(),
          ),
        );
    return budgetId;
  }

  Future<void> delete(String id) async {
    await (db.delete(
      db.budgetAlerts,
    )..where((a) => a.budgetId.equals(id))).go();
    await (db.delete(db.budgets)..where((b) => b.id.equals(id))).go();
  }

  /// Records an alert; returns true only the first time for this
  /// budget/period/threshold, which is what prevents duplicate notifications.
  Future<bool> tryRecordAlert(
    String budgetId,
    String periodKey,
    int threshold,
  ) async {
    return db.transaction(() async {
      final existing =
          await (db.select(db.budgetAlerts)..where(
                (a) =>
                    a.budgetId.equals(budgetId) &
                    a.periodKey.equals(periodKey) &
                    a.threshold.equals(threshold),
              ))
              .getSingleOrNull();
      if (existing != null) return false;
      await db
          .into(db.budgetAlerts)
          .insert(
            BudgetAlertsCompanion.insert(
              budgetId: budgetId,
              periodKey: periodKey,
              threshold: threshold,
              firedAt: DateTime.now(),
            ),
          );
      return true;
    });
  }

  Future<void> clearAlertsFor(String budgetId, String periodKey) =>
      (db.delete(db.budgetAlerts)..where(
            (a) => a.budgetId.equals(budgetId) & a.periodKey.equals(periodKey),
          ))
          .go();
}
