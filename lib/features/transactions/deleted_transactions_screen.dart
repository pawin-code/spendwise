import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/core/widgets/common.dart';

class DeletedTransactionsScreen extends ConsumerWidget {
  const DeletedTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deleted = ref.watch(deletedTxnsProvider);
    final cats = categoryMap(
      ref.watch(allCategoriesProvider).value ?? const [],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Recently deleted')),
      body: AsyncBody(
        value: deleted,
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.delete_outline,
              title: 'Nothing here',
              message: 'Deleted transactions are kept for 30 days so you can restore them, then removed permanently.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Deleted items are excluded from totals and are removed permanently after 30 days.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final t in rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.categoryId == null
                            ? 'Transaction'
                            : (cats[t.categoryId]?.name ?? 'Transaction'),
                      ),
                      subtitle: Text(
                        '${formatDay(t.occurredAt)} · deleted ${formatDay(t.deletedAt!)}',
                      ),
                      leading: MoneyText(
                        t.amountMinor,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Restore',
                            icon: const Icon(Icons.restore),
                            onPressed: () async {
                              await ref
                                  .read(ledgerServiceProvider)
                                  .undoDelete(t.id);
                              if (context.mounted) {
                                showSnack(context, 'Transaction restored');
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Delete permanently',
                            icon: const Icon(Icons.delete_forever_outlined),
                            onPressed: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Delete permanently?',
                                message: 'This cannot be undone.',
                                confirmLabel: 'Delete forever',
                                destructive: true,
                              );
                              if (ok) {
                                await ref
                                    .read(transactionRepositoryProvider)
                                    .deleteForever(t.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
