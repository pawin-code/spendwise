import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/domain/calculations.dart';

class CategorySlice {
  const CategorySlice(this.name, this.color, this.amountMinor);
  final String name;
  final Color color;
  final int amountMinor;
}

List<CategorySlice> slicesFrom(
  Map<String, int> totals,
  Map<String, CategoryRow> cats, {
  int maxSlices = 6,
}) {
  final entries = totals.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final slices = <CategorySlice>[];
  var other = 0;
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (i < maxSlices) {
      final c = cats[e.key];
      slices.add(
        CategorySlice(
          c?.name ?? (e.key == kUncategorized ? 'Uncategorized' : 'Unknown'),
          Color(c?.colorValue ?? 0xFF607D8B),
          e.value,
        ),
      );
    } else {
      other += e.value;
    }
  }
  if (other > 0) {
    slices.add(
      CategorySlice('Everything else', const Color(0xFF90A4AE), other),
    );
  }
  return slices;
}

/// Donut chart with a text legend (colour is never the only cue).
class CategoryDonut extends ConsumerWidget {
  const CategoryDonut({super.key, required this.slices, this.centerLabel});
  final List<CategorySlice> slices;
  final String? centerLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(currencyProvider);
    final total = slices.fold<int>(0, (a, s) => a + s.amountMinor);
    if (total == 0) return const SizedBox.shrink();
    final semanticsLabel =
        'Spending by category: ${slices.map((s) => '${s.name} ${formatMinor(s.amountMinor, currency: cur)}').join(', ')}';
    return Column(
      children: [
        Semantics(
          label: semanticsLabel,
          child: SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ExcludeSemantics(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 58,
                      sections: [
                        for (final s in slices)
                          PieChartSectionData(
                            value: s.amountMinor.toDouble(),
                            color: s.color,
                            radius: 26,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerLabel ?? 'Total',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      formatMinor(total, currency: cur, hideZeroFraction: true),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${s.amountMinor * 100 ~/ total}% · ${formatMinor(s.amountMinor, currency: cur, hideZeroFraction: true)}',
                    style: Theme.of(context).textTheme.labelLarge,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class BarPoint {
  const BarPoint(this.label, this.incomeMinor, this.expenseMinor);
  final String label;
  final int incomeMinor;
  final int expenseMinor;
}

/// Grouped income-vs-expense bars with a legend.
class IncomeExpenseBars extends ConsumerWidget {
  const IncomeExpenseBars({
    super.key,
    required this.points,
    required this.incomeColor,
    required this.expenseColor,
  });
  final List<BarPoint> points;
  final Color incomeColor;
  final Color expenseColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(currencyProvider);
    final maxMinor = points.fold<int>(
      0,
      (m, p) =>
          [m, p.incomeMinor, p.expenseMinor].reduce((a, b) => a > b ? a : b),
    );
    if (maxMinor == 0) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.labelSmall;
    return Column(
      children: [
        Semantics(
          label:
              'Income versus expenses: ${points.map((p) => '${p.label} income ${formatMinor(p.incomeMinor, currency: cur)}, expenses ${formatMinor(p.expenseMinor, currency: cur)}').join('; ')}',
          child: SizedBox(
            height: 200,
            child: ExcludeSemantics(
              child: BarChart(
                BarChartData(
                  maxY: maxMinor * 1.15,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= points.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(points[i].label, style: style),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 3,
                        barRods: [
                          BarChartRodData(
                            toY: points[i].incomeMinor.toDouble(),
                            color: incomeColor,
                            width: 9,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          BarChartRodData(
                            toY: points[i].expenseMinor.toDouble(),
                            color: expenseColor,
                            width: 9,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          runSpacing: 4,
          children: [
            _Legend(color: incomeColor, label: 'Income'),
            _Legend(color: expenseColor, label: 'Expenses'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

class TrendPoint {
  const TrendPoint(this.label, this.valueMinor);
  final String label;
  final int valueMinor;
}

/// Spending trend line.
class SpendingTrendLine extends ConsumerWidget {
  const SpendingTrendLine({
    super.key,
    required this.points,
    required this.color,
  });
  final List<TrendPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(currencyProvider);
    final maxMinor = points.fold<int>(
      0,
      (m, p) => p.valueMinor > m ? p.valueMinor : m,
    );
    if (maxMinor == 0 || points.length < 2) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.labelSmall;
    final step = (points.length / 6).ceil().clamp(1, 100);
    return Semantics(
      label:
          'Spending trend: ${points.map((p) => '${p.label} ${formatMinor(p.valueMinor, currency: cur)}').join(', ')}',
      child: SizedBox(
        height: 180,
        child: ExcludeSemantics(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxMinor * 1.15,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  strokeWidth: 0.6,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length || i % step != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(points[i].label, style: style),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].valueMinor.toDouble()),
                  ],
                  isCurved: true,
                  color: color,
                  barWidth: 3,
                  dotData: FlDotData(show: points.length <= 12),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
