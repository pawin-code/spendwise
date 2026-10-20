import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/core/widgets/icons.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';

class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(allWalletsProvider);
    final balances = ref.watch(balancesProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Wallets & accounts')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-wallet',
        onPressed: () => showWalletSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New wallet'),
      ),
      body: AsyncBody(
        value: wallets,
        data: (list) {
          final total = list.fold<int>(
            0,
            (a, w) => a + (balances[w.id] ?? w.openingBalanceMinor),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
            children: [
              AppCard(
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Combined balance',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Flexible(
                      child: MoneyText(
                        total,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  'Wallets are records you maintain yourself. SpendWise does not connect to your bank or payment apps, so balances reflect only what you enter.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              for (final w in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => showWalletSheet(context, existing: w),
                    leading: CircleAvatar(
                      backgroundColor: Color(w.colorValue)
                          .withValues(alpha: 0.16),
                      child: Icon(switch (w.kind) {
                        WalletKind.cash => Icons.payments_outlined,
                        WalletKind.bank => Icons.account_balance_outlined,
                        WalletKind.digital => Icons.phone_android,
                      }, color: Color(w.colorValue)),
                    ),
                    title: Text(w.name),
                    subtitle: Text(
                      w.archived ? 'Archived · ${w.kind.label}' : w.kind.label,
                    ),
                    trailing: MoneyText(
                      balances[w.id] ?? w.openingBalanceMinor,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> showWalletSheet(BuildContext context, {WalletRow? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _WalletSheet(existing: existing),
    ),
  );
}

class _WalletSheet extends ConsumerStatefulWidget {
  const _WalletSheet({this.existing});
  final WalletRow? existing;

  @override
  ConsumerState<_WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends ConsumerState<_WalletSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _opening = TextEditingController(
    text: widget.existing == null || widget.existing!.openingBalanceMinor == 0
        ? ''
        : minorToPlain(widget.existing!.openingBalanceMinor),
  );
  late WalletKind _kind = widget.existing?.kind ?? WalletKind.bank;
  late int _color = widget.existing?.colorValue ?? kPaletteColors[1];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var opening = 0;
    final text = _opening.text.trim();
    if (text.isNotEmpty) {
      final negative = text.startsWith('-');
      final parsed = parseAmountToMinor(negative ? text.substring(1) : text);
      if (parsed == null) {
        setState(
          () => _error = 'Enter a valid opening balance, e.g. 1500 or 1500.50',
        );
        return;
      }
      opening = negative ? -parsed : parsed;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(walletRepositoryProvider);
    try {
      if (widget.existing == null) {
        await repo.add(
          name: _name.text,
          kind: _kind,
          openingBalanceMinor: opening,
          colorValue: _color,
        );
      } else {
        await repo.update(
          widget.existing!.id,
          name: _name.text,
          kind: _kind,
          openingBalanceMinor: opening,
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
    final w = widget.existing!;
    try {
      await ref.read(walletRepositoryProvider).setArchived(w.id, !w.archived);
      if (mounted) Navigator.pop(context);
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final cur = ref.watch(currencyProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEdit ? 'Edit wallet' : 'New wallet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<WalletKind>(
              isExpanded: true,
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final k in WalletKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: 'Opening balance (optional)',
                prefixText: '${cur.symbol} ',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
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
