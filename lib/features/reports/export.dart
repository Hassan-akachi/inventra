import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils.dart';
import 'currency.dart';
import 'periods.dart';
import 'reports.dart';

/// One CSV cell: quoted when it holds a comma, quote or line break.
String _cell(Object? v) {
  if (v == null) return '';
  final s = '$v';
  if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String toCsv(List<String> header, Iterable<List<Object?>> rows) {
  final b = StringBuffer()..writeln(header.map(_cell).join(','));
  for (final r in rows) {
    b.writeln(r.map(_cell).join(','));
  }
  return b.toString();
}

/// Amount in major units for spreadsheets (125050 -> 1250.50).
String _major(int? minor) => minor == null ? '' : (minor / 100).toStringAsFixed(2);

String _slug(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

/// Writes [content] to a temporary file and opens the share sheet.
Future<void> shareTextFile(String fileName, String content, {String mime = 'text/csv'}) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, fileName));
  // BOM so Excel opens ₦ and other symbols correctly.
  await file.writeAsString('﻿$content');
  await Share.shareXFiles([XFile(file.path, mimeType: mime)], subject: fileName);
}

class Exporter {
  Exporter(this._db, this._businessId, {required this.showCosts});
  final PowerSyncDatabase _db;
  final String _businessId;
  final bool showCosts;

  /// Every item in a shop (or all shops) with stock and prices.
  Future<void> items({String? shopId, required String label}) async {
    final rows = await _db.getAll(
      'SELECT m.name AS shop, c.name AS category, i.*, '
      'COALESCE((SELECT SUM(s.change) FROM stock_movements s WHERE s.item_id = i.id), 0) AS qty '
      'FROM items i LEFT JOIN main_categories m ON m.id = i.main_category_id '
      'LEFT JOIN item_categories c ON c.id = i.item_category_id '
      'WHERE i.business_id = ? AND i.deleted_at IS NULL ${shopId == null ? '' : 'AND i.main_category_id = ?'} '
      'ORDER BY m.name, c.name, i.name',
      [_businessId, if (shopId != null) shopId],
    );
    final header = [
      'Shop', 'Category', 'Item', 'Barcode', 'Size', 'Unit', 'Quantity', 'Low-stock level',
      'Currency', if (showCosts) 'Cost price', 'Selling price',
      if (showCosts) 'Stock value (cost)', 'Stock value (selling)', 'Expiry date', 'Discontinued', 'Note',
    ];
    final data = rows.map((r) {
      final q = (r['qty'] as num?)?.toInt() ?? 0;
      final cost = r['cost_price'] as int?;
      final sell = r['selling_price'] as int?;
      return <Object?>[
        r['shop'], r['category'], r['name'], r['barcode'], r['size'], r['base_unit'], q,
        r['low_stock_level'], r['currency'],
        if (showCosts) _major(cost), _major(sell),
        if (showCosts) _major(q > 0 && cost != null ? q * cost : 0),
        _major(q > 0 && sell != null ? q * sell : 0),
        r['expiry_date'], (r['discontinued'] == 1) ? 'Yes' : 'No', r['note'],
      ];
    });
    await shareTextFile('inventra-items-${_slug(label)}-${dateOnly(DateTime.now())}.csv',
        toCsv(header, data));
  }

  /// One row per sale in the range.
  Future<void> sales({String? shopId, required ReportRange range, required String label}) async {
    final rows = await _db.getAll(
      'SELECT s.*, m.name AS shop, c.name AS customer FROM sales s '
      'LEFT JOIN main_categories m ON m.id = s.main_category_id '
      'LEFT JOIN customers c ON c.id = s.customer_id '
      'WHERE s.business_id = ? AND s.deleted_at IS NULL AND s.sold_at >= ? AND s.sold_at < ? '
      '${shopId == null ? '' : 'AND s.main_category_id = ? '}ORDER BY s.sold_at',
      [_businessId, range.fromIso, range.toIso, if (shopId != null) shopId],
    );
    final header = [
      'Date', 'Receipt', 'Shop', 'Customer', 'Currency', 'Subtotal', 'Discount', 'Total',
      'Paid', 'Balance', 'Status', 'Cancelled',
    ];
    final data = rows.map((r) {
      final total = (r['total'] as int?) ?? 0;
      final paid = (r['amount_paid'] as int?) ?? 0;
      return <Object?>[
        formatDateTime(r['sold_at'] as String?), r['receipt_no'], r['shop'], r['customer'],
        r['currency'], _major(r['subtotal'] as int?), _major(r['discount'] as int?),
        _major(total), _major(paid), _major(total - paid), r['payment_status'],
        r['voided_at'] == null ? 'No' : 'Yes',
      ];
    });
    await shareTextFile('inventra-sales-${_slug(label)}-${dateOnly(range.start)}.csv',
        toCsv(header, data));
  }

  /// One row per expense in the range.
  Future<void> expenses({String? shopId, required ReportRange range, required String label}) async {
    final rows = await _db.getAll(
      'SELECT e.*, m.name AS shop FROM expenses e LEFT JOIN main_categories m ON m.id = e.main_category_id '
      'WHERE e.business_id = ? AND e.deleted_at IS NULL AND e.spent_at >= ? AND e.spent_at < ? '
      '${shopId == null ? '' : 'AND e.main_category_id = ? '}ORDER BY e.spent_at',
      [_businessId, dateOnly(range.start), dateOnly(range.end), if (shopId != null) shopId],
    );
    await shareTextFile(
      'inventra-expenses-${_slug(label)}-${dateOnly(range.start)}.csv',
      toCsv(['Date', 'Shop', 'Type', 'Currency', 'Amount', 'Note'], [
        for (final r in rows)
          [r['spent_at'], r['shop'] ?? 'Whole business', r['category'], r['currency'],
           _major(r['amount'] as int?), r['note']],
      ]),
    );
  }

  /// One row per item line sold in the range (for detailed analysis).
  Future<void> saleLines({String? shopId, required ReportRange range, required String label}) async {
    final rows = await _db.getAll(
      'SELECT s.sold_at, s.receipt_no, s.currency, m.name AS shop, si.* FROM sale_items si '
      'JOIN sales s ON s.id = si.sale_id LEFT JOIN main_categories m ON m.id = s.main_category_id '
      'WHERE s.business_id = ? AND s.voided_at IS NULL AND s.deleted_at IS NULL '
      'AND s.sold_at >= ? AND s.sold_at < ? '
      '${shopId == null ? '' : 'AND s.main_category_id = ? '}ORDER BY s.sold_at',
      [_businessId, range.fromIso, range.toIso, if (shopId != null) shopId],
    );
    final header = [
      'Date', 'Receipt', 'Shop', 'Item', 'Unit', 'Quantity', 'Base quantity', 'Currency',
      'Unit price', 'Line total', if (showCosts) 'Cost', if (showCosts) 'Profit',
    ];
    final data = rows.map((r) {
      final qty = (r['quantity'] as int?) ?? 0;
      final line = (r['line_total'] as int?) ?? 0;
      final cost = ((r['cost_price'] as int?) ?? 0) * qty;
      return <Object?>[
        formatDateTime(r['sold_at'] as String?), r['receipt_no'], r['shop'], r['item_name'],
        r['unit_name'], qty, r['base_quantity'], r['currency'], _major(r['unit_price'] as int?),
        _major(line), if (showCosts) _major(cost), if (showCosts) _major(line - cost),
      ];
    });
    await shareTextFile('inventra-items-sold-${_slug(label)}-${dateOnly(range.start)}.csv',
        toCsv(header, data));
  }
}

/// A one-page PDF of the report, ready to share or print.
Future<Uint8List> buildReportPdf({
  required Report report,
  required String businessName,
  required String scopeLabel,
  required bool showCosts,
  required Rates rates,
  required String reportCurrency,
}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
  const indigo = PdfColor.fromInt(0xFF14213D);
  const gold = PdfColor.fromInt(0xFFF2B705);
  final h = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: indigo);

  String change(int now, int before) {
    final c = percentChange(now, before);
    return c == null ? '—' : '${c >= 0 ? '+' : ''}${c.toStringAsFixed(1)}%';
  }

  pw.Widget table(List<String> header, List<List<String>> rows) => pw.TableHelper.fromTextArray(
        headers: header,
        data: rows,
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: indigo),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {for (var i = 1; i < header.length; i++) i: pw.Alignment.centerRight},
        border: null,
        rowDecoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      );

  final totalsRows = [
    for (final e in report.totals.entries)
      [
        e.key,
        Money.format(e.value.sales, e.key),
        change(e.value.sales, report.previous[e.key]?.sales ?? 0),
        '${e.value.count}',
        Money.format(e.value.averageSale, e.key),
        if (showCosts) Money.format(e.value.profit, e.key),
        Money.format(e.value.unpaid, e.key),
      ],
  ];
  final combined = report.totals.length > 1
      ? rates.sumIn(report.map((t) => t.sales), reportCurrency)
      : null;

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    header: (_) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: gold, width: 3))),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(businessName, style: h.copyWith(fontSize: 16))),
        pw.Text('Inventra report', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ]),
    ),
    footer: (c) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${c.pageNumber} of ${c.pagesCount} · '
          '${DateFormat('d MMM yyyy, HH:mm').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
    build: (_) => [
      pw.SizedBox(height: 8),
      pw.Text('$scopeLabel · ${report.range.label}', style: const pw.TextStyle(fontSize: 11)),
      pw.SizedBox(height: 12),
      pw.Text('Summary', style: h),
      pw.SizedBox(height: 6),
      if (report.totals.isEmpty)
        pw.Text('No sales in this period.')
      else
        table([
          'Currency', 'Sales', 'vs previous', 'Sales count', 'Average',
          if (showCosts) 'Profit', 'Unpaid',
        ], totalsRows),
      if (showCosts && report.expenses.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        table(['Currency', 'Profit', 'Expenses', 'Net profit'], [
          for (final c in {...report.totals.keys, ...report.expenses.keys})
            [
              c,
              Money.format(report.totals[c]?.profit ?? 0, c),
              Money.format(report.expenses[c] ?? 0, c),
              Money.format(report.netProfit()[c] ?? 0, c),
            ],
        ]),
      ],
      if (combined != null) ...[
        pw.SizedBox(height: 4),
        pw.Text('Combined: ${Money.format(combined, reportCurrency)} '
            '(rates from ExchangeRate-API or entered by you)',
            style: const pw.TextStyle(fontSize: 9)),
      ],
      pw.SizedBox(height: 16),
      if (report.items.isNotEmpty) ...[
        pw.Text('Best sellers', style: h),
        pw.SizedBox(height: 6),
        table([
          'Item', 'Quantity', 'Sales', if (showCosts) 'Profit',
        ], [
          for (final i in report.items.take(15))
            [
              i.name, '${i.quantity} ${i.baseUnit}', Money.format(i.revenue, i.currency),
              if (showCosts) Money.format(i.profit, i.currency),
            ],
        ]),
        pw.SizedBox(height: 16),
      ],
      if (report.categories.isNotEmpty) ...[
        pw.Text('Sales by category', style: h),
        pw.SizedBox(height: 6),
        table(['Category', 'Quantity', 'Sales'], [
          for (final c in report.categories) [c.label, '${c.count}', Money.format(c.amount, c.currency)],
        ]),
        pw.SizedBox(height: 16),
      ],
      if (report.payments.isNotEmpty) ...[
        pw.Text('Money received', style: h),
        pw.SizedBox(height: 6),
        table(['Method', 'Payments', 'Amount'], [
          for (final c in report.payments)
            [c.label.toUpperCase() == 'POS' ? 'POS' : '${c.label[0].toUpperCase()}${c.label.substring(1)}',
             '${c.count}', Money.format(c.amount, c.currency)],
        ]),
        pw.SizedBox(height: 16),
      ],
      if (showCosts && report.expenseCategories.isNotEmpty) ...[
        pw.Text('Expenses', style: h),
        pw.SizedBox(height: 6),
        table(['Type', 'Payments', 'Amount'], [
          for (final c in report.expenseCategories) [c.label, '${c.count}', Money.format(c.amount, c.currency)],
        ]),
        pw.SizedBox(height: 16),
      ],
      if (report.stock.isNotEmpty) ...[
        pw.Text('Stock on hand now', style: h),
        pw.SizedBox(height: 6),
        table([
          'Currency', 'Items', 'Units', if (showCosts) 'Value at cost', 'Value at selling price',
        ], [
          for (final s in report.stock)
            [
              s.currency, '${s.items}', '${s.units}',
              if (showCosts) Money.format(s.cost, s.currency), Money.format(s.retail, s.currency),
            ],
        ]),
      ],
    ],
  ));
  return doc.save();
}

Future<void> shareReportPdf(Uint8List bytes, String label) =>
    Printing.sharePdf(bytes: bytes, filename: 'inventra-report-${_slug(label)}.pdf');
