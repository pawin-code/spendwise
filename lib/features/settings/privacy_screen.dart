import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/widgets/common.dart';

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Fact(
            Icons.phone_android,
            'Stored on this device',
            'Your transactions, budgets, wallets and categories live in SpendWise\'s private app storage. They are not uploaded anywhere, and there is no SpendWise account.',
          ),
          const _Fact(
            Icons.shield_outlined,
            'How it is protected',
            'The database is not separately encrypted by SpendWise. It is protected by Android\'s app sandbox and your phone\'s screen lock (and device encryption, which Android enables by default). Android cloud backup of app data is turned off for SpendWise.',
          ),
          const _Fact(
            Icons.visibility_off_outlined,
            'What we never ask for',
            'No bank logins, card numbers, PINs or OTPs. No SMS, contacts, call log or location access. No analytics or advertising trackers in this version.',
          ),
          const _Fact(
            Icons.delete_sweep_outlined,
            'If you uninstall',
            'Uninstalling SpendWise deletes its stored records from the phone. Back up first (Import & export) if you want to keep them. Files you exported yourself stay where you saved them.',
          ),
          const _Fact(
            Icons.notifications_outlined,
            'Permissions used',
            'Notifications (only if you turn reminders on), and optional boot-time rescheduling so reminders survive a restart. Saving and opening files uses Android\'s file picker, so no storage permission is needed.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.policy_outlined),
            label: const Text('Read the privacy policy'),
            onPressed: () => context.push(Routes.legal('privacy')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Recently deleted'),
            onPressed: () => context.push(Routes.deleted),
          ),
          const SectionHeader('Delete my data'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Erase all data removes every transaction, budget, wallet, category, reminder and setting from this device, and cancels scheduled reminders. This cannot be undone.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Erase all data'),
                  onPressed: () => _erase(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _erase(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _EraseDialog(),
    );
    if (confirmed != true) return;
    try {
      await ref.read(notificationServiceProvider).cancelAll();
      await ref.read(databaseProvider).wipeAll();
      await ref.read(settingsRepositoryProvider).clear();
      ref.invalidate(settingsProvider);
      // Drop the cached purchase record; Google Play re-confirms any real subscription.
      final billing = ref.read(subscriptionRepositoryProvider);
      await billing.clearLocalEntitlement();
      unawaited(billing.restore());
      if (context.mounted) {
        context.go(Routes.splash);
      }
    } catch (_) {
      if (context.mounted) {
        showSnack(context, 'Could not erase data. Nothing was changed.');
      }
    }
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Owns its text controller so it is disposed only after the dialog is gone.
class _EraseDialog extends StatefulWidget {
  const _EraseDialog();

  @override
  State<_EraseDialog> createState() => _EraseDialogState();
}

class _EraseDialogState extends State<_EraseDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Erase all data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Everything you entered will be permanently deleted from this device. Create a backup first if you might need it.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Type DELETE to confirm',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _controller.text.trim() == 'DELETE'
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('Erase everything'),
        ),
      ],
    );
  }
}
