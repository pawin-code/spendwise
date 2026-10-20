import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/data/repositories/transaction_repository.dart';
import 'package:spendwise/domain/calculations.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/services/csv_service.dart';

import '../helpers.dart';

CategoryRow cat(String id, String name, CategoryType t) => CategoryRow(
  id: id,
  name: name,
  type: t,
  iconKey: 'category',
  colorValue: 0,
  archived: false,
  isDefault: false,
  sortOrder: 0,
);

void main() {
  const csv = CsvService();
  final cats = [
    cat('cat_food', 'Food & groceries', CategoryType.expense),
    cat('cat_salary', 'Salary', CategoryType.income),
  ];
  final wallets = [walletRow('Cash'), walletRow('HDFC')];

  ImportPreview parse(
    String text, {
    Set<String> ids = const {},
    Set<String> fps = const {},
  }) => csv.parse(
    text,
    categories: cats,
    wallets: wallets,
    existingIds: ids,
    existingFingerprints: fps,
  );

  test('export then import round-trips amounts, dates and text exactly', () {
    final category = cats.first;
    final wallet = wallets.first;
    final views = [
      TxnView(
        txn(
          amount: 123456,
          at: DateTime(2026, 10, 3, 12),
          payee: 'Big Bazaar',
          note: 'weekly, "bulk" shop',
        ),
        category,
        wallet,
        null,
      ),
      TxnView(
        txn(
          type: TxnType.income,
          amount: 5000000,
          category: 'cat_salary',
          at: DateTime(2026, 10, 1, 12),
        ),
        cats[1],
        wallet,
        null,
      ),
    ];
    final text = csv.exportTransactions(views);
    final preview = parse(text);
    expect(preview.fatalError, isNull);
    expect(preview.errors, isEmpty);
    expect(preview.rows.length, 2);
    expect(preview.rows[0].amountMinor, 123456);
    expect(preview.rows[0].payee, 'Big Bazaar');
    expect(preview.rows[0].note, 'weekly, "bulk" shop');
    expect(preview.rows[0].occurredAt, DateTime(2026, 10, 3));
    expect(preview.rows[1].type, TxnType.income);
    expect(preview.rows[1].categoryName, 'Salary');
  });

  test(
    'export neutralises spreadsheet formulas and import restores the text',
    () {
      final views = [
        TxnView(
          txn(note: '=HYPERLINK("http://evil")', payee: '+91 98765'),
          cats.first,
          wallets.first,
          null,
        ),
      ];
      final text = csv.exportTransactions(views);
      expect(text, contains("'=HYPERLINK"));
      expect(text, contains("'+91 98765"));
      final row = parse(text).rows.single;
      expect(row.note, '=HYPERLINK("http://evil")');
      expect(row.payee, '+91 98765');
    },
  );

  test('validates every row and reports line numbers', () {
    const text =
        'date,type,amount,category,wallet\n'
        '2026-10-01,expense,100.50,Food & groceries,Cash\n'
        '2026-13-01,expense,10,,Cash\n'
        '2026-02-30,expense,10,,Cash\n'
        '2026-10-02,spend,10,,Cash\n'
        '2026-10-03,expense,abc,,Cash\n'
        '2026-10-04,expense,0,,Cash\n'
        '2026-10-05,expense,1.234,,Cash\n'
        '2026-10-06,transfer,50,,Cash\n'
        '2026-10-07,transfer,50,,Cash,Cash\n'
        '1980-10-07,expense,5,,Cash\n';
    final p = parse(text);
    expect(p.rows.length, 1);
    expect(p.errors.map((e) => e.line), [3, 4, 5, 6, 7, 8, 9, 10, 11]);
    expect(p.errors.first.message, contains('does not exist'));
  });

  test('rejects files with missing required columns or too much data', () {
    expect(parse('foo,bar\n1,2').fatalError, contains('date'));
    expect(parse('').fatalError, isNotNull);
    expect(parse('date,type,amount\n' * 1, ids: {}).rows, isEmpty);
    final big = 'a' * (kMaxImportBytes + 1);
    expect(parse(big).fatalError, contains('5 MB'));
  });

  test('flags duplicates against existing records and within the file', () {
    const text =
        'date,type,amount,wallet,payee,note\n'
        '2026-10-01,expense,100,Cash,Shop,milk\n'
        '2026-10-01,expense,100,Cash,Shop,milk\n'
        '2026-10-02,expense,200,Cash,Shop,eggs\n';
    final fp = CsvService.fingerprint(
      date: DateTime(2026, 10, 2),
      hasTime: false,
      type: TxnType.expense,
      amountMinor: 20000,
      wallet: 'Cash',
      payee: 'Shop',
      note: 'eggs',
    );
    final p = parse(text, fps: {fp});
    expect(p.rows.length, 3);
    expect(p.duplicateCount, 2);
    expect(p.importableCount, 1);
    expect(p.rows[0].isDuplicate, isFalse);
    expect(p.rows[1].isDuplicate, isTrue);
    expect(p.rows[2].isDuplicate, isTrue);
  });

  test('matching ids are duplicates', () {
    final p = parse(
      'id,date,type,amount\nabc,2026-10-01,expense,10\n',
      ids: {'abc'},
    );
    expect(p.rows.single.isDuplicate, isTrue);
  });

  test('marks unknown categories and wallets as new, handles BOM and CRLF', () {
    final p = parse(
      '﻿date,type,amount,category,wallet\r\n2026-10-01,expense,10,Pets,Paytm\r\n',
    );
    expect(p.rows.single.newCategory, isTrue);
    expect(p.rows.single.newWallet, isTrue);
  });

  test('summary export contains totals', () {
    final s = csv.exportSummary(
      periodLabel: 'October 2026',
      summary: summarize([
        txn(type: TxnType.income, amount: 50000, category: 'cat_salary'),
        txn(amount: 12000, category: 'cat_food'),
      ]),
      categoryNames: const {'cat_food': 'Food & groceries'},
    );
    expect(s, contains('Income,500.00'));
    expect(s, contains('Food & groceries,120.00'));
  });
}
