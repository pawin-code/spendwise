import 'package:spendwise/core/money.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/services/budget_service.dart';

/// Facade used by the UI for changing transactions. After every change it
/// re-evaluates budget thresholds; dashboards and reports refresh themselves
/// because they watch the database.
class LedgerService {
  LedgerService({
    required this.transactions,
    required this.alerts,
    required this.alertsEnabled,
    required this.currency,
  });

  final TransactionRepository transactions;
  final BudgetAlertService alerts;
  final bool Function() alertsEnabled;
  final CurrencyInfo Function() currency;

  Future<void> refreshAlerts(DateTime when) async {
    try {
      await alerts.evaluate(
        when,
        enabled: alertsEnabled(),
        currency: currency(),
      );
    } catch (_) {
      // Alerts are best-effort and must never break saving a transaction.
    }
  }

  Future<String> add(TxnInput input) async {
    final id = await transactions.add(input);
    await refreshAlerts(input.occurredAt);
    return id;
  }

  Future<void> update(String id, TxnInput input) async {
    final before = await transactions.getById(id);
    await transactions.update(id, input);
    await refreshAlerts(input.occurredAt);
    if (before != null &&
        (before.occurredAt.month != input.occurredAt.month ||
            before.occurredAt.year != input.occurredAt.year)) {
      await refreshAlerts(before.occurredAt);
    }
  }

  Future<void> delete(String id) => transactions.softDelete(id);

  Future<void> undoDelete(String id) async {
    await transactions.restore(id);
    final t = await transactions.getById(id);
    if (t != null) await refreshAlerts(t.occurredAt);
  }
}
