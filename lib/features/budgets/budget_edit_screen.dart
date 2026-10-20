import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

class BudgetEditScreen extends ConsumerStatefulWidget {
  const BudgetEditScreen({super.key, this.budgetId});
  final String? budgetId;

  @override
  ConsumerState<BudgetEditScreen> createState() => _BudgetEditScreenState();
}

class _BudgetEditScreenState extends ConsumerState<BudgetEditScreen> {
  final _amount = TextEditingController();
  String? _categoryId;
  DateTime _start = startOfMonth(DateTime.now());
  DateTime? _end;
  double _warn = 80;
  bool _rollover = false;
  String? _error;
  bool _busy = false;
  bool _loaded = false;
  BudgetRow? _existing;

  bool get _isEdit => widget.budgetId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final b = (await ref.read(budgetRepositoryProvider).getAll())
        .where((b) => b.id == widget.budgetId)
        .firstOrNull;
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _existing = b;
      if (b != null) {
        _amount.text = minorToPlain(b.amountMinor)
            .replaceAll(RegExp(r'\.00$'), '');
        _categoryId = b.categoryId;
        _start = startOfMonth(b.startMonth);
        _end = b.endMonth;
        _warn = b.warnPercent.toDouble();
        _rollover = b.rollover;
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickMonth({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : (_end ?? _start),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Pick any day in the month',
    );
    if (picked == null) return;
    setState(
      () =>
          isStart ? _start = startOfMonth(picked) : _end = startOfMonth(picked),
    );
  }

  Future<void> _save() async {
    final minor = parseAmountToMinor(_amount.text);
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter a budget amount greater than zero.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(budgetRepositoryProvider)
          .save(
            id: widget.budgetId,
            categoryId: _categoryId,
            amountMinor: minor,
            startMonth: _start,
            endMonth: _end,
            warnPercent: _warn.round(),
            rollover: _rollover,
          );
      await ref.read(ledgerServiceProvider).refreshAlerts(DateTime.now());
      if (!mounted) return;
      showSnack(context, 'Budget saved');
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
      title: 'Delete budget?',
      message: 'Your transactions are not affected. Past budget history for this scope will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(budgetRepositoryProvider).delete(widget.budgetId!);
    if (!mounted) return;
    showSnack(context, 'Budget deleted');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cur = ref.watch(currencyProvider);
    final cats = (ref.watch(categoriesProvider).value ?? const [])
        .where((c) => c.type == CategoryType.expense)
        .toList();
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_isEdit && _existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Budget')),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Not found',
          message: 'This budget no longer exists.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit budget' : 'New budget'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete budget',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Applies to'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Overall monthly budget'),
              ),
              for (final c in cats)
                DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
            ],
            onChanged: _isEdit ? null : (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monthly amount',
              prefixText: '${cur.symbol} ',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickMonth(isStart: true),
                  icon: const Icon(Icons.event),
                  label: Text('From ${formatMonth(_start)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ongoing'),
            subtitle: Text(
              _end == null
                  ? 'Repeats every month until you end it'
                  : 'Ends after ${formatMonth(_end!)}',
            ),
            value: _end == null,
            onChanged: (v) => setState(() => _end = v ? null : _start),
          ),
          if (_end != null)
            OutlinedButton.icon(
              onPressed: () => _pickMonth(isStart: false),
              icon: const Icon(Icons.event_busy),
              label: Text('Until ${formatMonth(_end!)}'),
            ),
          const SizedBox(height: 16),
          Text(
            'Warn me at ${_warn.round()}% (and again at 100%)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            value: _warn,
            min: 50,
            max: 95,
            divisions: 9,
            label: '${_warn.round()}%',
            onChanged: (v) => setState(() => _warn = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Roll over unspent money'),
            subtitle: const Text(
              'Off by default. When on, whatever you do not spend is added to next month\'s limit.',
            ),
            value: _rollover,
            onChanged: (v) => setState(() => _rollover = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_isEdit ? 'Save changes' : 'Create budget'),
          ),
        ],
      ),
    );
  }
}
