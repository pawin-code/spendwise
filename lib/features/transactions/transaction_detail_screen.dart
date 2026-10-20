import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/features/transactions/txn_tile.dart';

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(txnViewProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          if (value.value != null && value.value!.txn.deletedAt == null) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(Routes.editTransaction(id)),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Delete transaction?',
                  message: 'It moves to Recently deleted for 30 days, where you can restore it.',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                final ledger = ref.read(ledgerServiceProvider);
                await ledger.delete(id);
                if (!context.mounted) return;
                context.pop();
                // The scaffold messenger lives above this route.
                showSnack(
                  context,
                  'Transaction deleted',
                  actionLabel: 'Undo',
                  onAction: () => ledger.undoDelete(id),
                );
              },
            ),
          ],
        ],
      ),
      body: AsyncBody<TxnView?>(
        value: value,
        data: (v) {
          if (v == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Not found',
              message: 'This transaction no longer exists.',
            );
          }
          final t = v.txn;
          final isTransfer = t.type == TxnType.transfer;
          final color = isTransfer
              ? Theme.of(context).colorScheme.secondary
              : (t.type == TxnType.income
                    ? context.finance.income
                    : context.finance.expense);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (t.deletedAt != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'This transaction is deleted and excluded from all totals.',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(ledgerServiceProvider).undoDelete(id),
                        child: const Text('Restore'),
                      ),
                    ],
                  ),
                ),
              AppCard(
                child: Column(
                  children: [
                    isTransfer
                        ? CircleAvatar(
                            radius: 28,
                            child: Icon(Icons.swap_horiz, color: color),
                          )
                        : CategoryAvatar(
                            iconKey: v.category?.iconKey ?? 'category',
                            color: v.category?.colorValue ?? 0xFF607D8B,
                            size: 56,
                          ),
                    const SizedBox(height: 12),
                    Text(
                      txnTitle(v),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    AmountLabel(
                      minor: t.amountMinor,
                      sign: isTransfer
                          ? ''
                          : (t.type == TxnType.income ? '+' : '-'),
                      color: color,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  children: [
                    _Line(
                      'Type',
                      t.type.name[0].toUpperCase() + t.type.name.substring(1),
                    ),
                    _Line(
                      'Date',
                      t.hasTime
                          ? '${formatDay(t.occurredAt)} · ${formatTime(t.occurredAt)}'
                          : formatDay(t.occurredAt),
                    ),
                    _Line(isTransfer ? 'From' : 'Wallet', v.wallet.name),
                    if (isTransfer) _Line('To', v.toWallet?.name ?? '—'),
                    if (!isTransfer)
                      _Line('Category', v.category?.name ?? 'Uncategorized'),
                    if (t.payee.isNotEmpty) _Line('Payee', t.payee),
                    if (t.note.isNotEmpty) _Line('Note', t.note),
                    if (t.recurringRuleId != null)
                      const _Line(
                        'Source',
                        'Recorded from a bill or recurring item',
                      ),
                    _Line('Added', formatDay(t.createdAt)),
                    if (t.updatedAt.difference(t.createdAt).inMinutes > 0)
                      _Line('Last edited', formatDay(t.updatedAt)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
