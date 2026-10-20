import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/features/settings/notification_actions.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final isPro = ref.watch(isProProvider);
    final cur = currencyByCode(s.currencyCode);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          AppCard(
            onTap: () => context.push(isPro ? Routes.subscription : Routes.pro),
            child: Row(
              children: [
                Icon(
                  isPro ? Icons.verified : Icons.workspace_premium_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPro ? 'SpendWise Pro' : 'Free plan',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        isPro ? 'Manage your subscription' : 'See what Pro adds — everything essential stays free',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SectionHeader('Appearance'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) =>
                      n.update((x) => x.copyWith(themeMode: v.first)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Accent colour',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final a in kAccentThemes)
                      Semantics(
                        button: true,
                        selected: (isPro ? s.accent : 'emerald') == a.key,
                        label:
                            '${a.name} accent${a.pro && !isPro ? ', requires Pro' : ''}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () {
                            if (a.pro && !isPro) {
                              context.push(Routes.pro);
                            } else {
                              n.update((x) => x.copyWith(accent: a.key));
                            }
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: a.seed,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  if ((isPro ? s.accent : 'emerald') == a.key)
                                    const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                    ),
                                  if (a.pro && !isPro)
                                    const Icon(
                                      Icons.lock_outline,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                a.name,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Money'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.currency_rupee),
                  title: const Text('Currency'),
                  subtitle: Text('${cur.code} — ${cur.name}'),
                  onTap: () => _pickCurrency(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.event_repeat),
                  title: const Text('Planned income day'),
                  subtitle: Text(
                    s.plannedIncomeDay == null
                        ? 'Not set'
                        : 'Day ${s.plannedIncomeDay} of each month',
                  ),
                  onTap: () => _pickIncomeDay(context, ref),
                ),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Categories'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.categories),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Wallets & accounts'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.wallets),
                ),
                ListTile(
                  leading: const Icon(Icons.repeat),
                  title: const Text('Recurring transactions'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.recurring),
                ),
                ListTile(
                  leading: const Icon(Icons.event_note_outlined),
                  title: const Text('Bill reminders'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.bills),
                ),
              ],
            ),
          ),
          const SectionHeader('Notifications'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Bill reminders'),
                  subtitle: const Text(
                    'Asks Android for permission only when you turn this on',
                  ),
                  value: s.notificationsEnabled,
                  onChanged: (v) async {
                    if (v) {
                      await enableNotifications(context, ref);
                    } else {
                      await disableNotifications(ref);
                    }
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.pie_chart_outline),
                  title: const Text('Budget alerts'),
                  subtitle: const Text(
                    'At your warning level and at 100% (needs notifications on)',
                  ),
                  value: s.budgetAlertsEnabled,
                  onChanged: (v) =>
                      n.update((x) => x.copyWith(budgetAlertsEnabled: v)),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Reminder time'),
                  subtitle: Text(
                    TimeOfDay(hour: s.reminderHour, minute: 0).format(context),
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: s.reminderHour, minute: 0),
                    );
                    if (t != null) {
                      await n.update((x) => x.copyWith(reminderHour: t.hour));
                    }
                  },
                ),
              ],
            ),
          ),
          const SectionHeader('Data & privacy'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.import_export),
                  title: const Text('Import & export'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.importExport),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Recently deleted'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.deleted),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Privacy & data management'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.privacy),
                ),
              ],
            ),
          ),
          const SectionHeader('About'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About & support'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.about),
                ),
                ListTile(
                  leading: const Icon(Icons.policy_outlined),
                  title: const Text('Privacy policy'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.legal('privacy')),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of service'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.legal('terms')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCurrency(BuildContext context, WidgetRef ref) async {
    final current = ref.read(settingsProvider).currencyCode;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Display currency'),
            ),
            for (final c in kCurrencies)
              ListTile(
                selected: c.code == current,
                title: Text('${c.code} — ${c.name}'),
                subtitle: Text('Example: ${formatMinor(123456, currency: c)}'),
                trailing: c.code == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, c.code),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Changing the currency only changes the symbol and number format. Amounts you already entered are not converted.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(currencyCode: picked));
    }
  }

  Future<void> _pickIncomeDay(BuildContext context, WidgetRef ref) async {
    final current = ref.read(settingsProvider).plannedIncomeDay;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Planned income day'),
        children: [
          SizedBox(
            width: 300,
            height: 360,
            child: ListView(
              children: [
                ListTile(
                  title: const Text('Not set'),
                  onTap: () => Navigator.pop(ctx, 0),
                  selected: current == null,
                ),
                for (var d = 1; d <= 28; d++)
                  ListTile(
                    title: Text('Day $d'),
                    selected: current == d,
                    onTap: () => Navigator.pop(ctx, d),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      await ref
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(plannedIncomeDay: picked == 0 ? null : picked),
          );
    }
  }
}
