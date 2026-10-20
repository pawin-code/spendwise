import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/core/widgets/icons.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

final _monthTotalsProvider = StreamProvider.autoDispose<Map<String, int>>((
  ref,
) {
  final m = ref.watch(selectedMonthProvider);
  return ref
      .watch(categoryRepositoryProvider)
      .watchTotals(startOfMonth(m), startOfNextMonth(m));
});

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Categories'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Expense'),
                  Tab(text: 'Income'),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              heroTag: 'add-category',
              onPressed: () => showCategorySheet(
                context,
                type: tabs.index == 0
                    ? CategoryType.expense
                    : CategoryType.income,
              ),
              icon: const Icon(Icons.add),
              label: const Text('New category'),
            ),
            body: const TabBarView(
              children: [
                _CategoryList(type: CategoryType.expense),
                _CategoryList(type: CategoryType.income),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.type});
  final CategoryType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allCategoriesProvider);
    final totals = ref.watch(_monthTotalsProvider).value ?? const {};
    final month = ref.watch(selectedMonthProvider);
    return AsyncBody(
      value: all,
      data: (list) {
        final mine = list.where((c) => c.type == type).toList();
        final active = mine.where((c) => !c.archived).toList();
        final archived = mine.where((c) => c.archived).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Totals for ${formatMonth(month)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final c in active) _tile(context, ref, c, totals[c.id] ?? 0),
            if (archived.isNotEmpty) ...[
              const SectionHeader('Archived'),
              for (final c in archived)
                _tile(context, ref, c, totals[c.id] ?? 0),
            ],
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, CategoryRow c, int total) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => showCategorySheet(context, existing: c, type: type),
        leading: CategoryAvatar(iconKey: c.iconKey, color: c.colorValue),
        title: Text(c.name),
        subtitle: c.archived
            ? const Text('Archived — hidden from pickers')
            : null,
        trailing: MoneyText(
          total,
          hideZeroFraction: true,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }
}

Future<void> showCategorySheet(
  BuildContext context, {
  CategoryRow? existing,
  required CategoryType type,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _CategorySheet(existing: existing, type: type),
    ),
  );
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({this.existing, required this.type});
  final CategoryRow? existing;
  final CategoryType type;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late String _icon = widget.existing?.iconKey ?? 'category';
  late int _color = widget.existing?.colorValue ?? kPaletteColors.first;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(categoryRepositoryProvider);
    try {
      if (widget.existing == null) {
        await repo.add(
          name: _name.text,
          type: widget.type,
          iconKey: _icon,
          colorValue: _color,
        );
      } else {
        await repo.update(
          widget.existing!.id,
          name: _name.text,
          iconKey: _icon,
          colorValue: _color,
        );
      }
      if (mounted) Navigator.pop(context);
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleArchive() async {
    final c = widget.existing!;
    final used = await ref.read(categoryRepositoryProvider).usageCount(c.id);
    if (!mounted) return;
    if (!c.archived) {
      final ok = await confirmDialog(
        context,
        title: 'Archive "${c.name}"?',
        message: used > 0
            ? 'It will be hidden from pickers. $used existing transaction${used == 1 ? '' : 's'} keep this category and your totals do not change.'
            : 'It will be hidden from pickers. You can restore it any time.',
        confirmLabel: 'Archive',
      );
      if (!ok) return;
    }
    await ref.read(categoryRepositoryProvider).setArchived(c.id, !c.archived);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEdit ? 'Edit category' : 'New ${widget.type.name} category',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
            ),
            const SizedBox(height: 8),
            Text('Icon', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in kCategoryIcons.entries)
                  Semantics(
                    button: true,
                    selected: _icon == e.key,
                    label: 'Icon ${e.key.replaceAll('_', ' ')}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _icon = e.key),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _icon == e.key
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: _icon == e.key ? 2 : 1,
                          ),
                        ),
                        child: Icon(e.value, color: Color(_color)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Color', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in kPaletteColors)
                  Semantics(
                    button: true,
                    selected: _color == c,
                    label: 'Color option',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                        ),
                        child: _color == c
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (isEdit)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _toggleArchive,
                      child: Text(
                        widget.existing!.archived ? 'Restore' : 'Archive',
                      ),
                    ),
                  ),
                if (isEdit) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
