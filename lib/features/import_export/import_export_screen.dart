import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/features/import_export/export_sheet.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise/services/csv_service.dart';
import 'package:spendwise/services/export_helper.dart';

class ImportExportScreen extends ConsumerStatefulWidget {
  const ImportExportScreen({super.key});

  @override
  ConsumerState<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends ConsumerState<ImportExportScreen> {
  ImportPreview? _preview;
  bool _skipDuplicates = true;
  bool _busy = false;
  String? _message;

  Future<String> _exportAll({DateTime? from, DateTime? to}) async {
    final repo = ref.read(transactionRepositoryProvider);
    final views = await repo
        .watchViews(
          TxnFilter(
            from: from,
            toExclusive: to,
            sort: TxnSort.dateAsc,
            limit: 1000000,
          ),
        )
        .first;
    return ref.read(csvServiceProvider).exportTransactions(views);
  }

  Future<void> _pickImport() async {
    setState(() {
      _busy = true;
      _message = null;
      _preview = null;
    });
    try {
      final text = await const ExportHelper().pickTextFile();
      if (text == null) return;
      final preview = await ref.read(importServiceProvider).preview(text);
      if (mounted) setState(() => _preview = preview);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'That file could not be opened. Choose a UTF-8 CSV file.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final p = _preview!;
    final n = _skipDuplicates ? p.importableCount : p.rows.length;
    final ok = await confirmDialog(
      context,
      title: 'Import $n transaction${n == 1 ? '' : 's'}?',
      message:
          'They will be added to your existing records. ${p.errors.isEmpty ? '' : '${p.errors.length} invalid row(s) will be skipped. '}You can delete imported items afterwards.',
      confirmLabel: 'Import',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(importServiceProvider)
          .commit(p, skipDuplicates: _skipDuplicates);
      await ref.read(ledgerServiceProvider).refreshAlerts(DateTime.now());
      if (mounted) {
        setState(() {
          _preview = null;
          _message =
              'Imported ${r.imported} transaction${r.imported == 1 ? '' : 's'}${r.skippedDuplicates > 0 ? ', skipped ${r.skippedDuplicates} duplicate(s)' : ''}${r.failed > 0 ? ', ${r.failed} failed' : ''}.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Import failed and nothing was changed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await confirmDialog(
      context,
      title: 'Restore from backup?',
      message: 'This REPLACES all transactions, budgets, wallets and categories on this device with the contents of the backup file. Create a backup first if you want to keep your current data.',
      confirmLabel: 'Choose file',
      destructive: true,
    );
    if (!ok) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final text = await const ExportHelper().pickTextFile(
        extensions: ['json'],
      );
      if (text == null) return;
      final summary = await ref
          .read(backupServiceProvider)
          .restoreFromJson(text);
      if (mounted) {
        setState(
          () => _message =
              'Restored ${summary.transactions} transactions, ${summary.wallets} wallets and ${summary.budgets} budgets.',
        );
      }
    } on BackupException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Restore failed. Your current data was not changed.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Import & export')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _message!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          if (preview != null)
            _PreviewCard(
              preview: preview,
              skipDuplicates: _skipDuplicates,
              onSkip: (v) => setState(() => _skipDuplicates = v),
              onCommit: _busy ? null : _commit,
              onCancel: () => setState(() => _preview = null),
            ),
          const SectionHeader('Export (CSV)'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Spreadsheet-friendly files you can open in Excel or Google Sheets.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.table_view),
                  label: const Text('Export all transactions'),
                  onPressed: () => showExportSheet(
                    context,
                    ref,
                    fileName:
                        'spendwise-transactions-${isoDateString(now)}.csv',
                    build: () => '',
                    buildAsync: _exportAll,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Export this month'),
                  onPressed: () => showExportSheet(
                    context,
                    ref,
                    fileName: 'spendwise-${monthKey(now)}.csv',
                    build: () => '',
                    buildAsync: () => _exportAll(
                      from: startOfMonth(now),
                      to: startOfNextMonth(now),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('Import (CSV)'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Columns: ${kCsvHeader.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Required: date (YYYY-MM-DD), type (income / expense / transfer) and amount. You will see a preview before anything is saved.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Choose CSV file'),
                  onPressed: _busy ? null : _pickImport,
                ),
              ],
            ),
          ),
          const SectionHeader('Backup & restore'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A backup file contains every record on this device (transactions, wallets, categories, budgets, reminders). It is not encrypted and is not uploaded anywhere. Store it somewhere private.',
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Create backup file'),
                  onPressed: () => showExportSheet(
                    context,
                    ref,
                    fileName: 'spendwise-backup-${isoDateString(now)}.json',
                    mimeType: 'application/json',
                    build: () => '',
                    buildAsync: () =>
                        ref.read(backupServiceProvider).createBackupJson(),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restore_page_outlined),
                  label: const Text('Restore from backup'),
                  onPressed: _busy ? null : _restore,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String isoDateString(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({
    required this.preview,
    required this.skipDuplicates,
    required this.onSkip,
    required this.onCommit,
    required this.onCancel,
  });
  final ImportPreview preview;
  final bool skipDuplicates;
  final ValueChanged<bool> onSkip;
  final VoidCallback? onCommit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(currencyProvider);
    if (preview.fatalError != null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                const Text('Cannot import this file'),
              ],
            ),
            const SizedBox(height: 8),
            Text(preview.fatalError!),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Dismiss'),
              ),
            ),
          ],
        ),
      );
    }
    final importCount = skipDuplicates
        ? preview.importableCount
        : preview.rows.length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Import preview',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${preview.rows.length} valid row(s) · ${preview.duplicateCount} possible duplicate(s) · ${preview.errors.length} invalid row(s)',
          ),
          const SizedBox(height: 8),
          if (preview.rows.any((r) => r.newCategory || r.newWallet))
            Text(
              'New categories or wallets named in the file will be created.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          for (final r in preview.rows.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                r.isDuplicate ? Icons.content_copy : Icons.check_circle_outline,
                color: r.isDuplicate
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                '${r.type.name} · ${formatMinor(r.amountMinor, currency: cur)}',
              ),
              subtitle: Text(
                '${formatDay(r.occurredAt)} · ${r.categoryName.isEmpty ? r.walletName : r.categoryName}${r.isDuplicate ? ' · duplicate' : ''}',
              ),
            ),
          if (preview.rows.length > 5)
            Text(
              '…and ${preview.rows.length - 5} more',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (preview.errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Problems', style: Theme.of(context).textTheme.titleSmall),
            for (final e in preview.errors.take(8))
              Text(
                'Row ${e.line}: ${e.message}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            if (preview.errors.length > 8)
              Text(
                '…and ${preview.errors.length - 8} more',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          if (preview.duplicateCount > 0)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Skip possible duplicates'),
              value: skipDuplicates,
              onChanged: onSkip,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: importCount == 0 ? null : onCommit,
                  child: Text('Import $importCount'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
