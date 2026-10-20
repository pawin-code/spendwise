import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

String txnTitle(TxnView v) {
  final t = v.txn;
  if (t.type == TxnType.transfer) return 'Transfer';
  return v.category?.name ?? 'Uncategorized';
}

String txnSubtitle(TxnView v, {bool includeDate = true}) {
  final t = v.txn;
  final parts = <String>[];
  if (t.type == TxnType.transfer) {
    parts.add('${v.wallet.name} → ${v.toWallet?.name ?? '?'}');
  } else {
    if (t.payee.isNotEmpty) parts.add(t.payee);
    if (t.note.isNotEmpty) parts.add(t.note);
    if (parts.isEmpty) parts.add(v.wallet.name);
  }
  if (includeDate) parts.add(friendlyDay(t.occurredAt));
  return parts.join(' · ');
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.view,
    this.onTap,
    this.includeDate = true,
    this.trailingExtra,
  });
  final TxnView view;
  final VoidCallback? onTap;
  final bool includeDate;
  final Widget? trailingExtra;

  @override
  Widget build(BuildContext context) {
    final t = view.txn;
    final fin = context.finance;
    final isTransfer = t.type == TxnType.transfer;
    final color = isTransfer
        ? Theme.of(context).colorScheme.secondary
        : (t.type == TxnType.income ? fin.income : fin.expense);
    final sign = isTransfer ? '' : (t.type == TxnType.income ? '+' : '-');
    final future = t.occurredAt.isAfter(DateTime.now());
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap ?? () => context.push(Routes.transaction(t.id)),
      leading: isTransfer
          ? CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondary
                  .withValues(alpha: 0.14),
              child: Icon(
                Icons.swap_horiz,
                color: Theme.of(context).colorScheme.secondary,
              ),
            )
          : CategoryAvatar(
              iconKey: view.category?.iconKey ?? 'category',
              color: view.category?.colorValue ?? 0xFF607D8B,
            ),
      title: Text(txnTitle(view), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${txnSubtitle(view, includeDate: includeDate)}${future ? ' · Scheduled' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?trailingExtra,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: AmountLabel(minor: t.amountMinor, sign: sign, color: color),
          ),
        ],
      ),
    );
  }
}

/// Signed, currency-formatted amount.
class AmountLabel extends StatelessWidget {
  const AmountLabel({
    super.key,
    required this.minor,
    required this.sign,
    required this.color,
  });
  final int minor;
  final String sign;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sign.isNotEmpty)
          Text(
            sign,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        Flexible(
          child: MoneyText(
            minor,
            color: color,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
