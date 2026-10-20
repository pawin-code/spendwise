import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/brand_mark.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';

class _Page {
  const _Page(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _Page(
    Icons.swap_vert_circle_outlined,
    'Track every rupee',
    'Add income and expenses in seconds with a big keypad and smart categories. Your balance, spending and savings update instantly.',
  ),
  _Page(
    Icons.pie_chart_outline,
    'Budgets and reminders',
    'Set a monthly or category budget, get a heads-up at 80% and 100%, and never miss rent, bills or subscriptions.',
  ),
  _Page(
    Icons.lock_outline,
    'Private by design',
    'Your records are stored on this device. No account is needed, and SpendWise never reads your SMS, contacts or bank logins.',
  ),
  _Page(
    Icons.cloud_off_outlined,
    'Optional extras',
    'Everything essential works offline. Only SpendWise Pro purchases need internet and a Google account; cloud sync is not part of this version.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  String _currency = 'INR';
  final _budgetCtrl = TextEditingController();
  int? _incomeDay;
  bool _saving = false;
  String? _budgetError;

  bool get _onSetup => _index == _pages.length;

  @override
  void dispose() {
    _controller.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish({bool skip = false}) async {
    if (_saving) return;
    int? budget;
    if (!skip && _budgetCtrl.text.trim().isNotEmpty) {
      budget = parseAmountToMinor(_budgetCtrl.text);
      if (budget == null || budget <= 0) {
        setState(
          () => _budgetError = 'Enter a valid amount, e.g. 25000 or 25000.50',
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(
              onboardingDone: true,
              currencyCode: skip ? s.currencyCode : _currency,
              plannedIncomeDay: skip ? null : _incomeDay,
            ),
          );
      if (budget != null) {
        await ref
            .read(budgetRepositoryProvider)
            .save(
              amountMinor: budget,
              startMonth: startOfMonth(DateTime.now()),
            );
      }
      if (mounted) context.go(Routes.home);
    } on ValidationException catch (e) {
      if (mounted) setState(() => _budgetError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _saving ? null : () => _finish(skip: true),
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  for (final p in _pages) _InfoPage(page: p),
                  _SetupPage(
                    currency: _currency,
                    onCurrency: (c) => setState(() => _currency = c),
                    budgetCtrl: _budgetCtrl,
                    budgetError: _budgetError,
                    incomeDay: _incomeDay,
                    onIncomeDay: (d) => setState(() => _incomeDay = d),
                    onSample: () => context.push(Routes.sample),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i <= _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? scheme.primary
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving
                      ? null
                      : () {
                          if (_onSetup) {
                            _finish();
                          } else {
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                  child: Text(_onSetup ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPage extends StatelessWidget {
  const _InfoPage({required this.page});
  final _Page page;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Branded hero panel: gradient, soft orbs, app mark and the page glyph.
            Container(
              width: double.infinity,
              height: 230,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: context.finance.heroGradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.finance.heroGradient.last.withValues(
                      alpha: 0.3,
                    ),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      right: -40,
                      top: -50,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -30,
                      bottom: -60,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Brand.emeraldMint.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandMark(size: 64),
                        const SizedBox(height: 18),
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Icon(page.icon, size: 36, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              page.title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              page.body,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.currency,
    required this.onCurrency,
    required this.budgetCtrl,
    required this.budgetError,
    required this.incomeDay,
    required this.onIncomeDay,
    required this.onSample,
  });

  final String currency;
  final ValueChanged<String> onCurrency;
  final TextEditingController budgetCtrl;
  final String? budgetError;
  final int? incomeDay;
  final ValueChanged<int?> onIncomeDay;
  final VoidCallback onSample;

  @override
  Widget build(BuildContext context) {
    final cur = currencyByCode(currency);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick setup',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'All optional. You can change these later in Settings.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: [
              for (final c in kCurrencies)
                DropdownMenuItem(
                  value: c.code,
                  child: Text('${c.code} — ${c.name}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) onCurrency(v);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: budgetCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monthly budget (optional)',
              prefixText: '${cur.symbol} ',
              errorText: budgetError,
              helperText: 'Total you plan to spend each month',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            isExpanded: true,
            initialValue: incomeDay,
            decoration: const InputDecoration(
              labelText: 'Planned income day (optional)',
              helperText: 'Used to estimate how long your money has to last',
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Not set')),
              for (var d = 1; d <= 28; d++)
                DropdownMenuItem<int?>(
                  value: d,
                  child: Text('Day $d of each month'),
                ),
            ],
            onChanged: onIncomeDay,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onSample,
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('See a sample walkthrough (no data is saved)'),
          ),
        ],
      ),
    );
  }
}
