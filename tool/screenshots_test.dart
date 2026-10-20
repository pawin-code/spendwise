// Renders the real UI (real fonts, sample data) to PNG files for design review and
// store screenshots. Not part of the normal suite:
//   flutter test tool/screenshots_test.dart --update-goldens
// Output: tool/shots/*.png
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/data/database/seed.dart';
import 'package:spendwise/data/repositories/recurring_repository.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

import '../test/widget/app_harness.dart';

Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$root/bin/cache/artifacts/material_fonts/$f')
          .readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

Future<void> seedDemo(ProviderContainer c) async {
  final tx = c.read(transactionRepositoryProvider);
  final wallets = c.read(walletRepositoryProvider);
  final bank = await wallets.add(
    name: 'HDFC Savings',
    kind: WalletKind.bank,
    openingBalanceMinor: 4500000,
    colorValue: 0xFF1D4ED8,
  );
  final upi = await wallets.add(
    name: 'UPI',
    kind: WalletKind.digital,
    openingBalanceMinor: 250000,
    colorValue: 0xFF6D28D9,
  );
  final now = DateTime.now();
  Future<void> e(
    int day,
    int amt,
    String cat,
    String payee, {
    String w = kDefaultWalletId,
    int monthsAgo = 0,
  }) async {
    final m = DateTime(now.year, now.month - monthsAgo, 1);
    await tx.add(
      TxnInput(
        type: TxnType.expense,
        amountMinor: amt,
        walletId: w,
        categoryId: cat,
        occurredAt: DateTime(
          m.year,
          m.month,
          day.clamp(1, daysInMonth(m.year, m.month)),
        ),
        payee: payee,
      ),
    );
  }

  Future<void> i(
    int day,
    int amt,
    String cat,
    String payee, {
    int monthsAgo = 0,
  }) async {
    final m = DateTime(now.year, now.month - monthsAgo, 1);
    await tx.add(
      TxnInput(
        type: TxnType.income,
        amountMinor: amt,
        walletId: bank,
        categoryId: cat,
        occurredAt: DateTime(m.year, m.month, day),
        payee: payee,
      ),
    );
  }

  for (var k = 2; k >= 0; k--) {
    await i(1, 7500000, 'cat_salary', 'Acme Tech', monthsAgo: k);
    if (k != 1) {
      await i(12, 1200000, 'cat_freelance', 'Design client', monthsAgo: k);
    }
    await e(2, 1800000, 'cat_rent', 'House rent', w: bank, monthsAgo: k);
    await e(3, 215000, 'cat_bills', 'Electricity', w: upi, monthsAgo: k);
    await e(4, 95000, 'cat_bills', 'Broadband', w: upi, monthsAgo: k);
    await e(5, 184050, 'cat_food', 'Big Basket', w: upi, monthsAgo: k);
    await e(8, 62000, 'cat_transport', 'Metro card', monthsAgo: k);
    await e(11, 249900, 'cat_shopping', 'Shoes', w: upi, monthsAgo: k);
    await e(
      14,
      129900,
      'cat_entertainment',
      'Weekend movie + dinner',
      monthsAgo: k,
    );
    await e(17, 158000, 'cat_food', 'Fresh Mart', w: upi, monthsAgo: k);
    await e(19, 80000, 'cat_health', 'Pharmacy', monthsAgo: k);
  }
  final budgets = c.read(budgetRepositoryProvider);
  final start = DateTime(now.year, now.month - 2);
  await budgets.save(amountMinor: 6500000, startMonth: start);
  await budgets.save(
    categoryId: 'cat_food',
    amountMinor: 600000,
    startMonth: start,
  );
  await budgets.save(
    categoryId: 'cat_shopping',
    amountMinor: 250000,
    startMonth: start,
  );
  final rec = c.read(recurringRepositoryProvider);
  final today = dateOnly(now);
  await rec.add(
    RuleInput(
      title: 'Home loan EMI',
      kind: ReminderKind.loan,
      type: CategoryType.expense,
      amountMinor: 1200000,
      walletId: bank,
      frequency: Frequency.monthly,
      startDate: today.add(const Duration(days: 3)),
    ),
  );
  await rec.add(
    RuleInput(
      title: 'Electricity bill',
      kind: ReminderKind.utility,
      type: CategoryType.expense,
      amountMinor: 215000,
      walletId: upi,
      categoryId: 'cat_bills',
      frequency: Frequency.monthly,
      startDate: today.add(const Duration(days: 1)),
    ),
  );
}

void main() {
  setUpAll(loadFonts);

  Future<void> shot(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  const phone = Size(411, 914);

  testWidgets('light screens', (tester) async {
    await pumpApp(tester, seed: seedDemo, size: phone);
    await shot(tester, '01-home');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -820));
    await settle(tester);
    await shot(tester, '02-home-scroll');
    await tapNav(tester, 'Transactions');
    await shot(tester, '03-transactions');
    await tapNav(tester, 'Budgets');
    await shot(tester, '04-budgets');
    await tapNav(tester, 'Reports');
    await shot(tester, '05-reports');
    await go(tester, Routes.add);
    await shot(tester, '06-add');
    await back(tester);
    await tapNav(tester, 'Settings');
    await shot(tester, '07-settings');
    await go(tester, Routes.pro);
    await shot(tester, '08-pro');
  });

  testWidgets('dark home', (tester) async {
    await pumpApp(
      tester,
      seed: (c) async {
        await seedDemo(c);
        await c
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(themeMode: ThemeMode.dark));
      },
      size: phone,
    );
    await shot(tester, '09-home-dark');
    await tapNav(tester, 'Transactions');
    await shot(tester, '10-transactions-dark');
  });

  testWidgets('onboarding and splash', (tester) async {
    await pumpApp(
      tester,
      location: Routes.onboarding,
      onboardingDone: false,
      size: phone,
    );
    await shot(tester, '11-onboarding');
    await pumpApp(
      tester,
      location: Routes.splash,
      onboardingDone: false,
      size: phone,
    );
    await shot(tester, '12-splash');
    await tester.pump(const Duration(seconds: 2));
  });

  // Keep the theme import referenced for analyzer when shots are unused.
  test('theme builds', () => expect(buildTheme(Brightness.light), isNotNull));
}
