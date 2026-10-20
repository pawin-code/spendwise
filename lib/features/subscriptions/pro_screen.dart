import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/services/billing/billing_config.dart';
import 'package:spendwise/services/billing/billing_gateway.dart';
import 'package:spendwise/services/billing/subscription_repository.dart';
import 'package:url_launcher/url_launcher.dart';

class ProScreen extends ConsumerStatefulWidget {
  const ProScreen({super.key});

  @override
  ConsumerState<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends ConsumerState<ProScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh the product list (prices) when the screen opens.
    Future.microtask(() {
      final s = ref.read(billingProvider);
      if (s.products.isEmpty && s.phase != BillingPhase.loading) {
        ref.read(subscriptionRepositoryProvider).refreshProducts();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(billingProvider);
    final repo = ref.read(subscriptionRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final ent = billing.entitlement;
    final busy =
        billing.phase == BillingPhase.purchasing ||
        billing.phase == BillingPhase.restoring;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('SpendWise Pro'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [scheme.secondary, scheme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.workspace_premium,
                    color: scheme.onPrimary,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Do more with your money',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The free plan is complete and stays free: unlimited entries, budgets, reminders, reports and CSV export. Pro adds extras and supports development.',
                    style: TextStyle(
                      color: scheme.onPrimary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            if (ent.isPro) ...[
              const SizedBox(height: 16),
              AppCard(
                child: Row(
                  children: [
                    Icon(Icons.verified, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pro is active${ent.expiresAt == null ? '' : ' (confirmed until ${formatDay(ent.expiresAt!)})'}. ${ent.message}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.push(Routes.subscription),
                child: const Text('Manage subscription'),
              ),
            ],
            const SectionHeader('Free vs Pro'),
            const AppCard(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  _CompareHeader(),
                  _CompareRow(
                    'Unlimited income & expenses',
                    free: true,
                    pro: true,
                  ),
                  _CompareRow(
                    'Budgets, alerts & bill reminders',
                    free: true,
                    pro: true,
                  ),
                  _CompareRow('Daily to yearly reports', free: true, pro: true),
                  _CompareRow(
                    'CSV import & export, local backup',
                    free: true,
                    pro: true,
                  ),
                  _CompareRow(
                    'Custom report date ranges',
                    free: false,
                    pro: true,
                  ),
                  _CompareRow('Extra colour themes', free: false, pro: true),
                  _CompareRow(
                    'Auto-record recurring items',
                    free: false,
                    pro: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Planned for later (not included yet): optional encrypted cloud backup and multi-device sync.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!ent.isPro) ...[
              const SectionHeader('Choose a plan'),
              if (billing.phase == BillingPhase.loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (billing.products.isEmpty)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cloud_off_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              billing.message ??
                                  'Plans are not available right now.',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Everything free keeps working. You can try again at any time.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => repo.refreshProducts(),
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final p in billing.products)
                  _PlanCard(product: p, busy: busy, onBuy: () => repo.buy(p)),
              if (ent.pending || (ent.message.isNotEmpty && !ent.isPro))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    ent.message,
                    style: TextStyle(color: scheme.tertiary),
                  ),
                ),
            ],
            if (billing.message != null && billing.products.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  billing.message!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => repo.restore(),
                    child: const Text('Restore purchases'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => launchUrl(
                      repo.manageSubscriptionUri(),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Manage in Google Play'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Subscriptions renew automatically at the price shown by Google Play until you cancel. Cancel any time in Google Play > Payments & subscriptions > Subscriptions; you keep Pro until the end of the period you paid for. Payment is charged to your Google account.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              children: [
                TextButton(
                  onPressed: () => context.push(Routes.legal('terms')),
                  child: const Text('Terms of service'),
                ),
                TextButton(
                  onPressed: () => context.push(Routes.legal('privacy')),
                  child: const Text('Privacy policy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.product,
    required this.busy,
    required this.onBuy,
  });
  final BillingProduct product;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final annual = product.id == BillingConfig.annualProductId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    annual ? 'Annual' : 'Monthly',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  product.priceText,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Billed ${annual ? 'once a year' : 'every month'}. Auto-renews until cancelled.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onBuy,
                child: Text('Subscribe ${annual ? 'yearly' : 'monthly'}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareHeader extends StatelessWidget {
  const _CompareHeader();
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          SizedBox(
            width: 56,
            child: Text('Free', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 56,
            child: Text('Pro', style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow(this.label, {required this.free, required this.pro});
  final String label;
  final bool free;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    Widget mark(bool v) => SizedBox(
      width: 56,
      child: Icon(
        v ? Icons.check_circle : Icons.remove,
        size: 20,
        color: v
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
        semanticLabel: v ? 'Included' : 'Not included',
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          mark(free),
          mark(pro),
        ],
      ),
    );
  }
}
