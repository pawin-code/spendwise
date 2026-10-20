import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/data/database/seed.dart';
import 'package:spendwise/data/repositories/recurring_repository.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

import 'app_harness.dart';

void main() {
  group('budgets', () {
    testWidgets(
      'creating an overall budget saves it and shows progress from real spending',
      (tester) async {
        final h = await pumpApp(tester, seed: seedBasics);
        await tapNav(tester, 'Budgets');
        await settle(tester);
        expect(find.textContaining('No budget for'), findsOneWidget);

        await tester.tap(find.text('Create budget'));
        await settle(tester);
        expect(find.text('New budget'), findsOneWidget);

        // Validation first.
        await tester.tap(find.text('Create budget'));
        await settle(tester);
        expect(
          find.text('Enter a budget amount greater than zero.'),
          findsOneWidget,
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Monthly amount'),
          '4000',
        );
        await tester.tap(find.text('Create budget'));
        await settle(tester);

        final budgets = await write(
          tester,
          () => h.container.read(budgetRepositoryProvider).getAll(),
        );
        expect(budgets.single.amountMinor, 400000);
        expect(budgets.single.categoryId, isNull);
        // 1,234.50 + 800 = 2,034.50 spent of 4,000 -> 50% used.
        expect(find.text('Overall budget'), findsWidgets);
        expect(find.textContaining('50% used'), findsOneWidget);
      },
    );

    testWidgets('a category budget shows over-budget state', (tester) async {
      await pumpApp(
        tester,
        seed: (c) async {
          await seedBasics(c);
          await c
              .read(budgetRepositoryProvider)
              .save(
                categoryId: 'cat_food',
                amountMinor: 100000,
                startMonth: startOfMonth(DateTime.now()),
              );
        },
      );
      await go(tester, Routes.budgets, push: false);
      expect(find.text('Food & groceries'), findsWidgets);
      expect(find.textContaining('over budget'), findsOneWidget);
      expect(find.text('Over by '), findsOneWidget);
    });
  });

  group('reports', () {
    testWidgets('are computed from stored transactions', (tester) async {
      await pumpApp(tester, seed: seedBasics);
      await go(tester, Routes.reports, push: false);
      expect(find.text('Reports'), findsWidgets);
      expect(find.text('₹50,000.00'), findsOneWidget); // income
      expect(
        find.text('₹2,034.50'),
        findsWidgets,
      ); // expenses (card and chart total)
      expect(find.text('+₹47,965.50'), findsOneWidget); // net
      expect(find.text('Spending by category'), findsOneWidget);
      expect(find.text('Largest expenses'), findsOneWidget);
      expect(find.textContaining('2 expenses'), findsOneWidget);
    });

    testWidgets('empty periods say so instead of drawing empty charts', (
      tester,
    ) async {
      await pumpApp(tester);
      await go(tester, Routes.reports, push: false);
      expect(find.text('Nothing to report'), findsOneWidget);
    });

    testWidgets(
      'custom ranges are gated behind Pro with an explanation, not a forced purchase',
      (tester) async {
        await pumpApp(tester, seed: seedBasics);
        await go(tester, Routes.reports, push: false);
        expect(find.text('PRO'), findsOneWidget);
        await tester.ensureVisible(find.text('Custom'));
        await tester.tap(find.text('Custom'));
        await settle(tester);
        expect(find.text('Custom ranges are in Pro'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(find.text('Custom ranges are in Pro'), findsNothing);
        // Free periods keep working.
        await tester.tap(find.text('Yearly'));
        await settle(tester);
        expect(find.text('₹50,000.00'), findsOneWidget);
      },
    );

    testWidgets('Pro users get the custom range chip without a badge', (
      tester,
    ) async {
      await pumpApp(tester, seed: seedBasics, pro: true);
      await go(tester, Routes.reports, push: false);
      expect(find.text('PRO'), findsNothing);
    });
  });

  group('settings, theme and navigation', () {
    testWidgets('theme switching updates the app theme and is persisted', (
      tester,
    ) async {
      final h = await pumpApp(tester);
      await tapNav(tester, 'Settings');
      await settle(tester);
      await tester.tap(find.text('Dark'));
      await settle(tester);
      expect(h.container.read(settingsProvider).themeMode, ThemeMode.dark);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(
        h.container.read(sharedPrefsProvider).getString('theme_mode'),
        'dark',
      );
      await tester.tap(find.text('Light'));
      await settle(tester);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
    });

    testWidgets(
      'bottom navigation reaches every main screen and the add button is always available',
      (tester) async {
        await pumpApp(tester, seed: seedBasics);
        expect(find.byTooltip('Add transaction'), findsOneWidget);
        await tapNav(tester, 'Transactions');
        await settle(tester);
        expect(find.text('Big Basket'), findsOneWidget);
        await tapNav(tester, 'Budgets');
        await settle(tester);
        expect(find.text('Budgets'), findsWidgets);
        await tapNav(tester, 'Reports');
        await settle(tester);
        expect(find.text('Income vs expenses'), findsOneWidget);
        expect(find.text('Spending by category'), findsOneWidget);
        await tapNav(tester, 'Settings');
        await settle(tester);
        expect(find.text('Appearance'), findsOneWidget);
        expect(
          find.byTooltip('Add transaction'),
          findsNothing,
        ); // not shown on Settings
        await tapNav(tester, 'Home');
        await settle(tester);
        expect(find.text('Safe-to-Spend'), findsOneWidget);
      },
    );

    testWidgets('every settings row opens a working screen', (tester) async {
      await pumpApp(tester);
      await tapNav(tester, 'Settings');
      await settle(tester);
      final entries = {
        'Categories': 'Categories',
        'Wallets & accounts': 'Combined balance',
        'Recurring transactions': 'No recurring items',
        'Bill reminders': 'No bills yet',
        'Import & export': 'Export (CSV)',
        'Recently deleted': 'Nothing here',
        'Privacy & data management': 'Stored on this device',
        'About & support': 'Support',
      };
      for (final e in entries.entries) {
        await tester.tap(find.text(e.key).first);
        await settle(tester);
        expect(find.text(e.value), findsWidgets, reason: 'opening ${e.key}');
        await tester.pageBack();
        await settle(tester);
      }
    });

    testWidgets('currency can be changed and the app reformats amounts', (
      tester,
    ) async {
      final h = await pumpApp(tester, seed: seedBasics);
      await tapNav(tester, 'Settings');
      await settle(tester);
      await tester.tap(find.text('INR — Indian Rupee'));
      await settle(tester);
      await tester.tap(find.text('USD — US Dollar'));
      await settle(tester);
      expect(h.container.read(settingsProvider).currencyCode, 'USD');
      await tapNav(tester, 'Home');
      await settle(tester);
      expect(find.text(r'$50,000'), findsWidgets);
    });
  });

  group('categories & wallets', () {
    testWidgets('a custom category can be created and then used', (
      tester,
    ) async {
      final h = await pumpApp(tester);
      await go(tester, Routes.categories);
      await tester.tap(find.text('New category'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Pets');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Pets'), findsOneWidget);
      final all = await write(
        tester,
        () => h.container.read(categoryRepositoryProvider).getAll(),
      );
      expect(all.any((c) => c.name == 'Pets'), isTrue);
    });

    testWidgets(
      'duplicate category names show a friendly error and keep the sheet open',
      (tester) async {
        await pumpApp(tester);
        await go(tester, Routes.categories);
        await tester.tap(find.text('New category'));
        await settle(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Name'),
          'transport',
        );
        await tester.tap(find.text('Save'));
        await settle(tester);
        expect(find.textContaining('already exists'), findsOneWidget);
      },
    );

    testWidgets(
      'wallets list shows the default Cash wallet and opening balance',
      (tester) async {
        await pumpApp(
          tester,
          seed: (c) async {
            await c
                .read(walletRepositoryProvider)
                .add(
                  name: 'HDFC',
                  kind: WalletKind.bank,
                  openingBalanceMinor: 1250000,
                  colorValue: 1,
                );
          },
        );
        await go(tester, Routes.wallets);
        expect(find.text('Cash'), findsWidgets);
        expect(find.text('HDFC'), findsOneWidget);
        expect(find.text('₹12,500.00'), findsWidgets);
        expect(
          find.textContaining('does not connect to your bank'),
          findsOneWidget,
        );
      },
    );
  });

  group('bills and recurring', () {
    testWidgets(
      'mark-as-paid asks first, then records one transaction and advances the bill',
      (tester) async {
        late String ruleId;
        final h = await pumpApp(
          tester,
          seed: (c) async {
            ruleId = await c
                .read(recurringRepositoryProvider)
                .add(
                  RuleInput(
                    title: 'House rent',
                    kind: ReminderKind.rent,
                    type: CategoryType.expense,
                    amountMinor: 1500000,
                    walletId: kDefaultWalletId,
                    frequency: Frequency.monthly,
                    startDate: dateOnly(DateTime.now()),
                  ),
                );
          },
        );
        await go(tester, Routes.bills);
        expect(find.text('House rent'), findsOneWidget);
        expect(find.text('Due today'), findsOneWidget);
        expect(
          find.textContaining('never mark a bill as paid'),
          findsOneWidget,
        );

        // Nothing is recorded just because a reminder exists.
        expect(
          (await write(
            tester,
            () =>
                h.container.read(transactionRepositoryProvider).getAllActive(),
          )),
          isEmpty,
        );

        await tester.tap(find.text('Mark paid'));
        await settle(tester);
        expect(find.text('Mark as paid?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(
          (await write(
            tester,
            () =>
                h.container.read(transactionRepositoryProvider).getAllActive(),
          )),
          isEmpty,
        );

        await tester.tap(find.text('Mark paid'));
        await settle(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
        await settle(tester);
        final rows = await write(
          tester,
          () => h.container.read(transactionRepositoryProvider).getAllActive(),
        );
        expect(rows.single.amountMinor, 1500000);
        final rule = await write(
          tester,
          () => h.container.read(recurringRepositoryProvider).getById(ruleId),
        );
        expect(rule!.nextDue.isAfter(dateOnly(DateTime.now())), isTrue);
      },
    );

    testWidgets(
      'the reminder form validates and keeps the entered text on error',
      (tester) async {
        await pumpApp(tester);
        await go(tester, '${Routes.recurringEdit}?bill=1');
        await tester.enterText(
          find.widgetWithText(TextField, 'Title'),
          'Broadband',
        );
        await tester.tap(find.text('Save'));
        await settle(tester);
        expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
        expect(find.text('Broadband'), findsOneWidget);
      },
    );

    testWidgets('auto-recording is clearly a Pro option for free users', (
      tester,
    ) async {
      await pumpApp(tester);
      await go(tester, Routes.recurringEdit);
      expect(find.text('PRO'), findsOneWidget);
    });
  });

  group('free vs Pro', () {
    testWidgets(
      'the Pro screen is honest when Google Play is unavailable and never blocks free features',
      (tester) async {
        await pumpApp(tester);
        await go(tester, Routes.pro);
        expect(find.text('SpendWise Pro'), findsWidgets);
        expect(find.text('Free vs Pro'), findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
        expect(find.text('Restore purchases'), findsOneWidget);
        expect(find.text('Manage in Google Play'), findsOneWidget);
        expect(find.text('Terms of service'), findsOneWidget);
        expect(find.text('Privacy policy'), findsOneWidget);
        expect(find.textContaining('not available'), findsWidgets);
        expect(
          find.textContaining('₹49'),
          findsNothing,
        ); // prices only ever come from Google Play
        expect(find.textContaining('₹399'), findsNothing);
        await tester.tap(find.byTooltip('Close'));
        await settle(tester);
        expect(find.text('Welcome to SpendWise'), findsOneWidget);
      },
    );

    testWidgets('Pro users see manage options instead of upgrade prompts', (
      tester,
    ) async {
      await pumpApp(tester, pro: true);
      await tapNav(tester, 'Settings');
      await settle(tester);
      expect(find.text('SpendWise Pro'), findsOneWidget);
      expect(find.text('Manage your subscription'), findsOneWidget);
    });

    testWidgets(
      'accent themes are locked for free users and selectable for Pro',
      (tester) async {
        final h = await pumpApp(tester);
        await tapNav(tester, 'Settings');
        await settle(tester);
        await tester.tap(find.text('Ocean'));
        await settle(tester);
        expect(
          find.text('Free vs Pro'),
          findsOneWidget,
        ); // sent to the Pro screen instead of changing
        expect(h.container.read(settingsProvider).accent, 'emerald');
      },
    );

    testWidgets(
      'free users can still add unlimited records with billing unavailable',
      (tester) async {
        final h = await pumpApp(tester);
        await write(tester, () async {
          final ledger = h.container.read(ledgerServiceProvider);
          for (var i = 1; i <= 60; i++) {
            await ledger.add(
              TxnInput(
                type: TxnType.expense,
                amountMinor: i * 100,
                walletId: kDefaultWalletId,
                categoryId: 'cat_food',
                occurredAt: DateTime.now(),
              ),
            );
          }
        });
        expect(
          await write(
            tester,
            () =>
                h.container.read(transactionRepositoryProvider).getAllActive(),
          ),
          hasLength(60),
        );
      },
    );
  });

  group('privacy & data', () {
    testWidgets(
      'erase all data requires typing DELETE and then returns to a clean first run',
      (tester) async {
        final h = await pumpApp(tester, seed: seedBasics);
        await go(tester, Routes.privacy);
        await tester.tap(find.text('Erase all data'));
        await settle(tester);
        expect(find.text('Erase all data?'), findsOneWidget);
        final erase = find.widgetWithText(FilledButton, 'Erase everything');
        expect(tester.widget<FilledButton>(erase).onPressed, isNull);
        await tester.enterText(
          find.widgetWithText(TextField, 'Type DELETE to confirm'),
          'delete',
        );
        await tester.pump();
        expect(tester.widget<FilledButton>(erase).onPressed, isNull);
        await tester.enterText(
          find.widgetWithText(TextField, 'Type DELETE to confirm'),
          'DELETE',
        );
        await tester.pump();
        await tester.tap(erase);
        await settle(tester);
        await tester.pump(const Duration(seconds: 2));
        await settle(tester);
        expect(
          await write(
            tester,
            () =>
                h.container.read(transactionRepositoryProvider).getAllActive(),
          ),
          isEmpty,
        );
        expect(h.container.read(sharedPrefsProvider).getKeys(), isEmpty);
        expect(find.text('Track every rupee'), findsOneWidget);
      },
    );
  });

  group('layout at 2x text on a 360dp phone (no overflow)', () {
    Future<void> boot(WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(
        tester,
        seed: (c) async {
          await seedBasics(c);
          await c
              .read(budgetRepositoryProvider)
              .save(
                categoryId: 'cat_food',
                amountMinor: 100000,
                startMonth: startOfMonth(DateTime.now()),
              );
          await c
              .read(budgetRepositoryProvider)
              .save(
                amountMinor: 4000000,
                startMonth: startOfMonth(DateTime.now()),
              );
        },
        size: const Size(360, 3000),
      );
    }

    for (final tab in [
      'Home',
      'Transactions',
      'Budgets',
      'Reports',
      'Settings',
    ]) {
      testWidgets('tab $tab', (tester) async {
        await boot(tester);
        await tapNav(tester, tab);
      });
    }
    for (final route in [
      Routes.add,
      Routes.categories,
      Routes.wallets,
      Routes.bills,
      Routes.recurring,
      Routes.recurringEdit,
      Routes.budgetEdit,
      Routes.importExport,
      Routes.pro,
      Routes.subscription,
      Routes.privacy,
      Routes.about,
      Routes.deleted,
      Routes.sample,
    ]) {
      testWidgets('route $route', (tester) async {
        await boot(tester);
        await go(tester, route);
      });
    }
  });
}
