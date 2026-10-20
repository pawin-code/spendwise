import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/features/budgets/budget_widgets.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider);
    final all = ref.watch(budgetsProvider).value ?? const [];
    final cats = categoryMap(
      ref.watch(allCategoriesProvider).value ?? const [],
    );
    final month = ref.watch(selectedMonthProvider);
    final thisMonth = startOfMonth(DateTime.now());
    final past = all
        .where(
          (b) =>
              b.endMonth != null &&
              startOfMonth(b.endMonth!).isBefore(thisMonth),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            tooltip: 'New budget',
            icon: const Icon(Icons.add),
            onPressed: () => context.push(Routes.budgetEdit),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
        children: [
          const Align(alignment: Alignment.centerLeft, child: MonthSwitcher()),
          AsyncBody(
            value: progress,
            onRetry: () => ref.invalidate(budgetProgressProvider),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.pie_chart_outline,
                    title: 'No budget for ${formatMonth(month)}',
                    message: 'Create an overall monthly budget or set limits per category and get alerts at 80% and 100%.',
                    actionLabel: 'Create budget',
                    onAction: () => context.push(Routes.budgetEdit),
                  ),
                );
              }
              final overall = list
                  .where((p) => p.budget.categoryId == null)
                  .toList();
              final byCat = list
                  .where((p) => p.budget.categoryId != null)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (overall.isNotEmpty) ...[
                    const SectionHeader('Overall'),
                    for (final p in overall) BudgetProgressCard(progress: p),
                  ],
                  if (byCat.isNotEmpty) ...[
                    const SectionHeader('By category'),
                    for (final p in byCat)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: BudgetProgressCard(progress: p),
                      ),
                  ],
                ],
              );
            },
          ),
          if (past.isNotEmpty) ...[
            const SectionHeader('Budget history'),
            for (final b in past)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => context.push('${Routes.budgetEdit}?id=${b.id}'),
                  leading: const Icon(Icons.history),
                  title: Text(
                    b.categoryId == null
                        ? 'Overall budget'
                        : (cats[b.categoryId]?.name ?? 'Category budget'),
                  ),
                  subtitle: Text(
                    '${formatMonth(b.startMonth)} – ${formatMonth(b.endMonth!)}',
                  ),
                  trailing: MoneyText(
                    b.amountMinor,
                    hideZeroFraction: true,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
