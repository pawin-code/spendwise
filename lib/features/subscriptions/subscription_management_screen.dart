import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/services/billing/billing_config.dart';
import 'package:spendwise/services/billing/entitlement.dart';
import 'package:spendwise/services/billing/subscription_repository.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionManagementScreen extends ConsumerWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billing = ref.watch(billingProvider);
    final repo = ref.read(subscriptionRepositoryProvider);
    final ent = billing.entitlement;
    final busy = billing.phase == BillingPhase.restoring;
    final plan = ent.productId == null
        ? '—'
        : (ent.productId == BillingConfig.annualProductId
              ? 'Pro (yearly)'
              : (ent.productId == BillingConfig.monthlyProductId
                    ? 'Pro (monthly)'
                    : 'Pro'));
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ent.isPro
                          ? Icons.verified
                          : Icons.workspace_premium_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ent.isPro ? 'SpendWise Pro' : 'Free plan',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Line('Plan', ent.isPro ? plan : 'Free'),
                _Line('Confirmation', switch (ent.source) {
                  EntitlementSource.serverVerified =>
                    'Verified with the purchase server',
                  EntitlementSource.googlePlay =>
                    'Confirmed by Google Play on this device',
                  EntitlementSource.none =>
                    ent.pending
                        ? 'Pending payment'
                        : 'No active subscription found',
                }),
                if (ent.expiresAt != null)
                  _Line(
                    ent.source == EntitlementSource.googlePlay
                        ? 'Re-check by'
                        : 'Valid until',
                    formatDay(ent.expiresAt!),
                  ),
                if (ent.message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      ent.message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!ent.isPro)
            FilledButton(
              onPressed: () => context.push(Routes.pro),
              child: const Text('See SpendWise Pro'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(
              repo.manageSubscriptionUri(),
              mode: LaunchMode.externalApplication,
            ),
            label: const Text('Manage or cancel in Google Play'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : () => repo.restore(),
            label: Text(
              busy ? 'Checking…' : 'Restore purchases / refresh status',
            ),
          ),
          if (billing.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(billing.message!),
            ),
          const SizedBox(height: 20),
          Text(
            'Cancelling stops future renewals; Pro stays active until the end of the period you already paid for. Your records and all free features are never locked, whether or not you subscribe.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!BillingConfig.verifierConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Developer note: no purchase-verification server is configured in this build, so Pro is granted from Google Play\'s own on-device purchase record and re-checked at least every 72 hours.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
