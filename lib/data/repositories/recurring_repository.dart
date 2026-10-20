import 'package:drift/drift.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/ids.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/domain/recurrence.dart';

class RuleInput {
  const RuleInput({
    required this.title,
    required this.kind,
    required this.type,
    required this.amountMinor,
    required this.walletId,
    required this.frequency,
    required this.startDate,
    this.categoryId,
    this.intervalCount = 1,
    this.endDate,
    this.autoPost = false,
    this.remind = true,
    this.remindDaysBefore = 1,
    this.note = '',
  });

  final String title;
  final ReminderKind kind;
  final CategoryType type;
  final int amountMinor;
  final String walletId;
  final String? categoryId;
  final Frequency frequency;
  final int intervalCount;
  final DateTime startDate;
  final DateTime? endDate;
  final bool autoPost;
  final bool remind;
  final int remindDaysBefore;
  final String note;
}

class RecurringRepository {
  RecurringRepository(this.db, this.transactions);
  final AppDatabase db;
  final TransactionRepository transactions;

  Stream<List<RuleRow>> watchAll() => (db.select(
    db.recurringRules,
  )..orderBy([(r) => OrderingTerm.asc(r.nextDue)])).watch();

  Future<List<RuleRow>> getAll() => (db.select(
    db.recurringRules,
  )..orderBy([(r) => OrderingTerm.asc(r.nextDue)])).get();

  Future<RuleRow?> getById(String id) => (db.select(
    db.recurringRules,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  void _validate(RuleInput i) {
    if (i.title.trim().isEmpty) throw ValidationException('Enter a title.');
    if (i.title.trim().length > 80) {
      throw ValidationException('Titles can be at most 80 characters.');
    }
    if (i.amountMinor <= 0) {
      throw ValidationException('Enter an amount greater than zero.');
    }
    if (i.amountMinor > kMaxAmountMinor) {
      throw ValidationException('That amount is too large.');
    }
    if (i.intervalCount < 1 || i.intervalCount > 365) {
      throw ValidationException('Repeat interval must be between 1 and 365.');
    }
    if (i.remindDaysBefore < 0 || i.remindDaysBefore > 30) {
      throw ValidationException('Remind between 0 and 30 days before.');
    }
    if (i.endDate != null &&
        dateOnly(i.endDate!).isBefore(dateOnly(i.startDate))) {
      throw ValidationException('End date must not be before the start date.');
    }
  }

  RecurringRulesCompanion _companion(
    RuleInput i, {
    required String id,
    DateTime? nextDue,
    DateTime? createdAt,
  }) => RecurringRulesCompanion(
    id: Value(id),
    title: Value(i.title.trim()),
    kind: Value(i.kind),
    type: Value(i.type),
    amountMinor: Value(i.amountMinor),
    categoryId: Value(i.categoryId),
    walletId: Value(i.walletId),
    frequency: Value(i.frequency),
    intervalCount: Value(i.intervalCount),
    startDate: Value(dateOnly(i.startDate)),
    nextDue: Value(dateOnly(nextDue ?? i.startDate)),
    endDate: Value(i.endDate == null ? null : dateOnly(i.endDate!)),
    autoPost: Value(i.autoPost),
    remind: Value(i.remind),
    remindDaysBefore: Value(i.remindDaysBefore),
    note: Value(i.note.trim()),
    createdAt: Value(createdAt ?? DateTime.now()),
  );

  Future<String> add(RuleInput input) async {
    _validate(input);
    final id = newId();
    await db.into(db.recurringRules).insert(_companion(input, id: id));
    return id;
  }

  /// If the schedule changed, nextDue is recomputed as the first occurrence on
  /// or after today so the user is never flooded with historic due dates.
  Future<void> update(String id, RuleInput input) async {
    _validate(input);
    final existing = await getById(id);
    if (existing == null) {
      throw ValidationException('This item no longer exists.');
    }
    var next = existing.nextDue;
    final scheduleChanged =
        existing.startDate != dateOnly(input.startDate) ||
        existing.frequency != input.frequency ||
        existing.intervalCount != input.intervalCount;
    if (scheduleChanged) {
      final today = dateOnly(DateTime.now());
      final s = dateOnly(input.startDate);
      next = !s.isBefore(today)
          ? s
          : (nextOccurrenceAfter(
                  s,
                  input.frequency,
                  input.intervalCount,
                  today.subtract(const Duration(days: 1)),
                ) ??
                s);
    }
    await (db.update(db.recurringRules)..where((r) => r.id.equals(id))).write(
      _companion(input, id: id, nextDue: next, createdAt: existing.createdAt),
    );
  }

  Future<void> setActive(String id, bool active) =>
      (db.update(db.recurringRules)..where((r) => r.id.equals(id))).write(
        RecurringRulesCompanion(active: Value(active)),
      );

  Future<void> delete(String id) async {
    // Posted transactions stay; they simply lose the schedule reference.
    await (db.update(db.transactions)
          ..where((t) => t.recurringRuleId.equals(id)))
        .write(const TransactionsCompanion(recurringRuleId: Value(null)));
    await (db.delete(db.recurringRules)..where((r) => r.id.equals(id))).go();
  }

  static String occurrenceKey(String ruleId, DateTime occurrence) {
    final d = dateOnly(occurrence);
    return '$ruleId|${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  DateTime? _advance(RuleRow r, DateTime from) {
    if (r.frequency == Frequency.once) return null;
    final n = nextOccurrenceAfter(
      r.startDate,
      r.frequency,
      r.intervalCount,
      from,
    );
    if (n == null) return null;
    if (r.endDate != null && n.isAfter(dateOnly(r.endDate!))) return null;
    return n;
  }

  /// Records the current occurrence as paid and advances the schedule.
  /// Idempotent: the unique occurrence key prevents duplicates, even if called
  /// repeatedly or from several code paths.
  Future<bool> markPaid(String ruleId, {DateTime? paidOn}) async {
    return db.transaction(() async {
      final rule = await getById(ruleId);
      if (rule == null || !rule.active) return false;
      final key = occurrenceKey(rule.id, rule.nextDue);
      final dup = await (db.select(
        db.transactions,
      )..where((t) => t.occurrenceKey.equals(key))).getSingleOrNull();
      if (dup == null) {
        await transactions.add(
          TxnInput(
            type: rule.type == CategoryType.income
                ? TxnType.income
                : TxnType.expense,
            amountMinor: rule.amountMinor,
            walletId: rule.walletId,
            categoryId: rule.categoryId,
            occurredAt: paidOn ?? DateTime.now(),
            payee: rule.title,
            note: rule.note,
            recurringRuleId: rule.id,
            occurrenceKey: key,
          ),
        );
      }
      final next = _advance(rule, rule.nextDue);
      await (db.update(
        db.recurringRules,
      )..where((r) => r.id.equals(rule.id))).write(
        RecurringRulesCompanion(
          nextDue: Value(next ?? rule.nextDue),
          active: Value(next != null),
        ),
      );
      return true;
    });
  }

  /// Skips the current occurrence without recording a payment.
  Future<void> skip(String ruleId) async {
    final rule = await getById(ruleId);
    if (rule == null) return;
    final next = _advance(rule, rule.nextDue);
    await (db.update(
      db.recurringRules,
    )..where((r) => r.id.equals(ruleId))).write(
      RecurringRulesCompanion(
        nextDue: Value(next ?? rule.nextDue),
        active: Value(next != null),
      ),
    );
  }

  /// Posts every due occurrence (<= [today]) of rules the user opted in to
  /// auto-post. Returns the number of transactions created. Safe to call on
  /// every app launch: duplicates are impossible.
  Future<int> postDueAutoRules(DateTime today, {int maxPerRule = 60}) async {
    final todayD = dateOnly(today);
    var created = 0;
    final rules = await (db.select(
      db.recurringRules,
    )..where((r) => r.active.equals(true) & r.autoPost.equals(true))).get();
    for (final rule in rules) {
      var guard = 0;
      var current = rule;
      while (guard++ < maxPerRule &&
          current.active &&
          !current.nextDue.isAfter(todayD)) {
        final before = current.nextDue;
        final ok = await markPaid(current.id, paidOn: before);
        if (!ok) break;
        created++;
        final refreshed = await getById(current.id);
        if (refreshed == null ||
            refreshed.nextDue == before && refreshed.active) {
          break;
        }
        current = refreshed;
      }
    }
    return created;
  }
}
