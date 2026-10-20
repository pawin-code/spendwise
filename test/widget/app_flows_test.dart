import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/database/seed.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

import 'app_harness.dart';

Finder keypad(String k) => k == 'back'
    ? find.descendant(
        of: find.byType(AmountKeypad),
        matching: find.byIcon(Icons.backspace_outlined),
      )
    : find.descendant(of: find.byType(AmountKeypad), matching: find.text(k));

void main() {
  group('onboarding', () {
    testWidgets('walks through the pages, applies setup and lands on Home', (
      tester,
    ) async {
      final h = await pumpApp(
        tester,
        location: Routes.onboarding,
        onboardingDone: false,
      );
      expect(find.text('Track every rupee'), findsOneWidget);
      for (final title in [
        'Budgets and reminders',
        'Private by design',
        'Optional extras',
      ]) {
        await tester.tap(find.text('Next'));
        await settle(tester);
        expect(find.text(title), findsOneWidget);
      }
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.text('Quick setup'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly budget (optional)'),
        '25000',
      );
      await tester.tap(find.text('Get started'));
      await settle(tester);

      expect(find.text('Welcome to SpendWise'), findsOneWidget);
      expect(h.container.read(settingsProvider).onboardingDone, isTrue);
      expect(h.container.read(settingsProvider).currencyCode, 'INR');
      final budgets = await write(
        tester,
        () => h.container.read(budgetRepositoryProvider).getAll(),
      );
      expect(budgets.single.amountMinor, 2500000);
      expect(budgets.single.categoryId, isNull);
    });

    testWidgets('rejects an invalid budget instead of silently dropping it', (
      tester,
    ) async {
      await pumpApp(tester, location: Routes.onboarding, onboardingDone: false);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await settle(tester);
      }
      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly budget (optional)'),
        'abc',
      );
      await tester.tap(find.text('Get started'));
      await settle(tester);
      expect(find.textContaining('Enter a valid amount'), findsOneWidget);
      expect(find.text('Quick setup'), findsOneWidget);
    });

    testWidgets('can be skipped and does not insert any records', (
      tester,
    ) async {
      final h = await pumpApp(
        tester,
        location: Routes.onboarding,
        onboardingDone: false,
      );
      await tester.tap(find.text('Skip'));
      await settle(tester);
      expect(find.text('Welcome to SpendWise'), findsOneWidget);
      expect(h.container.read(settingsProvider).onboardingDone, isTrue);
      expect(
        await write(
          tester,
          () => h.container.read(transactionRepositoryProvider).getAllActive(),
        ),
        isEmpty,
      );
      expect(
        await write(
          tester,
          () => h.container.read(budgetRepositoryProvider).getAll(),
        ),
        isEmpty,
      );
    });

    testWidgets(
      'the sample walkthrough is clearly labelled and saves nothing',
      (tester) async {
        final h = await pumpApp(
          tester,
          location: Routes.onboarding,
          onboardingDone: false,
        );
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.text('Next'));
          await settle(tester);
        }
        await tester.tap(find.textContaining('sample walkthrough'));
        await settle(tester);
        expect(find.textContaining('Illustrative sample only'), findsOneWidget);
        expect(
          await write(
            tester,
            () =>
                h.container.read(transactionRepositoryProvider).getAllActive(),
          ),
          isEmpty,
        );
      },
    );

    testWidgets('returning users skip straight to Home', (tester) async {
      await pumpApp(tester, location: Routes.splash);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('Welcome to SpendWise'), findsOneWidget);
    });
  });

  group('dashboard', () {
    testWidgets('new users see a helpful empty state and no invented numbers', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Welcome to SpendWise'), findsOneWidget);
      expect(find.text('Add a transaction'), findsOneWidget);
      expect(find.text('Safe-to-Spend'), findsNothing);
      expect(find.text('₹0.00'), findsWidgets);
    });

    testWidgets(
      'shows real totals, categories and recent items from the database',
      (tester) async {
        await pumpApp(tester, seed: seedBasics);
        expect(find.text('Welcome to SpendWise'), findsNothing);
        expect(find.text('Safe-to-Spend'), findsOneWidget);
        expect(find.text('₹50,000'), findsWidgets); // income
        expect(find.text('₹2,034.50'), findsWidgets); // 1234.50 + 800 expenses
        expect(find.text('Recent transactions'), findsOneWidget);
      },
    );

    testWidgets(
      'updates immediately when a transaction is added and when it is deleted',
      (tester) async {
        final h = await pumpApp(tester, seed: seedBasics);
        final ledger = h.container.read(ledgerServiceProvider);
        final id = await write(
          tester,
          () => ledger.add(
            TxnInput(
              type: TxnType.expense,
              amountMinor: 500000,
              walletId: kDefaultWalletId,
              categoryId: 'cat_shopping',
              occurredAt: DateTime.now(),
            ),
          ),
        );
        expect(find.text('₹7,034.50'), findsWidgets);
        await write(tester, () => ledger.delete(id));
        expect(find.text('₹7,034.50'), findsNothing);
        expect(find.text('₹2,034.50'), findsWidgets);
      },
    );
  });

  group('add / edit transaction', () {
    testWidgets(
      'validates the amount, accepts keypad input and saves to the database',
      (tester) async {
        final h = await pumpApp(tester);
        await tester.tap(find.text('Add').first);
        await settle(tester);
        expect(find.text('Add transaction'), findsOneWidget);

        await tester.tap(find.text('Save'));
        await settle(tester);
        expect(find.text('Enter an amount greater than zero.'), findsOneWidget);

        await tester.tap(keypad('1'));
        await tester.tap(keypad('2'));
        await tester.tap(keypad('.'));
        await tester.tap(keypad('5'));
        await tester.pump();
        expect(find.text('₹12.5'), findsOneWidget);
        expect(find.text('Enter an amount greater than zero.'), findsNothing);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Food & groceries'));
        await tester.pump();
        await tester.enterText(
          find.widgetWithText(TextField, 'Merchant / payee (optional)'),
          'Corner Shop',
        );
        await tester.tap(find.text('Save'));
        await settle(tester);

        final rows = await write(
          tester,
          () => h.container.read(transactionRepositoryProvider).getAllActive(),
        );
        expect(rows.length, 1);
        expect(rows.single.amountMinor, 1250);
        expect(rows.single.type, TxnType.expense);
        expect(rows.single.categoryId, 'cat_food');
        expect(rows.single.payee, 'Corner Shop');
      },
    );

    testWidgets(
      'the keypad never allows more than two decimals or a second decimal point',
      (tester) async {
        await pumpApp(tester, location: '${Routes.add}?type=income');
        for (final k in ['1', '.', '2', '3', '4', '.']) {
          await tester.tap(keypad(k));
        }
        await tester.pump();
        expect(find.text('₹1.23'), findsOneWidget);
      },
    );

    testWidgets('transfers need two different wallets', (tester) async {
      final h = await pumpApp(tester, location: '${Routes.add}?type=transfer');
      await tester.tap(keypad('5'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(
        find.text('Choose two different wallets for a transfer.'),
        findsOneWidget,
      );
      expect(
        await write(
          tester,
          () => h.container.read(transactionRepositoryProvider).getAllActive(),
        ),
        isEmpty,
      );
    });

    testWidgets(
      'editing loads the saved values, saves changes and keeps one record',
      (tester) async {
        late String id;
        final h = await pumpApp(
          tester,
          seed: (c) async {
            id = await c
                .read(ledgerServiceProvider)
                .add(
                  TxnInput(
                    type: TxnType.expense,
                    amountMinor: 45000,
                    walletId: kDefaultWalletId,
                    categoryId: 'cat_food',
                    occurredAt: DateTime.now(),
                    note: 'old note',
                  ),
                );
          },
        );
        await go(tester, Routes.editTransaction(id));
        expect(find.text('Edit transaction'), findsOneWidget);
        expect(find.text('₹450'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'old note'), findsOneWidget);

        await tester.tap(keypad('back'));
        await tester.tap(keypad('9'));
        await tester.pump();
        await tester.tap(find.text('Save changes'));
        await settle(tester);

        final rows = await write(
          tester,
          () => h.container.read(transactionRepositoryProvider).getAllActive(),
        );
        expect(rows.length, 1);
        expect(rows.single.amountMinor, 45900);
        expect(rows.single.note, 'old note');
        expect(rows.single.categoryId, 'cat_food');
      },
    );
  });
}
