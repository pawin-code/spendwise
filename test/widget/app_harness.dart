import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/app.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/database/seed.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

import '../helpers.dart';

class Harness {
  Harness(this.container);
  final ProviderContainer container;
  AppDatabase get db => container.read(databaseProvider);

  /// Runs real async work (database I/O) outside the fake-async test zone.
  Future<T> run<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body))!;
}

/// Boots the full app on an in-memory database.
Future<Harness> pumpApp(
  WidgetTester tester, {
  String location = Routes.home,
  bool onboardingDone = true,
  bool pro = false,
  Size size = const Size(412, 3000),
  Future<void> Function(ProviderContainer c)? seed,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = (await tester.runAsync(
    () => makeContainer(
      prefs: {'onboarding_done': onboardingDone},
      overrides: [if (pro) isProProvider.overrideWithValue(true)],
    ),
  ))!;
  final harness = Harness(container);
  // Seed BEFORE the UI exists: writes made while live queries are waiting on the
  // fake-async clock can stall, so tests seed first and then boot the app.
  if (seed != null) await tester.runAsync(() => seed(container));
  addTearDown(() async {
    // Unmount first so streams are cancelled before the database closes.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    container.dispose();
    await tester.runAsync(() => harness.db.close());
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: SpendWiseApp(initialLocation: location),
    ),
  );
  await settle(tester);
  return harness;
}

/// pumpAndSettle that tolerates database streams delivering over a few frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

/// Salary 50,000 + two expenses (1,234.50 and 800) in the current month.
Future<void> seedBasics(ProviderContainer c) async {
  final ledger = c.read(ledgerServiceProvider);
  final now = DateTime.now();
  await ledger.add(
    TxnInput(
      type: TxnType.income,
      amountMinor: 5000000,
      walletId: kDefaultWalletId,
      categoryId: 'cat_salary',
      occurredAt: DateTime(now.year, now.month, 1),
    ),
  );
  await ledger.add(
    TxnInput(
      type: TxnType.expense,
      amountMinor: 123450,
      walletId: kDefaultWalletId,
      categoryId: 'cat_food',
      occurredAt: DateTime(now.year, now.month, 2),
      payee: 'Big Basket',
    ),
  );
  await ledger.add(
    TxnInput(
      type: TxnType.expense,
      amountMinor: 80000,
      walletId: kDefaultWalletId,
      categoryId: 'cat_transport',
      occurredAt: DateTime(now.year, now.month, 2),
    ),
  );
}

/// Performs a database write while the UI is live, pumping until it finishes.
Future<T> write<T>(WidgetTester tester, Future<T> Function() op) async {
  var done = false;
  Object? error;
  late T result;
  op()
      .then((v) {
        result = v;
        done = true;
      })
      .catchError((Object e) {
        error = e;
        done = true;
      });
  for (var i = 0; i < 200 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!done) fail('database write did not finish');
  if (error != null) throw error!;
  await settle(tester);
  return result;
}

/// Navigates the running app to [path] (as a deep link / push would).
Future<void> go(WidgetTester tester, String path, {bool push = true}) async {
  final context = tester.element(find.byType(Scaffold).first);
  final router = GoRouter.of(context);
  if (push) {
    router.push(path);
  } else {
    router.go(path);
  }
  await settle(tester);
}

/// Taps a bottom-navigation destination (not a same-named heading elsewhere).
Future<void> tapNav(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

/// Pops the top route (works for screens with a custom close button too).
Future<void> back(WidgetTester tester) async {
  GoRouter.of(tester.element(find.byType(Scaffold).last)).pop();
  await settle(tester);
}
