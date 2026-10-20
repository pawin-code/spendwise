// End-to-end workflow test. Run on an emulator or device:
//   flutter test integration_test/app_test.dart -d <deviceId>
// It uses the real on-disk database and real SharedPreferences, and "restarts"
// the app by tearing down the widget tree and database and reopening the same file.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/app/app.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/features/transactions/transaction_form_screen.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 20),
  );
  await Future<void>.delayed(const Duration(milliseconds: 150));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 20),
  );
}

Future<void> typeAmount(WidgetTester tester, String amount) async {
  for (final ch in amount.split('')) {
    await tester.tap(
      find.descendant(of: find.byType(AmountKeypad), matching: find.text(ch)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> launch(WidgetTester tester, File dbFile) async {
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.file(dbFile);
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const SpendWiseApp(),
    ),
  );
  await settle(tester);
}

Future<void> shutdown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first run -> onboarding -> add income and expense -> budget -> edit/delete -> restart -> export',
    (tester) async {
      SharedPreferences.setMockInitialValues(
        {},
      ); // clean first-run state; real store is used afterwards
      final dir = await getTemporaryDirectory();
      final dbFile = File(
        p.join(
          dir.path,
          'spendwise_it_${DateTime.now().microsecondsSinceEpoch}.sqlite',
        ),
      );

      // 1-2. Launch and complete onboarding with a monthly budget.
      await launch(tester, dbFile);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('Track every rupee'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await settle(tester);
      }
      await tester.enterText(
        find.widgetWithText(TextField, 'Monthly budget (optional)'),
        '20000',
      );
      await tester.tap(find.text('Get started'));
      await settle(tester);
      expect(find.text('Welcome to SpendWise'), findsOneWidget);

      // 3. Add income of 50,000.
      await tester.tap(find.byKey(const Key('quick-income')));
      await settle(tester);
      await typeAmount(tester, '50000');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Salary'));
      await tester.tap(find.text('Save'));
      await settle(tester);

      // 4. Add an expense of 1,234.50 (Food).
      await tester.tap(find.byTooltip('Add transaction'));
      await settle(tester);
      await typeAmount(tester, '1234.50');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Food & groceries'));
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Merchant / payee (optional)'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(TransactionFormScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Merchant / payee (optional)'),
        'Fresh Mart',
      );
      // The on-screen keyboard resizes the form; wait for the layout to settle.
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);

      // 5-6. Dashboard reflects real totals; budget is 20,000 - 1,234.50.
      expect(find.text('₹50,000'), findsWidgets);
      expect(find.text('₹1,234.50'), findsWidgets);
      expect(find.text('₹18,765.50'), findsWidgets);
      expect(find.text('Safe-to-Spend'), findsOneWidget);

      // 7. Edit the expense to 1,500, then delete a second one and undo/confirm.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Transactions'),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Fresh Mart', skipOffstage: false).first);
      await settle(tester);
      await tester.tap(find.byTooltip('Edit'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AmountKeypad),
          matching: find.byIcon(Icons.backspace_outlined),
        ),
      );
      await tester.pump();
      await tester.longPress(
        find.descendant(
          of: find.byType(AmountKeypad),
          matching: find.byIcon(Icons.backspace_outlined),
        ),
      );
      await tester.pump();
      await typeAmount(tester, '1500');
      await tester.tap(find.text('Save changes'));
      await settle(tester);
      expect(find.text('₹1,500.00'), findsWidgets);

      await tester.tap(find.byTooltip('Delete'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Home'),
        ),
      );
      await settle(tester);
      expect(find.text('₹1,500'), findsNothing);

      // Undo from the "Recently deleted" screen so the expense exists again before the restart.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NavigationBar)),
      );
      final deleted = await container
          .read(transactionRepositoryProvider)
          .watchDeleted()
          .first;
      expect(deleted.length, 1);
      await container.read(ledgerServiceProvider).undoDelete(deleted.single.id);
      await settle(tester);
      expect(find.text('₹1,500'), findsWidgets);

      // 8. Restart: tear everything down and reopen the same database file.
      await shutdown(tester);
      await launch(tester, dbFile);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(
        find.text('Track every rupee'),
        findsNothing,
        reason: 'onboarding must not repeat',
      );
      expect(find.text('₹50,000'), findsWidgets);
      expect(find.text('₹1,500'), findsWidgets);
      expect(find.text('Safe-to-Spend'), findsOneWidget);

      // 9. Export: CSV produced from the persisted records.
      final c2 = ProviderScope.containerOf(
        tester.element(find.byType(NavigationBar)),
      );
      final views = await c2
          .read(transactionRepositoryProvider)
          .watchViews(const TxnFilter(limit: 100))
          .first;
      final csv = c2.read(csvServiceProvider).exportTransactions(views);
      expect(csv, contains('date,time,type,amount'));
      expect(csv, contains('50000.00'));
      expect(csv, contains('1500.00'));
      expect(csv, contains('Fresh Mart'));

      // 10. Billing: with no configured store products the Pro screen degrades gracefully.
      await tester.tap(find.byTooltip('SpendWise Pro'));
      await settle(tester);
      expect(find.text('Free vs Pro'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(find.text('Safe-to-Spend'), findsOneWidget);
      expect(
        await c2.read(transactionRepositoryProvider).getAllActive(),
        hasLength(2),
      );
      expect(
        (await c2.read(transactionRepositoryProvider).getAllActive()).map(
          (t) => t.type,
        ),
        containsAll([TxnType.income, TxnType.expense]),
      );
    },
  );
}
