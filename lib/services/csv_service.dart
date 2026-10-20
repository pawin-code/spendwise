import 'package:csv/csv.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/domain/enums.dart';

const List<String> kCsvHeader = [
  'id',
  'date',
  'time',
  'type',
  'amount',
  'category',
  'wallet',
  'to_wallet',
  'payee',
  'note',
];

const int kMaxImportRows = 20000;
const int kMaxImportBytes = 5 * 1024 * 1024;

String _two(int n) => n.toString().padLeft(2, '0');
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// Neutralises spreadsheet formula injection on export.
String _safeCell(String v) {
  if (v.isEmpty) return v;
  const risky = ['=', '+', '-', '@', '\t', '\r'];
  return risky.contains(v[0]) ? "'$v" : v;
}

/// Reverses [_safeCell] on import.
String _unsafeCell(String v) {
  if (v.length > 1 &&
      v[0] == "'" &&
      const ['=', '+', '-', '@'].contains(v[1])) {
    return v.substring(1);
  }
  return v;
}

class CsvService {
  const CsvService();

  static final Csv _codec = Csv(lineDelimiter: '\n');

  String exportTransactions(List<TxnView> views) {
    final rows = <List<String>>[
      kCsvHeader,
      for (final v in views)
        [
          v.txn.id,
          isoDate(v.txn.occurredAt),
          v.txn.hasTime
              ? '${_two(v.txn.occurredAt.hour)}:${_two(v.txn.occurredAt.minute)}'
              : '',
          v.txn.type.name,
          minorToPlain(v.txn.amountMinor),
          _safeCell(v.category?.name ?? ''),
          _safeCell(v.wallet.name),
          _safeCell(v.toWallet?.name ?? ''),
          _safeCell(v.txn.payee),
          _safeCell(v.txn.note),
        ],
    ];
    return _codec.encode(rows);
  }

  /// Simple two-column summary export used by the Reports screen.
  String exportSummary({
    required String periodLabel,
    required PeriodSummary summary,
    required Map<String, String> categoryNames,
  }) {
    final rows = <List<String>>[
      ['SpendWise report', _safeCell(periodLabel)],
      ['Income', minorToPlain(summary.incomeMinor)],
      ['Expenses', minorToPlain(summary.expenseMinor)],
      ['Net', minorToPlain(summary.netMinor)],
      ['Expense transactions', '${summary.expenseCount}'],
      ['Average expense', minorToPlain(summary.averageExpenseMinor)],
      [],
      ['Category', 'Spent'],
      for (final e
          in (summary.expenseByCategory.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value))))
        [
          _safeCell(categoryNames[e.key] ?? 'Uncategorized'),
          minorToPlain(e.value),
        ],
    ];
    return _codec.encode(rows);
  }

  /// Parses and validates CSV text. Never writes anything; the caller shows the
  /// [ImportPreview] and only then commits.
  ImportPreview parse(
    String text, {
    required List<CategoryRow> categories,
    required List<WalletRow> wallets,
    required Set<String> existingIds,
    required Set<String> existingFingerprints,
  }) {
    if (text.length > kMaxImportBytes) {
      return ImportPreview.failed(
        'File is larger than 5 MB. Split it into smaller files.',
      );
    }
    final clean = text.startsWith('﻿') ? text.substring(1) : text;
    List<List<dynamic>> rows;
    try {
      rows = _codec.decode(clean);
    } catch (_) {
      return ImportPreview.failed('This file could not be read as CSV.');
    }
    rows = rows
        .where((r) => r.any((c) => c.toString().trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) return ImportPreview.failed('The file is empty.');
    final header = rows.first
        .map((c) => c.toString().trim().toLowerCase())
        .toList();
    final idx = <String, int>{
      for (var i = 0; i < header.length; i++) header[i]: i,
    };
    for (final required in const ['date', 'type', 'amount']) {
      if (!idx.containsKey(required)) {
        return ImportPreview.failed(
          'Missing required column "$required". Expected: ${kCsvHeader.join(', ')}.',
        );
      }
    }
    if (rows.length - 1 > kMaxImportRows) {
      return ImportPreview.failed(
        'Too many rows (limit $kMaxImportRows per import).',
      );
    }

    String cell(List<dynamic> r, String name) {
      final i = idx[name];
      if (i == null || i >= r.length) return '';
      return _unsafeCell(r[i].toString().trim());
    }

    final catByName = {
      for (final c in categories) '${c.type.name}:${c.name.toLowerCase()}': c,
    };
    final walletByName = {for (final w in wallets) w.name.toLowerCase(): w};
    final seenIds = <String>{...existingIds};
    final seenFingerprints = <String>{...existingFingerprints};
    final valid = <ImportRow>[];
    final errors = <ImportError>[];
    var duplicates = 0;

    for (var i = 1; i < rows.length; i++) {
      final lineNo = i + 1;
      final r = rows[i];
      final dateText = cell(r, 'date');
      final typeText = cell(r, 'type').toLowerCase();
      final amountText = cell(r, 'amount');
      final timeText = cell(r, 'time');

      final dm = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateText);
      if (dm == null) {
        errors.add(ImportError(lineNo, 'Date "$dateText" must be YYYY-MM-DD.'));
        continue;
      }
      final y = int.parse(dm.group(1)!),
          mo = int.parse(dm.group(2)!),
          d = int.parse(dm.group(3)!);
      var date = DateTime(y, mo, d);
      if (date.year != y || date.month != mo || date.day != d) {
        errors.add(ImportError(lineNo, 'Date "$dateText" does not exist.'));
        continue;
      }
      if (y < 1990 || y > 2100) {
        errors.add(
          ImportError(lineNo, 'Date "$dateText" is outside 1990-2100.'),
        );
        continue;
      }
      var hasTime = false;
      if (timeText.isNotEmpty) {
        final tm = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(timeText);
        if (tm == null) {
          errors.add(ImportError(lineNo, 'Time "$timeText" must be HH:MM.'));
          continue;
        }
        date = DateTime(
          y,
          mo,
          d,
          int.parse(tm.group(1)!),
          int.parse(tm.group(2)!),
        );
        hasTime = true;
      }
      final type = TxnType.values.where((t) => t.name == typeText).firstOrNull;
      if (type == null) {
        errors.add(
          ImportError(
            lineNo,
            'Type "$typeText" must be income, expense or transfer.',
          ),
        );
        continue;
      }
      final amount = parseAmountToMinor(amountText);
      if (amount == null || amount <= 0) {
        errors.add(
          ImportError(
            lineNo,
            'Amount "$amountText" is not a valid positive number (max 2 decimals).',
          ),
        );
        continue;
      }
      final walletName = cell(r, 'wallet');
      final toWalletName = cell(r, 'to_wallet');
      final categoryName = cell(r, 'category');
      final payee = cell(r, 'payee');
      final note = cell(r, 'note');
      if (note.length > 500 || payee.length > 100) {
        errors.add(
          ImportError(lineNo, 'Note (max 500) or payee (max 100) is too long.'),
        );
        continue;
      }
      if (type == TxnType.transfer) {
        if (walletName.isEmpty || toWalletName.isEmpty) {
          errors.add(
            ImportError(lineNo, 'Transfers need both wallet and to_wallet.'),
          );
          continue;
        }
        if (walletName.toLowerCase() == toWalletName.toLowerCase()) {
          errors.add(ImportError(lineNo, 'Transfer wallets must differ.'));
          continue;
        }
      }
      if (walletName.length > 60 ||
          toWalletName.length > 60 ||
          categoryName.length > 40) {
        errors.add(
          ImportError(
            lineNo,
            'Wallet (max 60) or category (max 40) name is too long.',
          ),
        );
        continue;
      }
      final id = cell(r, 'id');
      final fp = fingerprint(
        date: date,
        hasTime: hasTime,
        type: type,
        amountMinor: amount,
        wallet: walletName,
        payee: payee,
        note: note,
      );
      final isDup =
          (id.isNotEmpty && seenIds.contains(id)) ||
          seenFingerprints.contains(fp);
      if (isDup) duplicates++;
      if (id.isNotEmpty) seenIds.add(id);
      seenFingerprints.add(fp);
      final catKey =
          '${(type == TxnType.income ? CategoryType.income : CategoryType.expense).name}:${categoryName.toLowerCase()}';
      valid.add(
        ImportRow(
          line: lineNo,
          type: type,
          amountMinor: amount,
          occurredAt: date,
          hasTime: hasTime,
          categoryName: type == TxnType.transfer ? '' : categoryName,
          walletName: walletName.isEmpty
              ? (wallets.isNotEmpty ? wallets.first.name : 'Cash')
              : walletName,
          toWalletName: toWalletName,
          payee: payee,
          note: note,
          isDuplicate: isDup,
          newCategory:
              type != TxnType.transfer &&
              categoryName.isNotEmpty &&
              !catByName.containsKey(catKey),
          newWallet:
              walletName.isNotEmpty &&
              !walletByName.containsKey(walletName.toLowerCase()),
        ),
      );
    }
    return ImportPreview(
      rows: valid,
      errors: errors,
      duplicateCount: duplicates,
      fatalError: null,
    );
  }

  static String fingerprint({
    required DateTime date,
    required bool hasTime,
    required TxnType type,
    required int amountMinor,
    required String wallet,
    required String payee,
    required String note,
  }) => [
    isoDate(date),
    hasTime ? '${_two(date.hour)}:${_two(date.minute)}' : '',
    type.name,
    amountMinor,
    wallet.toLowerCase(),
    payee.toLowerCase(),
    note.toLowerCase(),
  ].join('|');
}

class ImportRow {
  const ImportRow({
    required this.line,
    required this.type,
    required this.amountMinor,
    required this.occurredAt,
    required this.hasTime,
    required this.categoryName,
    required this.walletName,
    required this.toWalletName,
    required this.payee,
    required this.note,
    required this.isDuplicate,
    required this.newCategory,
    required this.newWallet,
  });

  final int line;
  final TxnType type;
  final int amountMinor;
  final DateTime occurredAt;
  final bool hasTime;
  final String categoryName;
  final String walletName;
  final String toWalletName;
  final String payee;
  final String note;
  final bool isDuplicate;
  final bool newCategory;
  final bool newWallet;
}

class ImportError {
  const ImportError(this.line, this.message);
  final int line;
  final String message;
}

class ImportPreview {
  const ImportPreview({
    required this.rows,
    required this.errors,
    required this.duplicateCount,
    required this.fatalError,
  });

  factory ImportPreview.failed(String message) => ImportPreview(
    rows: const [],
    errors: const [],
    duplicateCount: 0,
    fatalError: message,
  );

  final List<ImportRow> rows;
  final List<ImportError> errors;
  final int duplicateCount;
  final String? fatalError;

  int get importableCount => rows.where((r) => !r.isDuplicate).length;
}
