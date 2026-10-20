import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/catalog_repositories.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/services/csv_service.dart';

class ImportResult {
  const ImportResult({
    required this.imported,
    required this.skippedDuplicates,
    required this.failed,
  });
  final int imported;
  final int skippedDuplicates;
  final int failed;
}

/// Previews and commits CSV imports. Commits run in one DB transaction so a
/// failure leaves the existing data untouched.
class ImportService {
  ImportService({
    required this.db,
    required this.transactions,
    required this.categories,
    required this.wallets,
    this.csv = const CsvService(),
  });

  final AppDatabase db;
  final TransactionRepository transactions;
  final CategoryRepository categories;
  final WalletRepository wallets;
  final CsvService csv;

  Future<ImportPreview> preview(String text) async {
    final existing = await transactions.getAllActive();
    final cats = await categories.getAll();
    final ws = await wallets.getAll();
    final walletNames = {for (final w in ws) w.id: w.name};
    return csv.parse(
      text,
      categories: cats,
      wallets: ws,
      existingIds: existing.map((t) => t.id).toSet(),
      existingFingerprints: {
        for (final t in existing)
          CsvService.fingerprint(
            date: t.occurredAt,
            hasTime: t.hasTime,
            type: t.type,
            amountMinor: t.amountMinor,
            wallet: walletNames[t.walletId] ?? '',
            payee: t.payee,
            note: t.note,
          ),
      },
    );
  }

  Future<ImportResult> commit(
    ImportPreview preview, {
    bool skipDuplicates = true,
  }) async {
    var imported = 0;
    var skipped = 0;
    var failed = 0;
    await db.transaction(() async {
      final catCache = <String, String>{};
      final walletCache = <String, String>{};
      for (final c in await categories.getAll()) {
        catCache['${c.type.name}:${c.name.toLowerCase()}'] = c.id;
      }
      for (final w in await wallets.getAll()) {
        walletCache[w.name.toLowerCase()] = w.id;
      }
      Future<String> walletId(String name) async {
        final key = name.toLowerCase();
        final hit = walletCache[key];
        if (hit != null) return hit;
        final id = await wallets.add(
          name: name,
          kind: WalletKind.bank,
          colorValue: 0xFF1976D2,
        );
        walletCache[key] = id;
        return id;
      }

      Future<String?> categoryId(String name, TxnType type) async {
        if (name.isEmpty) return null;
        final ct = type == TxnType.income
            ? CategoryType.income
            : CategoryType.expense;
        final key = '${ct.name}:${name.toLowerCase()}';
        final hit = catCache[key];
        if (hit != null) return hit;
        final id = await categories.add(
          name: name,
          type: ct,
          iconKey: 'category',
          colorValue: 0xFF546E7A,
        );
        catCache[key] = id;
        return id;
      }

      for (final row in preview.rows) {
        if (row.isDuplicate && skipDuplicates) {
          skipped++;
          continue;
        }
        try {
          await transactions.add(
            TxnInput(
              type: row.type,
              amountMinor: row.amountMinor,
              walletId: await walletId(
                row.walletName.isEmpty ? 'Cash' : row.walletName,
              ),
              toWalletId: row.type == TxnType.transfer
                  ? await walletId(row.toWalletName)
                  : null,
              categoryId: await categoryId(row.categoryName, row.type),
              occurredAt: row.occurredAt,
              hasTime: row.hasTime,
              note: row.note,
              payee: row.payee,
            ),
          );
          imported++;
        } on ValidationException {
          failed++;
        }
      }
    });
    return ImportResult(
      imported: imported,
      skippedDuplicates: skipped,
      failed: failed,
    );
  }
}
