import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils.dart';
import '../business/business.dart';
import 'sales.dart';

/// Builds an 80 mm receipt. Uses a bundled font so ₦, £, €, ¥ print correctly.
Future<Uint8List> buildReceiptPdf({
  required Business? business,
  required Sale sale,
  required List<SaleLine> lines,
  required List<Payment> payments,
}) async {
  final regular =
      pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final doc = pw.Document(
    title: 'Receipt ${sale.receiptNo}',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  String money(int v) => Money.format(v, sale.currency);

  const small = pw.TextStyle(fontSize: 8);
  const normal = pw.TextStyle(fontSize: 9);
  final boldStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

  pw.Widget row(String left, String right, {pw.TextStyle? style}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(left, style: style ?? normal)),
          pw.Text(right, style: style ?? normal),
        ]),
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(business?.name ?? 'Receipt',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          if (sale.shopName != null)
            pw.Text(sale.shopName!, textAlign: pw.TextAlign.center, style: normal),
          if (business?.address != null)
            pw.Text(business!.address!, textAlign: pw.TextAlign.center, style: small),
          if (business?.phone != null)
            pw.Text(business!.phone!, textAlign: pw.TextAlign.center, style: small),
          pw.SizedBox(height: 6),
          if (sale.voided)
            pw.Text('*** CANCELLED ***',
                textAlign: pw.TextAlign.center, style: boldStyle),
          row('Receipt', sale.receiptNo, style: small),
          row('Date', formatDateTime(sale.soldAt), style: small),
          if (sale.customerName != null) row('Customer', sale.customerName!, style: small),
          pw.Divider(thickness: 0.5),
          for (final l in lines) ...[
            pw.Text(l.itemName, style: boldStyle),
            row('${l.quantity} ${l.unitName} × ${money(l.unitPrice)}', money(l.lineTotal)),
          ],
          pw.Divider(thickness: 0.5),
          row('Subtotal', money(sale.subtotal)),
          if (sale.discount > 0) row('Discount', '− ${money(sale.discount)}'),
          row('TOTAL', money(sale.total),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final p in payments) row('Paid (${p.method.label})', money(p.amount)),
          if (sale.balance > 0) row('Balance due', money(sale.balance), style: boldStyle),
          row('Status', sale.status.label, style: small),
          pw.SizedBox(height: 8),
          pw.Text(business?.receiptFooter ?? 'Thank you!',
              textAlign: pw.TextAlign.center, style: small),
          pw.SizedBox(height: 4),
          pw.Text('Made with Inventra', textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Opens the phone's share sheet (WhatsApp, email…) with the receipt PDF.
Future<void> shareReceipt(Uint8List bytes, String receiptNo) =>
    Printing.sharePdf(bytes: bytes, filename: '$receiptNo.pdf');

/// Sends the receipt to a printer (including Bluetooth/Wi-Fi printers the phone supports).
Future<void> printReceipt(Uint8List bytes, String receiptNo) =>
    Printing.layoutPdf(onLayout: (_) async => bytes, name: receiptNo);
