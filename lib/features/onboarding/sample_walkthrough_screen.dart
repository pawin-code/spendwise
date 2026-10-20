import 'package:flutter/material.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/common.dart';

/// A guided tour using clearly-labelled illustrative numbers. Nothing here is
/// read from or written to the real transaction database.
class SampleWalkthroughScreen extends StatelessWidget {
  const SampleWalkthroughScreen({super.key});

  static const _income = 6500000; // 65,000.00
  static const _expense = 4120000;
  static const _budget = 5000000;
  static const _lines = [
    ('Food & groceries', 1250000, Icons.restaurant, 0xFFEF6C00),
    ('Rent & housing', 1800000, Icons.home, 0xFF6D4C41),
    ('Transport', 420000, Icons.directions_bus, 0xFF1976D2),
    ('Entertainment', 650000, Icons.movie, 0xFFC2185B),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sample walkthrough')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Illustrative sample only. These numbers are not saved and are not your data.',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Step(
            number: 1,
            title: 'Your month at a glance',
            text: 'The Home screen totals the income and expenses you record.',
            child: Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Income',
                    value: formatMinor(_income),
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Stat(
                    label: 'Expenses',
                    value: formatMinor(_expense),
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
          _Step(
            number: 2,
            title: 'Budgets show what is left',
            text: 'Set a monthly budget and watch the bar. You get an optional alert at 80% and 100%.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: _expense / _budget,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatMinor(_budget - _expense)} left of ${formatMinor(_budget)} (82% used)',
                ),
              ],
            ),
          ),
          _Step(
            number: 3,
            title: 'Spot where money goes',
            text: 'Categories reveal your biggest spending areas in Reports.',
            child: Column(
              children: [
                for (final l in _lines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CategoryAvatar(iconKey: 'category', color: l.$4),
                    title: Text(l.$1),
                    trailing: Text(formatMinor(l.$2)),
                  ),
              ],
            ),
          ),
          _Step(
            number: 4,
            title: 'Safe-to-Spend',
            text: 'An estimate of what you can spend per day: (budget − spent − bills still due) ÷ days left. It is based only on your own records.',
            child: const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back to setup'),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.text,
    required this.child,
  });
  final int number;
  final String title;
  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 14, child: Text('$number')),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(text),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 2),
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    ],
  );
}
