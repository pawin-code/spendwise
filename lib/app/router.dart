import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/shell.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/features/budgets/budget_edit_screen.dart';
import 'package:spendwise/features/budgets/budgets_screen.dart';
import 'package:spendwise/features/categories/categories_screen.dart';
import 'package:spendwise/features/dashboard/home_screen.dart';
import 'package:spendwise/features/import_export/import_export_screen.dart';
import 'package:spendwise/features/onboarding/onboarding_screen.dart';
import 'package:spendwise/features/onboarding/sample_walkthrough_screen.dart';
import 'package:spendwise/features/onboarding/splash_screen.dart';
import 'package:spendwise/features/reminders/bills_screen.dart';
import 'package:spendwise/features/reminders/recurring_edit_screen.dart';
import 'package:spendwise/features/reminders/recurring_screen.dart';
import 'package:spendwise/features/reports/reports_screen.dart';
import 'package:spendwise/features/settings/about_screen.dart';
import 'package:spendwise/features/settings/legal_screen.dart';
import 'package:spendwise/features/settings/privacy_screen.dart';
import 'package:spendwise/features/settings/settings_screen.dart';
import 'package:spendwise/features/subscriptions/pro_screen.dart';
import 'package:spendwise/features/subscriptions/subscription_management_screen.dart';
import 'package:spendwise/features/transactions/deleted_transactions_screen.dart';
import 'package:spendwise/features/transactions/transaction_detail_screen.dart';
import 'package:spendwise/features/transactions/transaction_form_screen.dart';
import 'package:spendwise/features/transactions/transactions_screen.dart';
import 'package:spendwise/features/wallets/wallets_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

abstract class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const sample = '/sample';
  static const home = '/home';
  static const transactions = '/transactions';
  static const budgets = '/budgets';
  static const reports = '/reports';
  static const settings = '/settings';
  static const add = '/add';
  static String transaction(String id) => '/transaction/$id';
  static String editTransaction(String id) => '/transaction/$id/edit';
  static const deleted = '/deleted';
  static const categories = '/categories';
  static const wallets = '/wallets';
  static const budgetEdit = '/budget-edit';
  static const bills = '/bills';
  static const recurring = '/recurring';
  static const recurringEdit = '/recurring-edit';
  static const importExport = '/import-export';
  static const pro = '/pro';
  static const subscription = '/subscription';
  static const privacy = '/privacy';
  static const about = '/about';
  static String legal(String kind) => '/legal/$kind';
}

GoRouter buildRouter({String initialLocation = Routes.splash}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.sample,
        builder: (_, _) => const SampleWalkthroughScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.transactions,
                builder: (_, _) => const TransactionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.budgets,
                builder: (_, _) => const BudgetsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.reports,
                builder: (_, _) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.add,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) {
          final t = state.uri.queryParameters['type'];
          final type =
              TxnType.values.where((e) => e.name == t).firstOrNull ??
              TxnType.expense;
          return TransactionFormScreen(initialType: type);
        },
      ),
      GoRoute(
        path: '/transaction/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) =>
            TransactionDetailScreen(id: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            parentNavigatorKey: rootNavigatorKey,
            builder: (_, state) =>
                TransactionFormScreen(editId: state.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: Routes.deleted,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const DeletedTransactionsScreen(),
      ),
      GoRoute(
        path: Routes.categories,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const CategoriesScreen(),
      ),
      GoRoute(
        path: Routes.wallets,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const WalletsScreen(),
      ),
      GoRoute(
        path: Routes.budgetEdit,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) =>
            BudgetEditScreen(budgetId: state.uri.queryParameters['id']),
      ),
      GoRoute(
        path: Routes.bills,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const BillsScreen(),
      ),
      GoRoute(
        path: Routes.recurring,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const RecurringScreen(),
      ),
      GoRoute(
        path: Routes.recurringEdit,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => RecurringEditScreen(
          ruleId: state.uri.queryParameters['id'],
          startAsBill: state.uri.queryParameters['bill'] == '1',
        ),
      ),
      GoRoute(
        path: Routes.importExport,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const ImportExportScreen(),
      ),
      GoRoute(
        path: Routes.pro,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const ProScreen(),
      ),
      GoRoute(
        path: Routes.subscription,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const SubscriptionManagementScreen(),
      ),
      GoRoute(
        path: Routes.privacy,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PrivacyScreen(),
      ),
      GoRoute(
        path: Routes.about,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const AboutScreen(),
      ),
      GoRoute(
        path: '/legal/:kind',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => LegalScreen(kind: state.pathParameters['kind']!),
      ),
    ],
  );
}
