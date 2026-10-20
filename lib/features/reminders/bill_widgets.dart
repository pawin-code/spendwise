import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/domain/enums.dart';

enum DueState { overdue, today, soon, later }

DueState dueStateOf(RuleRow r, DateTime now) {
  final diff = dateOnly(r.nextDue).difference(dateOnly(now)).inDays;
  if (diff < 0) return DueState.overdue;
  if (diff == 0) return DueState.today;
  if (diff <= 7) return DueState.soon;
  return DueState.later;
}

String dueLabel(RuleRow r, DateTime now) {
  final diff = dateOnly(r.nextDue).difference(dateOnly(now)).inDays;
  if (diff < 0) return 'Overdue by ${-diff} day${diff == -1 ? '' : 's'}';
  if (diff == 0) return 'Due today';
  if (diff == 1) return 'Due tomorrow';
  if (diff <= 14) return 'Due in $diff days';
  return 'Due ${formatDay(r.nextDue)}';
}

IconData kindIcon(ReminderKind k) => switch (k) {
  ReminderKind.rent => Icons.home_outlined,
  ReminderKind.utility => Icons.bolt,
  ReminderKind.subscription => Icons.subscriptions_outlined,
  ReminderKind.loan => Icons.account_balance_outlined,
  ReminderKind.other => Icons.event_note_outlined,
};

/// Records the payment (creating a real transaction) only after the user
/// confirms. A reminder never marks anything paid by itself.
Future<void> confirmAndMarkPaid(
  BuildContext context,
  WidgetRef ref,
  RuleRow rule,
) async {
  final cur = ref.read(currencyProvider);
  final ok = await confirmDialog(
    context,
    title: rule.type == CategoryType.income
        ? 'Mark as received?'
        : 'Mark as paid?',
    message:
        '"${rule.title}" for ${formatMinor(rule.amountMinor, currency: cur)} will be recorded as a transaction dated today.',
    confirmLabel: rule.type == CategoryType.income
        ? 'Mark received'
        : 'Mark paid',
  );
  if (!ok || !context.mounted) return;
  try {
    final done = await ref.read(recurringRepositoryProvider).markPaid(rule.id);
    await ref.read(ledgerServiceProvider).refreshAlerts(DateTime.now());
    if (context.mounted) {
      showSnack(
        context,
        done ? 'Recorded "${rule.title}".' : 'This item is no longer active.',
      );
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not record the payment: $e');
  }
}

class BillTile extends ConsumerWidget {
  const BillTile({super.key, required this.rule, this.showAction = true});
  final RuleRow rule;
  final bool showAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final state = dueStateOf(rule, now);
    final fin = context.finance;
    final color = switch (state) {
      DueState.overdue => fin.expense,
      DueState.today => fin.warning,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push('${Routes.recurringEdit}?id=${rule.id}'),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(kindIcon(rule.kind), color: color),
      ),
      title: Text(rule.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        dueLabel(rule, now),
        style: TextStyle(
          color: color,
          fontWeight: state == DueState.later
              ? FontWeight.w400
              : FontWeight.w600,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MoneyText(
            rule.amountMinor,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (showAction)
            SizedBox(
              height: 28,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => confirmAndMarkPaid(context, ref, rule),
                child: Text(
                  rule.type == CategoryType.income
                      ? 'Mark received'
                      : 'Mark paid',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
