import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/brand_mark.dart';
import 'package:spendwise/core/widgets/charts.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/features/budgets/budget_widgets.dart';
import 'package:spendwise/features/reminders/bill_widgets.dart';
import 'package:spendwise/features/transactions/txn_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            BrandMark(size: 30),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'SpendWise',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Bills & reminders',
            onPressed: () => context.push(Routes.bills),
            icon: const Icon(Icons.notifications_none),
          ),
          if (!isPro)
            IconButton(
              tooltip: 'SpendWise Pro',
              onPressed: () => context.push(Routes.pro),
              icon: const Icon(Icons.workspace_premium_outlined),
            ),
        ],
      ),
      body: const _HomeBody(),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(transactionCountProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
      children: [
        const Align(alignment: Alignment.centerLeft, child: MonthSwitcher()),
        const _BalanceCard(),
        const SizedBox(height: 12),
        const _QuickActions(),
        if (count.value == 0) ...[
          const SizedBox(height: 16),
          AppCard(
            child: EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Welcome to SpendWise',
              message: 'Add your first income or expense and your dashboard comes alive. Everything stays on this device.',
              actionLabel: 'Add a transaction',
              onAction: () => context.push(Routes.add),
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          const _SafeToSpendCard(),
          const _BudgetsSection(),
          const _CategorySection(),
          const _BillsSection(),
          const _RecentSection(),
        ],
      ],
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(balancesProvider);
    final summary = ref.watch(monthSummaryProvider);
    final extras = ref.watch(dashboardExtrasProvider);
    final month = ref.watch(selectedMonthProvider);
    final progress = ref.watch(budgetProgressProvider);
    final total = balances.value?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    final s = summary.value ?? PeriodSummary.empty;
    final overall = progress.value
        ?.where((p) => p.budget.categoryId == null)
        .firstOrNull;
    const onNavy = Colors.white;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Brand.navy, Color(0xFF0F3B3A), Brand.emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current balance',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: onNavy.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              total,
              color: onNavy,
              style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            'From your recorded wallets · ${formatMonth(month)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: onNavy.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Income',
                  minor: s.incomeMinor,
                  icon: Icons.south_west,
                  color: const Color(0xFF6EE7B7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  label: 'Expenses',
                  minor: s.expenseMinor,
                  icon: Icons.north_east,
                  color: const Color(0xFFFCA5A5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: overall == null ? 'Budget left' : 'Budget left',
                  minor: overall?.remainingMinor ?? 0,
                  icon: Icons.pie_chart_outline,
                  color: onNavy,
                  emptyText: overall == null ? 'No budget' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  label: 'Scheduled ahead',
                  minor: (extras.value?.futureExpenseMinor ?? 0),
                  icon: Icons.event_outlined,
                  color: onNavy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.minor,
    required this.icon,
    required this.color,
    this.emptyText,
  });
  final String label;
  final int minor;
  final IconData icon;
  final Color color;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                ),
                if (emptyText != null)
                  Text(
                    emptyText!,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  )
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: MoneyText(
                      minor,
                      color: Colors.white,
                      hideZeroFraction: true,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
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

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    Widget action(String label, IconData icon, String route, {Color? color}) =>
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.push(route),
            icon: Icon(icon, color: color),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
        );
    return Row(
      children: [
        action(
          'Income',
          Icons.add_circle_outline,
          '${Routes.add}?type=income',
          color: context.finance.income,
        ),
        const SizedBox(width: 8),
        action(
          'Expense',
          Icons.remove_circle_outline,
          '${Routes.add}?type=expense',
          color: context.finance.expense,
        ),
        const SizedBox(width: 8),
        action('Transfer', Icons.swap_horiz, '${Routes.add}?type=transfer'),
      ],
    );
  }
}

class _SafeToSpendCard extends ConsumerWidget {
  const _SafeToSpendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safe = ref.watch(safeToSpendProvider);
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: safe.when(
        loading: () => const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const Text('Safe-to-Spend is unavailable right now.'),
        data: (s) {
          String headline;
          String detail;
          Color? color;
          switch (s.status) {
            case SafeStatus.noBase:
              headline = 'Set a budget to see Safe-to-Spend';
              detail = 'Add an overall monthly budget or record income, and SpendWise estimates a daily amount.';
            case SafeStatus.overspent:
              headline = 'Over plan for this period';
              detail =
                  'Spent plus committed bills exceed your base by ${formatMinor(-s.availableMinor, currency: ref.watch(currencyProvider))}.';
              color = context.finance.expense;
            case SafeStatus.periodEnded:
              headline = s.availableMinor >= 0
                  ? 'Finished under plan'
                  : 'Finished over plan';
              detail =
                  '${formatMinor(s.availableMinor.abs(), currency: ref.watch(currencyProvider))} ${s.availableMinor >= 0 ? 'was left' : 'over'} for this month.';
            case SafeStatus.ok:
              headline =
                  '${formatMinor(s.perDayMinor, currency: ref.watch(currencyProvider))} per day';
              detail =
                  '${formatMinor(s.availableMinor, currency: ref.watch(currencyProvider))} available over ${s.daysRemaining} day${s.daysRemaining == 1 ? '' : 's'}';
              color = context.finance.income;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Safe-to-Spend',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'How is this calculated?',
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => _showAssumptions(context, ref, s),
                  ),
                ],
              ),
              Text(
                headline,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                'An estimate from your records — not a bank balance.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAssumptions(BuildContext context, WidgetRef ref, SafeToSpend s) {
    final cur = ref.read(currencyProvider);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'How Safe-to-Spend works',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _Row(
                  'Base (${s.basedOnBudget ? 'budget' : 'income'})',
                  formatMinor(s.baseMinor, currency: cur),
                ),
                _Row(
                  '− Spent so far',
                  formatMinor(s.spentMinor, currency: cur),
                ),
                _Row(
                  '− Committed (bills, scheduled)',
                  formatMinor(s.committedMinor, currency: cur),
                ),
                const Divider(),
                _Row(
                  '= Available',
                  formatMinor(s.availableMinor, currency: cur),
                  bold: true,
                ),
                _Row('÷ Days remaining', '${s.daysRemaining}'),
                _Row(
                  '= Per day',
                  formatMinor(s.perDayMinor, currency: cur),
                  bold: true,
                ),
                const SizedBox(height: 12),
                for (final a in s.assumptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $a'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
        ),
        Text(
          value,
          style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
        ),
      ],
    ),
  );
}

class _BudgetsSection extends ConsumerWidget {
  const _BudgetsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider);
    final list = progress.value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Budgets',
          actionLabel: list.isEmpty ? 'Create' : 'See all',
          onAction: () => list.isEmpty
              ? context.push(Routes.budgetEdit)
              : context.go(Routes.budgets),
        ),
        if (list.isEmpty)
          AppCard(
            onTap: () => context.push(Routes.budgetEdit),
            child: const Row(
              children: [
                Icon(Icons.pie_chart_outline),
                SizedBox(width: 12),
                Expanded(
                  child: Text('No budget for this month. Tap to create one.'),
                ),
              ],
            ),
          )
        else
          for (final p in list.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BudgetProgressCard(progress: p, compact: true),
            ),
      ],
    );
  }
}

class _CategorySection extends ConsumerWidget {
  const _CategorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthSummaryProvider).value;
    final cats = categoryMap(
      ref.watch(allCategoriesProvider).value ?? const [],
    );
    if (summary == null || summary.expenseMinor == 0) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Spending by category'),
        AppCard(
          child: CategoryDonut(
            slices: slicesFrom(summary.expenseByCategory, cats),
            centerLabel: 'Spent',
          ),
        ),
      ],
    );
  }
}

class _BillsSection extends ConsumerWidget {
  const _BillsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesProvider).value ?? const [];
    final now = DateTime.now();
    final horizon = dateOnly(now).add(const Duration(days: 14));
    final upcoming = rules
        .where((r) => r.active && !r.nextDue.isAfter(horizon))
        .take(3)
        .toList();
    if (upcoming.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Upcoming bills',
          actionLabel: 'See all',
          onAction: () => context.push(Routes.bills),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [for (final r in upcoming) BillTile(rule: r)],
          ),
        ),
      ],
    );
  }
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTxnsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Recent transactions',
          actionLabel: 'See all',
          onAction: () => context.go(Routes.transactions),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: recent.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Could not load transactions.'),
            ),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No transactions in this month yet.'),
                  )
                : Column(
                    children: [for (final v in list) TransactionTile(view: v)],
                  ),
          ),
        ),
      ],
    );
  }
}
