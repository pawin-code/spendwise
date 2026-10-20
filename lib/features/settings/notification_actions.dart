import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/core/widgets/common.dart';

/// Turns notifications on only after the user explicitly asks and Android
/// grants permission. If denied, every feature keeps working in-app.
Future<bool> enableNotifications(BuildContext context, WidgetRef ref) async {
  final granted = await ref
      .read(notificationServiceProvider)
      .requestPermission();
  if (granted) {
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(notificationsEnabled: true));
  } else if (context.mounted) {
    showSnack(
      context,
      'Notifications are off. You can still see bills and budgets inside SpendWise. To enable alerts, allow notifications in Android settings.',
    );
  }
  return granted;
}

Future<void> disableNotifications(WidgetRef ref) => ref
    .read(settingsProvider.notifier)
    .update((s) => s.copyWith(notificationsEnabled: false));
