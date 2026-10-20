import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/widgets/charts.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/domain/reports.dart';
import 'package:spendwise/features/budgets/budget_widgets.dart';
import 'package:spendwise/features/import_export/export_sheet.dart';

class ReportState {
  const ReportState({required this.period, required this.anchor, this.custom});
  final ReportPeriod period;
  final DateTime anchor;
  final DateRange? custom;

  DateRange get range => rangeFor(period, anchor, custom: custom);

  ReportState copyWith({
    ReportPeriod? period,
    DateTime? anchor,
    DateRange? custom,
  }) => ReportState(
    period: period ?? this.period,
    anchor: anchor ?? this.anchor,
    custom: custom ?? this.custom,
  );
}

class ReportStateNotifier extends Notifier<ReportState> {
  @override
  ReportState build() =>
      ReportState(period: ReportPeriod.month, anchor: dateOnly(DateTime.now()));
  void set(ReportState s) => state = s;
}

final reportStateProvider = NotifierProvider<ReportStateNotifier, ReportState>(
  ReportStateNotifier.new,
);

final _rangeTxnsProvider = StreamProvider.autoDispose
    .family<List<TxnRow>, DateRange>(
      (ref, r) => ref
          .watch(transactionRepositoryProvider)
          .watchRange(r.from, r.toExclusive),
    );

final _rangeBudgetProvider = FutureProvider.autoDispose
    .family<List<BudgetProgress>, DateTime>((ref, month) async {
      ref.watch(monthTxnsProvider);
      ref.watch(budgetsProvider);
      return ref.watch(budgetServiceProvider).progressForMonth(month);
    });

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportStateProvider);
    final isPro = ref.watch(isProProvider);
    final notifier = ref.read(reportStateProvider.notifier);
    final range = state.range;
    final txns = ref.watch(_rangeTxnsProvider(range));
    final prevRange = previousRange(state.period, range);
    final prevTxns = ref.watch(_rangeTxnsProvider(prevRange));
    final cats = categoryMap(
      ref.watch(allCategoriesProvider).value ?? const [],
    );
    final label = rangeLabel(state.period, range);
    final summaryNow = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Export report as CSV',
            icon: const Icon(Icons.ios_share),
            onPressed: txns.hasValue
                ? () {
                    final s = summarize(txns.requireValue, asOf: summaryNow);
                    showExportSheet(
                      context,
                      ref,
                      fileName: 'spendwise-report-${isoDateOf(range.from)}.csv',
                      build: () => ref
                          .read(csvServiceProvider)
                          .exportSummary(
                            periodLabel: label,
                            summary: s,
                            categoryNames: {
                              for (final e in cats.entries) e.key: e.value.name,
                            },
                          ),
                    );
                  }
                : null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in ReportPeriod.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.label),
                          if (p == ReportPeriod.custom && !isPro) ...[
                            const SizedBox(width: 6),
                            const ProBadge(),
                          ],
                        ],
                      ),
                      selected: state.period == p,
                      onSelected: (_) async {
                        if (p == ReportPeriod.custom) {
                          if (!isPro) {
                            final go = await confirmDialog(
                              context,
                              title: 'Custom ranges are in Pro',
                              message: 'Daily to yearly reports are free. Pick any start and end date with SpendWise Pro.',
                              confirmLabel: 'See Pro',
                            );
                            if (go && context.mounted) context.push(Routes.pro);
                            return;
                          }
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked == null) return;
                          notifier.set(
                            state.copyWith(
                              period: p,
                              custom: DateRange(
                                dateOnly(picked.start),
                                dateOnly(picked.end)
                                    .add(const Duration(days: 1)),
                              ),
                            ),
                          );
                        } else {
                          notifier.set(
                            state.copyWith(
                              period: p,
                              anchor: state.period == ReportPeriod.custom
                                  ? dateOnly(DateTime.now())
                                  : state.anchor,
                            ),
                          );
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.period != ReportPeriod.custom)
                IconButton(
                  tooltip: 'Previous period',
                  onPressed: () => notifier.set(
                    state.copyWith(
                      anchor: shiftAnchor(state.period, state.anchor, -1),
                    ),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              if (state.period != ReportPeriod.custom)
                IconButton(
                  tooltip: 'Next period',
                  onPressed: () => notifier.set(
                    state.copyWith(
                      anchor: shiftAnchor(state.period, state.anchor, 1),
                    ),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
            ],
          ),
          AsyncBody(
            value: txns,
            onRetry: () => ref.invalidate(_rangeTxnsProvider(range)),
            data: (rows) {
              final s = summarize(rows, asOf: summaryNow);
              if (s.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: EmptyState(
                    icon: Icons.insights_outlined,
                    title: 'Nothing to report',
                    message: 'There are no income or expense records in this period.',
                  ),
                );
              }
              final prev = prevTxns.hasValue
                  ? summarize(prevTxns.requireValue, asOf: summaryNow)
                  : null;
              final buckets = buildBuckets(
                state.period,
                range,
                rows,
                asOf: summaryNow,
              );
              return _ReportBody(
                state: state,
                summary: s,
                previous: prev,
                buckets: buckets,
                cats: cats,
              );
            },
          ),
        ],
      ),
    );
  }
}

String isoDateOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _ReportBody extends ConsumerWidget {
  const _ReportBody({
    required this.state,
    required this.summary,
    required this.previous,
    required this.buckets,
    required this.cats,
  });
  final ReportState state;
  final PeriodSummary summary;
  final PeriodSummary? previous;
  final List<Bucket> buckets;
  final Map<String, CategoryRow> cats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fin = context.finance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Income',
                minor: summary.incomeMinor,
                color: fin.income,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'Expenses',
                minor: summary.expenseMinor,
                color: fin.expense,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Net',
                minor: summary.netMinor,
                color: summary.netMinor >= 0 ? fin.income : fin.expense,
                signed: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'Avg expense',
                minor: summary.averageExpenseMinor,
                color: Theme.of(context).colorScheme.onSurface,
                footnote:
                    '${summary.expenseCount} expense${summary.expenseCount == 1 ? '' : 's'} · ${summary.incomeCount} income',
              ),
            ),
          ],
        ),
        if (previous != null && !previous!.isEmpty) ...[
          const SectionHeader('Compared with previous period'),
          AppCard(
            child: Column(
              children: [
                _Compare(
                  label: 'Income',
                  now: summary.incomeMinor,
                  before: previous!.incomeMinor,
                  higherIsGood: true,
                ),
                _Compare(
                  label: 'Expenses',
                  now: summary.expenseMinor,
                  before: previous!.expenseMinor,
                  higherIsGood: false,
                ),
                _Compare(
                  label: 'Net',
                  now: summary.netMinor,
                  before: previous!.netMinor,
                  higherIsGood: true,
                ),
              ],
            ),
          ),
        ],
        if (buckets.isNotEmpty) ...[
          const SectionHeader('Income vs expenses'),
          AppCard(
            child: IncomeExpenseBars(
              points: [
                for (final b in buckets)
                  BarPoint(b.label, b.incomeMinor, b.expenseMinor),
              ],
              incomeColor: fin.income,
              expenseColor: fin.expense,
            ),
          ),
          const SectionHeader('Spending trend'),
          AppCard(
            child: SpendingTrendLine(
              points: [
                for (final b in buckets) TrendPoint(b.label, b.expenseMinor),
              ],
              color: fin.expense,
            ),
          ),
        ],
        if (summary.expenseMinor > 0) ...[
          const SectionHeader('Spending by category'),
          AppCard(
            child: CategoryDonut(
              slices: slicesFrom(summary.expenseByCategory, cats),
              centerLabel: 'Spent',
            ),
          ),
        ],
        if (summary.largestExpenses.isNotEmpty) ...[
          const SectionHeader('Largest expenses'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                for (final t in summary.largestExpenses)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(Routes.transaction(t.id)),
                    leading: CategoryAvatar(
                      iconKey: cats[t.categoryId]?.iconKey ?? 'category',
                      color: cats[t.categoryId]?.colorValue ?? 0xFF607D8B,
                      size: 38,
                    ),
                    title: Text(
                      t.payee.isNotEmpty
                          ? t.payee
                          : (cats[t.categoryId]?.name ?? 'Expense'),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${cats[t.categoryId]?.name ?? 'Uncategorized'} · ${friendlyDay(t.occurredAt)}',
                    ),
                    trailing: MoneyText(
                      t.amountMinor,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (state.period == ReportPeriod.month ||
            state.period == ReportPeriod.week ||
            state.period == ReportPeriod.day) ...[
          const SectionHeader('Budget performance'),
          _BudgetPerformance(month: startOfMonth(state.range.from)),
        ],
      ],
    );
  }
}

class _BudgetPerformance extends ConsumerWidget {
  const _BudgetPerformance({required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(_rangeBudgetProvider(month));
    return progress.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Text('Budget data is unavailable.'),
      data: (list) {
        if (list.isEmpty) {
          return const AppCard(
            child: Text('No budget was active in this month.'),
          );
        }
        return Column(
          children: [
            for (final p in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: BudgetProgressCard(progress: p, compact: true),
              ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.minor,
    required this.color,
    this.signed = false,
    this.footnote,
  });
  final String label;
  final int minor;
  final Color color;
  final bool signed;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              minor,
              color: color,
              signed: signed,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (footnote != null)
            Text(
              footnote!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
            ),
        ],
      ),
    );
  }
}

class _Compare extends StatelessWidget {
  const _Compare({
    required this.label,
    required this.now,
    required this.before,
    required this.higherIsGood,
  });
  final String label;
  final int now;
  final int before;
  final bool higherIsGood;

  @override
  Widget build(BuildContext context) {
    final change = percentChange(now, before);
    final up = now >= before;
    final good = up == higherIsGood;
    final color = now == before
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (good ? context.finance.income : context.finance.expense);
    final text = change == null
        ? (before == 0 && now == 0 ? 'No change' : 'New')
        : '${change > 0 ? '+' : ''}$change%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          MoneyText(
            before,
            hideZeroFraction: true,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 14),
          ),
          MoneyText(
            now,
            hideZeroFraction: true,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(width: 10),
          Semantics(
            label: '$label ${up ? 'increased' : 'decreased'} $text',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    now == before
                        ? Icons.remove
                        : (up ? Icons.arrow_upward : Icons.arrow_downward),
                    size: 12,
                    color: color,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    text,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
