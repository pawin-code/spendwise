import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/features/reminders/bill_widgets.dart';
import 'package:spendwise/features/settings/notification_actions.dart';

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesProvider);
    final notificationsOn = ref.watch(
      settingsProvider.select((s) => s.notificationsEnabled),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill reminders'),
        actions: [
          IconButton(
            tooltip: 'Manage recurring items',
            icon: const Icon(Icons.repeat),
            onPressed: () => context.push(Routes.recurring),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-bill',
        onPressed: () => context.push('${Routes.recurringEdit}?bill=1'),
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Add reminder'),
      ),
      body: AsyncBody(
        value: rules,
        onRetry: () => ref.invalidate(rulesProvider),
        data: (all) {
          final now = DateTime.now();
          final today = dateOnly(now);
          final active = all.where((r) => r.active).toList();
          final overdue = active
              .where((r) => r.nextDue.isBefore(today))
              .toList();
          final week = active
              .where(
                (r) =>
                    !r.nextDue.isBefore(today) &&
                    r.nextDue.isBefore(today.add(const Duration(days: 8))),
              )
              .toList();
          final later = active
              .where(
                (r) => !r.nextDue.isBefore(today.add(const Duration(days: 8))),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
            children: [
              if (!notificationsOn)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_off_outlined),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Reminder notifications are off. Turn them on to get a nudge before a bill is due.',
                          ),
                        ),
                        TextButton(
                          onPressed: () => enableNotifications(context, ref),
                          child: const Text('Turn on'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (active.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.event_available_outlined,
                    title: 'No bills yet',
                    message: 'Add rent, utilities or subscriptions and SpendWise will remind you before they are due. Nothing is paid or recorded until you mark it.',
                  ),
                ),
              _Group(title: 'Overdue', rules: overdue),
              _Group(title: 'Due this week', rules: week),
              _Group(title: 'Later', rules: later),
              if (active.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Reminders never mark a bill as paid. Tap "Mark paid" after you pay, and SpendWise records the transaction.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.rules});
  final String title;
  final List<RuleRow> rules;

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [for (final r in rules) BillTile(rule: r)]),
        ),
      ],
    );
  }
}
