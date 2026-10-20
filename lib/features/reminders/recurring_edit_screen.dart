import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/router.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/recurring_repository.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

class RecurringEditScreen extends ConsumerStatefulWidget {
  const RecurringEditScreen({super.key, this.ruleId, this.startAsBill = false});
  final String? ruleId;
  final bool startAsBill;

  @override
  ConsumerState<RecurringEditScreen> createState() =>
      _RecurringEditScreenState();
}

class _RecurringEditScreenState extends ConsumerState<RecurringEditScreen> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _interval = TextEditingController(text: '1');
  final _note = TextEditingController();
  ReminderKind _kind = ReminderKind.other;
  CategoryType _type = CategoryType.expense;
  Frequency _frequency = Frequency.monthly;
  String? _categoryId;
  String? _walletId;
  DateTime _start = dateOnly(DateTime.now());
  DateTime? _end;
  bool _remind = true;
  int _remindDays = 1;
  bool _autoPost = false;
  String? _error;
  bool _busy = false;
  bool _loaded = false;
  RuleRow? _existing;

  bool get _isEdit => widget.ruleId != null;

  @override
  void initState() {
    super.initState();
    if (widget.startAsBill) _frequency = Frequency.once;
    if (_isEdit) {
      _load();
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final r = await ref
        .read(recurringRepositoryProvider)
        .getById(widget.ruleId!);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _existing = r;
      if (r != null) {
        _title.text = r.title;
        _amount.text = minorToPlain(r.amountMinor)
            .replaceAll(RegExp(r'\.00$'), '');
        _interval.text = '${r.intervalCount}';
        _note.text = r.note;
        _kind = r.kind;
        _type = r.type;
        _frequency = r.frequency;
        _categoryId = r.categoryId;
        _walletId = r.walletId;
        _start = r.startDate;
        _end = r.endDate;
        _remind = r.remind;
        _remindDays = r.remindDaysBefore;
        _autoPost = r.autoPost;
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _interval.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmountToMinor(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    final wallets = ref.read(walletsProvider).value ?? const [];
    final walletId =
        _walletId ?? (wallets.isNotEmpty ? wallets.first.id : null);
    if (walletId == null) {
      setState(() => _error = 'Add a wallet first.');
      return;
    }
    final interval = int.tryParse(_interval.text.trim()) ?? 0;
    setState(() {
      _busy = true;
      _error = null;
    });
    final input = RuleInput(
      title: _title.text,
      kind: _kind,
      type: _type,
      amountMinor: amount,
      walletId: walletId,
      categoryId: _categoryId,
      frequency: _frequency,
      intervalCount: _frequency == Frequency.once ? 1 : interval,
      startDate: _start,
      endDate: _frequency == Frequency.once ? null : _end,
      autoPost: _autoPost && ref.read(isProProvider),
      remind: _remind,
      remindDaysBefore: _remindDays,
      note: _note.text,
    );
    try {
      final repo = ref.read(recurringRepositoryProvider);
      if (_isEdit) {
        await repo.update(widget.ruleId!, input);
      } else {
        await repo.add(input);
      }
      if (!mounted) return;
      showSnack(context, 'Saved');
      context.pop();
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete "${_existing!.title}"?',
      message: 'Transactions already recorded from it stay in your history.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(recurringRepositoryProvider).delete(widget.ruleId!);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_isEdit && _existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reminder')),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Not found',
          message: 'This item no longer exists.',
        ),
      );
    }
    final cur = ref.watch(currencyProvider);
    final isPro = ref.watch(isProProvider);
    final wallets = ref.watch(walletsProvider).value ?? const <WalletRow>[];
    final cats = (ref.watch(categoriesProvider).value ?? const <CategoryRow>[])
        .where((c) => c.type == _type)
        .toList();
    final activeWallet =
        _walletId ?? (wallets.isNotEmpty ? wallets.first.id : null);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit
              ? 'Edit'
              : (widget.startAsBill
                    ? 'New bill reminder'
                    : 'New recurring item'),
        ),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          TextField(
            controller: _title,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. House rent',
            ),
          ),
          DropdownButtonFormField<ReminderKind>(
            isExpanded: true,
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Kind'),
            items: [
              for (final k in ReminderKind.values)
                DropdownMenuItem(value: k, child: Text(k.label)),
            ],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 12),
          SegmentedButton<CategoryType>(
            segments: const [
              ButtonSegment(
                value: CategoryType.expense,
                label: Text('Expense'),
              ),
              ButtonSegment(value: CategoryType.income, label: Text('Income')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '${cur.symbol} ',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            key: ValueKey('cat-$_type'),
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final c in cats)
                DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey('wallet-${wallets.length}'),
            initialValue: wallets.any((w) => w.id == activeWallet)
                ? activeWallet
                : null,
            decoration: const InputDecoration(labelText: 'Wallet'),
            items: [
              for (final w in wallets)
                DropdownMenuItem(value: w.id, child: Text(w.name)),
            ],
            onChanged: (v) => setState(() => _walletId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Frequency>(
            isExpanded: true,
            initialValue: _frequency,
            decoration: const InputDecoration(labelText: 'Repeats'),
            items: [
              for (final f in Frequency.values)
                DropdownMenuItem(value: f, child: Text(f.label)),
            ],
            onChanged: (v) => setState(() => _frequency = v ?? _frequency),
          ),
          if (_frequency != Frequency.once) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _interval,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Every',
                helperText:
                    'Every N ${switch (_frequency) {
                      Frequency.daily => 'days',
                      Frequency.weekly => 'weeks',
                      Frequency.monthly => 'months',
                      Frequency.yearly => 'years',
                      Frequency.once => '',
                    }}',
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(
              _frequency == Frequency.once
                  ? 'Due on ${formatDay(_start)}'
                  : 'Starts ${formatDay(_start)}',
            ),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _start,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _start = dateOnly(d));
            },
          ),
          if (_frequency != Frequency.once) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_busy),
                    label: Text(
                      _end == null ? 'No end date' : 'Ends ${formatDay(_end!)}',
                    ),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _end ?? _start,
                        firstDate: _start,
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _end = dateOnly(d));
                    },
                  ),
                ),
                if (_end != null)
                  IconButton(
                    tooltip: 'Clear end date',
                    onPressed: () => setState(() => _end = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind me'),
            subtitle: Text(
              _remind
                  ? (_remindDays == 0
                        ? 'On the due date'
                        : '$_remindDays day${_remindDays == 1 ? '' : 's'} before')
                  : 'No notification',
            ),
            value: _remind,
            onChanged: (v) => setState(() => _remind = v),
          ),
          if (_remind)
            Slider(
              value: _remindDays.toDouble(),
              min: 0,
              max: 7,
              divisions: 7,
              label: _remindDays == 0 ? 'Due day' : '$_remindDays d',
              onChanged: (v) => setState(() => _remindDays = v.round()),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                const Flexible(child: Text('Record automatically')),
                const SizedBox(width: 8),
                if (!isPro) const ProBadge(),
              ],
            ),
            subtitle: const Text(
              'Pro: post this item to your transactions on its due date without asking. Off by default.',
            ),
            value: _autoPost && isPro,
            onChanged: (v) {
              if (!isPro) {
                context.push(Routes.pro);
                return;
              }
              setState(() => _autoPost = v);
            },
          ),
          TextField(
            controller: _note,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_isEdit ? 'Save changes' : 'Save'),
          ),
        ],
      ),
    );
  }
}
