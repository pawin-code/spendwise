import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';

class SpendWiseApp extends ConsumerStatefulWidget {
  const SpendWiseApp({super.key, this.initialLocation = Routes.splash});
  final String initialLocation;

  @override
  ConsumerState<SpendWiseApp> createState() => _SpendWiseAppState();
}

class _SpendWiseAppState extends ConsumerState<SpendWiseApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isPro = ref.watch(isProProvider);
    // Keep bill reminders in sync with the database and notification settings.
    ref.watch(reminderSyncProvider);
    // Non-Pro users always render with the free accent.
    final accent = isPro ? settings.accent : 'emerald';
    return MaterialApp.router(
      title: 'SpendWise',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(Brightness.light, accent: accent),
      darkTheme: buildTheme(Brightness.dark, accent: accent),
      routerConfig: _router,
    );
  }
}
