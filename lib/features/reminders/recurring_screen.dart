import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/features/reminders/bill_widgets.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring transactions')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-recurring',
        onPressed: () => context.push(Routes.recurringEdit),
        icon: const Icon(Icons.add),
        label: const Text('New recurring'),
      ),
      body: AsyncBody(
        value: rules,
        onRetry: () => ref.invalidate(rulesProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.repeat,
              title: 'No recurring items',
              message: 'Schedule salary, rent, EMIs or subscriptions. You confirm each occurrence with one tap — or let Pro post them automatically.',
              actionLabel: 'Add recurring item',
              onAction: () => context.push(Routes.recurringEdit),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
            children: [
              for (final r in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () => context.push(
                              '${Routes.recurringEdit}?id=${r.id}',
                            ),
                            leading: Icon(kindIcon(r.kind)),
                            title: Text(
                              r.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${r.frequency.label}${r.intervalCount > 1 ? ' ×${r.intervalCount}' : ''} · ${r.active ? dueLabel(r, DateTime.now()) : 'Paused or finished'}',
                            ),
                            trailing: MoneyText(
                              r.amountMinor,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                        Switch(
                          value: r.active,
                          onChanged: (v) => ref
                              .read(recurringRepositoryProvider)
                              .setActive(r.id, v),
                        ),
                      ],
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
