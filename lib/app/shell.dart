import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/router.dart';

/// Bottom navigation + the prominent "add transaction" button.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Transactions',
    ),
    NavigationDestination(
      icon: Icon(Icons.pie_chart_outline),
      selectedIcon: Icon(Icons.pie_chart),
      label: 'Budgets',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'Reports',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final showFab = shell.currentIndex != 4;
    return Scaffold(
      body: shell,
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              heroTag: 'add-transaction',
              onPressed: () => context.push(Routes.add),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
              tooltip: 'Add transaction',
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        destinations: _destinations,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}
