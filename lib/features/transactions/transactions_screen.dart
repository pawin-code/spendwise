import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/features/transactions/txn_tile.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        final list = ref.read(txnListProvider).value;
        final f = ref.read(txnFilterProvider);
        if (list != null && list.length >= f.limit) {
          ref.read(txnFilterProvider.notifier).loadMore();
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref
          .read(txnFilterProvider.notifier)
          .set(ref.read(txnFilterProvider).copyWith(query: q, limit: 50));
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(txnFilterProvider);
    final list = ref.watch(txnListProvider);
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onQuery,
                decoration: const InputDecoration(
                  hintText: 'Search note, payee or category',
                  border: InputBorder.none,
                  filled: false,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              )
            : const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                _onQuery('');
              }
            },
          ),
          IconButton(
            tooltip: 'Filter and sort',
            icon: Badge(
              isLabelVisible:
                  filter.hasFilters &&
                  (filter.type != null ||
                      filter.categoryId != null ||
                      filter.walletId != null ||
                      filter.from != null),
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => _showFilters(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (filter.hasFilters) _ActiveFilters(filter: filter),
          Expanded(
            child: AsyncBody(
              value: list,
              onRetry: () => ref.invalidate(txnListProvider),
              data: (items) {
                if (items.isEmpty) {
                  return filter.hasFilters
                      ? EmptyState(
                          icon: Icons.search_off,
                          title: 'No matching transactions',
                          message: 'Try removing a filter or searching for something else.',
                          actionLabel: 'Clear filters',
                          onAction: () {
                            _search.clear();
                            ref.read(txnFilterProvider.notifier).reset();
                          },
                        )
                      : EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No transactions yet',
                          message:
                              'Tap Add to record your first income or expense.',
                          actionLabel: 'Add transaction',
                          onAction: () => context.push(Routes.add),
                        );
                }
                return _GroupedList(
                  items: items,
                  controller: _scroll,
                  groupByDate:
                      filter.sort == TxnSort.dateDesc ||
                      filter.sort == TxnSort.dateAsc,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FilterSheet(),
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.filter});
  final TxnFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = categoryMap(
      ref.watch(allCategoriesProvider).value ?? const [],
    );
    final wallets = {
      for (final w in ref.watch(allWalletsProvider).value ?? const [])
        w.id: w.name,
    };
    final notifier = ref.read(txnFilterProvider.notifier);
    final chips = <Widget>[
      if (filter.type != null)
        InputChip(
          label: Text(filter.type!.name),
          onDeleted: () => notifier.set(filter.copyWith(type: null)),
        ),
      if (filter.categoryId != null)
        InputChip(
          label: Text(cats[filter.categoryId]?.name ?? 'Category'),
          onDeleted: () => notifier.set(filter.copyWith(categoryId: null)),
        ),
      if (filter.walletId != null)
        InputChip(
          label: Text(wallets[filter.walletId] ?? 'Wallet'),
          onDeleted: () => notifier.set(filter.copyWith(walletId: null)),
        ),
      if (filter.from != null || filter.toExclusive != null)
        InputChip(
          label: Text(
            '${filter.from == null ? '…' : formatDay(filter.from!)} – ${filter.toExclusive == null ? '…' : formatDay(filter.toExclusive!.subtract(const Duration(days: 1)))}',
          ),
          onDeleted: () =>
              notifier.set(filter.copyWith(from: null, toExclusive: null)),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final c in chips)
            Padding(padding: const EdgeInsets.only(right: 8), child: c),
        ],
      ),
    );
  }
}

class _GroupedList extends ConsumerWidget {
  const _GroupedList({
    required this.items,
    required this.controller,
    required this.groupByDate,
  });
  final List<TxnView> items;
  final ScrollController controller;
  final bool groupByDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = <Widget>[];
    DateTime? lastDay;
    for (final v in items) {
      final day = dateOnly(v.txn.occurredAt);
      if (groupByDate && (lastDay == null || lastDay != day)) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text(
              friendlyDay(day),
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        );
        lastDay = day;
      }
      children.add(
        Dismissible(
          key: ValueKey('dismiss-${v.txn.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          confirmDismiss: (_) => confirmDialog(
            context,
            title: 'Delete transaction?',
            message: 'It moves to Recently deleted for 30 days, where you can restore it.',
            confirmLabel: 'Delete',
            destructive: true,
          ),
          onDismissed: (_) => deleteWithUndo(context, ref, v.txn.id),
          child: TransactionTile(view: v, includeDate: !groupByDate),
        ),
      );
    }
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
      children: children,
    );
  }
}

/// Soft-deletes and offers an Undo that restores the record.
Future<void> deleteWithUndo(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final ledger = ref.read(ledgerServiceProvider);
  await ledger.delete(id);
  if (!context.mounted) return;
  showSnack(
    context,
    'Transaction deleted',
    actionLabel: 'Undo',
    onAction: () => ledger.undoDelete(id),
  );
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(txnFilterProvider);
    final n = ref.read(txnFilterProvider.notifier);
    final cats = ref.watch(allCategoriesProvider).value ?? const [];
    final wallets = ref.watch(allWalletsProvider).value ?? const [];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter & sort',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => n.set(TxnFilter(query: f.query)),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Type', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: f.type == null,
                  onSelected: (_) => n.set(f.copyWith(type: null)),
                ),
                for (final t in TxnType.values)
                  ChoiceChip(
                    label: Text(t.name[0].toUpperCase() + t.name.substring(1)),
                    selected: f.type == t,
                    onSelected: (_) => n.set(f.copyWith(type: t)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: f.categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All categories'),
                ),
                for (final c in cats)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => n.set(f.copyWith(categoryId: v)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: f.walletId,
              decoration: const InputDecoration(labelText: 'Wallet'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All wallets'),
                ),
                for (final w in wallets)
                  DropdownMenuItem<String?>(value: w.id, child: Text(w.name)),
              ],
              onChanged: (v) => n.set(f.copyWith(walletId: v)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(
                f.from == null && f.toExclusive == null
                    ? 'Any date'
                    : '${f.from == null ? '…' : formatDay(f.from!)} – ${f.toExclusive == null ? '…' : formatDay(f.toExclusive!.subtract(const Duration(days: 1)))}',
              ),
              onPressed: () async {
                final r = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDateRange: f.from == null || f.toExclusive == null
                      ? null
                      : DateTimeRange(
                          start: f.from!,
                          end: f.toExclusive!.subtract(const Duration(days: 1)),
                        ),
                );
                if (r != null) {
                  n.set(
                    f.copyWith(
                      from: dateOnly(r.start),
                      toExclusive: dateOnly(r.end).add(const Duration(days: 1)),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            Text('Sort by', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Newest'),
                  selected: f.sort == TxnSort.dateDesc,
                  onSelected: (_) => n.set(f.copyWith(sort: TxnSort.dateDesc)),
                ),
                ChoiceChip(
                  label: const Text('Oldest'),
                  selected: f.sort == TxnSort.dateAsc,
                  onSelected: (_) => n.set(f.copyWith(sort: TxnSort.dateAsc)),
                ),
                ChoiceChip(
                  label: const Text('Highest amount'),
                  selected: f.sort == TxnSort.amountDesc,
                  onSelected: (_) =>
                      n.set(f.copyWith(sort: TxnSort.amountDesc)),
                ),
                ChoiceChip(
                  label: const Text('Lowest amount'),
                  selected: f.sort == TxnSort.amountAsc,
                  onSelected: (_) => n.set(f.copyWith(sort: TxnSort.amountAsc)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
