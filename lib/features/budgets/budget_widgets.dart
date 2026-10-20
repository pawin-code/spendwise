import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/domain/calculations.dart';

class BudgetProgressCard extends ConsumerWidget {
  const BudgetProgressCard({
    super.key,
    required this.progress,
    this.compact = false,
  });
  final BudgetProgress progress;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fin = context.finance;
    final cats = categoryMap(
      ref.watch(allCategoriesProvider).value ?? const [],
    );
    final cat = progress.budget.categoryId == null
        ? null
        : cats[progress.budget.categoryId];
    final status = progress.status;
    final color = switch (status) {
      BudgetStatus.ok => Theme.of(context).colorScheme.primary,
      BudgetStatus.warning => fin.warning,
      BudgetStatus.over => fin.expense,
    };
    final pct = progress.percentUsed;
    final value = progress.limitMinor <= 0
        ? 0.0
        : (progress.spentMinor / progress.limitMinor).clamp(0.0, 1.0);
    final statusText = switch (status) {
      BudgetStatus.ok => '$pct% used',
      BudgetStatus.warning => '$pct% used — approaching limit',
      BudgetStatus.over => '$pct% used — over budget',
    };
    final remaining = progress.remainingMinor;
    return AppCard(
      onTap: () =>
          context.push('${Routes.budgetEdit}?id=${progress.budget.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (cat != null) ...[
                CategoryAvatar(
                  iconKey: cat.iconKey,
                  color: cat.colorValue,
                  size: 34,
                ),
                const SizedBox(width: 10),
              ] else ...[
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  cat?.name ?? 'Overall budget',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MoneyText(
                progress.limitMinor,
                hideZeroFraction: true,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: '${cat?.name ?? 'Overall'} budget, $statusText',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 10,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                remaining >= 0 ? 'Left ' : 'Over by ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Flexible(
                child: MoneyText(
                  remaining.abs(),
                  hideZeroFraction: true,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          if (!compact && progress.carryMinor > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(
                    'Includes rollover ',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Flexible(
                    child: MoneyText(
                      progress.carryMinor,
                      hideZeroFraction: true,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
