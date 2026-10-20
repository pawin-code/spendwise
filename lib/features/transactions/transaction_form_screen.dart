import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

/// Category ids ordered by how often they were used recently, so suggestions
/// float to the front of the picker.
final recentCategoryIdsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final repo = ref.watch(transactionRepositoryProvider);
  final rows = await repo.getRange(
    DateTime.now().subtract(const Duration(days: 120)),
    DateTime.now().add(const Duration(days: 1)),
  );
  final counts = <String, int>{};
  for (final r in rows) {
    final c = r.categoryId;
    if (c != null) counts[c] = (counts[c] ?? 0) + 1;
  }
  final ids = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return ids;
});

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.editId,
    this.initialType = TxnType.expense,
  });
  final String? editId;
  final TxnType initialType;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  late TxnType _type = widget.initialType;
  String _amount = '';
  String? _categoryId;
  String? _walletId;
  String? _toWalletId;
  DateTime _date = DateTime.now();
  TimeOfDay? _time;
  final _payee = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _saving = false;
  bool _loading = false;
  TxnRow? _existing;

  bool get _isEdit => widget.editId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final t = await ref
        .read(transactionRepositoryProvider)
        .getById(widget.editId!);
    if (!mounted) return;
    if (t == null) {
      setState(() {
        _loading = false;
        _error = 'This transaction no longer exists.';
      });
      return;
    }
    setState(() {
      _existing = t;
      _type = t.type;
      _amount = minorToPlain(t.amountMinor).replaceAll(RegExp(r'\.00$'), '');
      _categoryId = t.categoryId;
      _walletId = t.walletId;
      _toWalletId = t.toWalletId;
      _date = t.occurredAt;
      _time = t.hasTime ? TimeOfDay.fromDateTime(t.occurredAt) : null;
      _payee.text = t.payee;
      _note.text = t.note;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _amountMinor => parseAmountToMinor(
    _amount.endsWith('.') ? _amount.substring(0, _amount.length - 1) : _amount,
  );

  Future<void> _save() async {
    final minor = _amountMinor;
    if (minor == null || minor <= 0) {
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
    if (_type == TxnType.transfer &&
        (_toWalletId == null || _toWalletId == walletId)) {
      setState(() => _error = 'Choose two different wallets for a transfer.');
      return;
    }
    final when = _time == null
        ? DateTime(_date.year, _date.month, _date.day)
        : DateTime(
            _date.year,
            _date.month,
            _date.day,
            _time!.hour,
            _time!.minute,
          );
    final input = TxnInput(
      type: _type,
      amountMinor: minor,
      walletId: walletId,
      toWalletId: _type == TxnType.transfer ? _toWalletId : null,
      categoryId: _type == TxnType.transfer ? null : _categoryId,
      occurredAt: when,
      hasTime: _time != null,
      note: _note.text,
      payee: _payee.text,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ledger = ref.read(ledgerServiceProvider);
      if (_isEdit) {
        await ledger.update(widget.editId!, input);
      } else {
        await ledger.add(input);
      }
      if (!mounted) return;
      showSnack(context, _isEdit ? 'Transaction updated' : 'Transaction saved');
      context.pop();
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(
        () => _error = 'Could not save. Your input is kept — please try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletsProvider).value ?? const <WalletRow>[];
    final categories =
        ref.watch(categoriesProvider).value ?? const <CategoryRow>[];
    final recent =
        ref.watch(recentCategoryIdsProvider).value ?? const <String>[];
    final cur = ref.watch(currencyProvider);
    final kind = _type == TxnType.income
        ? CategoryType.income
        : CategoryType.expense;
    final shown = categories.where((c) => c.type == kind).toList()
      ..sort((a, b) {
        final ia = recent.indexOf(a.id), ib = recent.indexOf(b.id);
        final ra = ia < 0 ? 999 : ia, rb = ib < 0 ? 999 : ib;
        return ra != rb ? ra.compareTo(rb) : a.sortOrder.compareTo(b.sortOrder);
      });
    final accent = switch (_type) {
      TxnType.income => context.finance.income,
      TxnType.expense => context.finance.expense,
      TxnType.transfer => Theme.of(context).colorScheme.secondary,
    };
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit transaction')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_isEdit && _existing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit transaction')),
        body: ErrorState(message: _error ?? 'Not found.'),
      );
    }
    final activeWalletId =
        _walletId ?? (wallets.isNotEmpty ? wallets.first.id : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit transaction' : 'Add transaction'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  SegmentedButton<TxnType>(
                    segments: const [
                      ButtonSegment(
                        value: TxnType.expense,
                        label: Text('Expense'),
                        icon: Icon(Icons.north_east),
                      ),
                      ButtonSegment(
                        value: TxnType.income,
                        label: Text('Income'),
                        icon: Icon(Icons.south_west),
                      ),
                      ButtonSegment(
                        value: TxnType.transfer,
                        label: Text('Transfer'),
                        icon: Icon(Icons.swap_horiz),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged:
                        _isEdit &&
                            _existing != null &&
                            (_existing!.type == TxnType.transfer ||
                                _type == TxnType.transfer)
                        ? null
                        : (s) => setState(() {
                            _type = s.first;
                            _categoryId = null;
                          }),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    label: 'Amount',
                    value: _amount.isEmpty ? 'empty' : '${cur.symbol}$_amount',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${cur.symbol}${_amount.isEmpty ? '0' : _amount}',
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        key: const Key('form-error'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  AmountKeypad(
                    onKey: (k) => setState(() {
                      _amount = AmountKeypad.apply(_amount, k);
                      _error = null;
                    }),
                    onClear: () => setState(() => _amount = ''),
                  ),
                  const SizedBox(height: 16),
                  if (_type != TxnType.transfer) ...[
                    Text(
                      'Category',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in shown)
                          ChoiceChip(
                            avatar: Icon(
                              Icons.circle,
                              size: 12,
                              color: Color(c.colorValue),
                            ),
                            label: Text(c.name),
                            selected: _categoryId == c.id,
                            onSelected: (v) =>
                                setState(() => _categoryId = v ? c.id : null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey('wallet-$activeWalletId-${wallets.length}'),
                    initialValue: wallets.any((w) => w.id == activeWalletId)
                        ? activeWalletId
                        : null,
                    decoration: InputDecoration(
                      labelText: _type == TxnType.transfer
                          ? 'From wallet'
                          : 'Wallet',
                    ),
                    items: [
                      for (final w in wallets)
                        DropdownMenuItem(value: w.id, child: Text(w.name)),
                    ],
                    onChanged: (v) => setState(() => _walletId = v),
                  ),
                  if (_type == TxnType.transfer) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey('to-$_toWalletId-${wallets.length}'),
                      initialValue: wallets.any((w) => w.id == _toWalletId)
                          ? _toWalletId
                          : null,
                      decoration: const InputDecoration(labelText: 'To wallet'),
                      items: [
                        for (final w in wallets.where(
                          (w) => w.id != activeWalletId,
                        ))
                          DropdownMenuItem(value: w.id, child: Text(w.name)),
                      ],
                      onChanged: (v) => setState(() => _toWalletId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(friendlyDay(_date)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) setState(() => _date = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(
                            _time == null ? 'Add time' : _time!.format(context),
                          ),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: _time ?? TimeOfDay.now(),
                            );
                            if (picked != null) setState(() => _time = picked);
                          },
                        ),
                      ),
                      if (_time != null)
                        IconButton(
                          tooltip: 'Remove time',
                          onPressed: () => setState(() => _time = null),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  if (_type != TxnType.transfer) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _payee,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Merchant / payee (optional)',
                        counterText: '',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isEdit ? 'Save changes' : 'Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
