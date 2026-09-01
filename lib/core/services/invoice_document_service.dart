import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../db/erp_database.dart';
import 'organization_profile_service.dart';

enum InvoicePrintFormat { a4, thermal80, thermal58 }

class InvoiceDocumentService {
  InvoiceDocumentService(this._database)
    : _organizationService = OrganizationProfileService(_database);
  final ErpDatabase _database;
  final OrganizationProfileService _organizationService;

  Future<Uint8List> build({
    required String kind,
    required String invoiceId,
    required InvoicePrintFormat format,
  }) async {
    final sale = kind == 'sale';
    final table = sale ? 'sales_invoices' : 'purchase_invoices';
    final partyTable = sale ? 'customers' : 'suppliers';
    final partyColumn = sale ? 'customer_id' : 'supplier_id';
    final lineTable = sale ? 'sales_lines' : 'purchase_lines';
    final headerRows = await _database.raw.rawQuery(
      '''SELECT i.*, o.name_ar AS organization_name, o.address AS organization_address,
          o.phones AS organization_phone, o.email AS organization_email,
          o.tax_number AS organization_tax_number,
          o.commercial_register AS organization_commercial_register,
          p.name AS party_name, u.display_name AS created_by_name
         FROM $table i
         JOIN organizations o ON o.id = (SELECT id FROM organizations LIMIT 1)
         LEFT JOIN $partyTable p ON p.id = i.$partyColumn
         LEFT JOIN users u ON u.id = i.created_by
         WHERE i.id = ? LIMIT 1''',
      [invoiceId],
    );
    if (headerRows.isEmpty) throw StateError('الفاتورة غير موجودة');
    final header = headerRows.first;
    final lineRows = await _database.raw.rawQuery(
      sale
          ? '''SELECT l.*, p.name_ar, u.name_ar AS unit_name, l.unit_price_minor AS amount_minor
              FROM $lineTable l JOIN products p ON p.id = l.product_id
              LEFT JOIN units u ON u.id = l.unit_id WHERE l.invoice_id = ? ORDER BY l.rowid'''
          : '''SELECT l.*, p.name_ar, u.name_ar AS unit_name, l.unit_cost_minor AS amount_minor
              FROM $lineTable l JOIN products p ON p.id = l.product_id
              LEFT JOIN units u ON u.id = l.unit_id WHERE l.invoice_id = ? ORDER BY l.rowid''',
      [invoiceId],
    );
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoKufiArabic-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf'),
    );
    final profile = await _organizationService.current();
    final logoBytes = await _organizationService.logoBytes(profile);
    final a4 = format == InvoicePrintFormat.a4;
    final pageFormat = switch (format) {
      InvoicePrintFormat.a4 => PdfPageFormat.a4,
      InvoicePrintFormat.thermal80 => PdfPageFormat(
        80 * PdfPageFormat.mm,
        360 * PdfPageFormat.mm,
      ),
      InvoicePrintFormat.thermal58 => PdfPageFormat(
        58 * PdfPageFormat.mm,
        360 * PdfPageFormat.mm,
      ),
    };
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: a4
            ? const pw.EdgeInsets.all(28)
            : const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 10),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        textDirection: pw.TextDirection.rtl,
        footer: a4
            ? (context) => pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'المستخدم: ${header['created_by_name'] ?? 'النظام'}',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                    pw.Text(
                      'صفحة ${context.pageNumber} من ${context.pagesCount}',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ],
                ),
              )
            : null,
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: a4 ? 58 : 30,
                      height: a4 ? 58 : 30,
                      padding: const pw.EdgeInsets.all(3),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: PdfColors.blueGrey200,
                          width: .35,
                        ),
                        borderRadius: pw.BorderRadius.circular(5),
                      ),
                      child: pw.Image(
                        pw.MemoryImage(logoBytes),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                    pw.SizedBox(width: a4 ? 10 : 5),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            header['organization_name'] as String,
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: a4 ? 16 : 10,
                            ),
                          ),
                          if (header['organization_address'] != null)
                            pw.Text(
                              header['organization_address'] as String,
                              style: pw.TextStyle(fontSize: a4 ? 8 : 6),
                            ),
                          if (header['organization_phone'] != null)
                            pw.Text(
                              'هاتف: ${header['organization_phone']}',
                              style: pw.TextStyle(fontSize: a4 ? 8 : 6),
                            ),
                          if (a4 && header['organization_email'] != null)
                            pw.Text(
                              'البريد: ${header['organization_email']}',
                              style: const pw.TextStyle(fontSize: 7),
                            ),
                          if (a4 && header['organization_tax_number'] != null)
                            pw.Text(
                              'الرقم الضريبي: ${header['organization_tax_number']}',
                              style: const pw.TextStyle(fontSize: 7),
                            ),
                          if (a4 &&
                              header['organization_commercial_register'] !=
                                  null)
                            pw.Text(
                              'السجل التجاري: ${header['organization_commercial_register']}',
                              style: const pw.TextStyle(fontSize: 7),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: a4 ? 14 : 7),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      sale ? 'فاتورة مبيعات' : 'فاتورة مشتريات',
                      style: pw.TextStyle(font: bold, fontSize: a4 ? 13 : 9),
                    ),
                    pw.Text(
                      header['invoice_no'] as String,
                      style: pw.TextStyle(font: bold, fontSize: a4 ? 11 : 8),
                    ),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'التاريخ: ${header['invoice_date']}  •  الطرف: ${header['party_name'] ?? (sale ? 'نقدي' : 'غير محدد')}',
                  style: pw.TextStyle(fontSize: a4 ? 8 : 6),
                ),
                pw.SizedBox(height: 8),
                _linesTable(lineRows, a4: a4, regular: regular, bold: bold),
                pw.SizedBox(height: 8),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.blueGrey200,
                        width: .4,
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _amountRow(
                          'الإجمالي قبل الخصم',
                          header['subtotal_minor'] as int,
                          a4,
                          bold,
                        ),
                        _amountRow(
                          'الخصم',
                          header['discount_minor'] as int,
                          a4,
                          regular,
                        ),
                        _amountRow(
                          'الضريبة',
                          header['tax_minor'] as int,
                          a4,
                          regular,
                        ),
                        _amountRow(
                          'الإجمالي النهائي',
                          header['total_minor'] as int,
                          a4,
                          bold,
                        ),
                        _amountRow(
                          'المدفوع',
                          header['paid_minor'] as int,
                          a4,
                          regular,
                        ),
                        _amountRow(
                          'المتبقي',
                          header['due_minor'] as int,
                          a4,
                          bold,
                        ),
                      ],
                    ),
                  ),
                ),
                if (header['notes'] != null &&
                    (header['notes'] as String).trim().isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'ملاحظات: ${header['notes']}',
                    style: pw.TextStyle(fontSize: a4 ? 8 : 6),
                  ),
                ],
                pw.SizedBox(height: 10),
                pw.Center(
                  child: pw.Text(
                    'شكراً لتعاملكم معنا',
                    style: pw.TextStyle(fontSize: a4 ? 8 : 6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _linesTable(
    List<Map<String, Object?>> rows, {
    required bool a4,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    final headers = a4
        ? const ['الصنف', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي']
        : const ['الصنف', 'ك', 'س', 'إجمالي'];
    final data = rows.map((row) {
      final quantity = row['quantity_minor'] as int;
      final amount = row['amount_minor'] as int;
      final total = row['line_total_minor'] as int;
      return a4
          ? [
              '${row['name_ar']}',
              '${row['unit_name'] ?? ''}',
              '$quantity',
              '$amount',
              '$total',
            ]
          : ['${row['name_ar']}', '$quantity', '$amount', '$total'];
    }).toList();
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(font: bold, fontSize: a4 ? 8 : 5),
      cellStyle: pw.TextStyle(font: regular, fontSize: a4 ? 7 : 5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
      cellAlignment: pw.Alignment.centerRight,
      border: pw.TableBorder.all(color: PdfColors.blueGrey200, width: .35),
    );
  }

  pw.Widget _amountRow(String label, int amount, bool a4, pw.Font font) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(font: font, fontSize: a4 ? 8 : 6),
            ),
            pw.Text(
              '$amount',
              style: pw.TextStyle(font: font, fontSize: a4 ? 8 : 6),
            ),
          ],
        ),
      );

  Future<void> share({
    required String kind,
    required String invoiceId,
    required InvoicePrintFormat format,
  }) async {
    final bytes = await build(kind: kind, invoiceId: invoiceId, format: format);
    await Printing.sharePdf(bytes: bytes, filename: 'invoice-$invoiceId.pdf');
  }

  Future<void> print({
    required String kind,
    required String invoiceId,
    required InvoicePrintFormat format,
  }) => Printing.layoutPdf(
    name: 'invoice-$invoiceId.pdf',
    onLayout: (_) => build(kind: kind, invoiceId: invoiceId, format: format),
  );
}
