import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../db/erp_database.dart';
import 'organization_profile_service.dart';

class PdfExportService {
  PdfExportService(ErpDatabase database)
    : _organizationService = OrganizationProfileService(database);

  final OrganizationProfileService _organizationService;

  Future<Uint8List> stockCountPdf({
    required Map<String, Object?> count,
    required List<Map<String, Object?>> lines,
    required String organizationName,
    required String generatedBy,
  }) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoKufiArabic-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf'),
    );
    final document = pw.Document();
    final profile = await _organizationService.current();
    final logoBytes = await _organizationService.logoBytes(profile);
    final effectiveName = profile?.nameAr ?? organizationName;
    final totalVariance = lines.fold<int>(
      0,
      (total, line) => total + (line['variance_qty_minor'] as int),
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 30),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        textDirection: pw.TextDirection.rtl,
        header: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.blueGrey, width: .5),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 50,
                  height: 50,
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
                pw.SizedBox(width: 9),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        effectiveName,
                        style: pw.TextStyle(font: bold, fontSize: 12),
                      ),
                      if (profile?.address?.trim().isNotEmpty == true)
                        pw.Text(
                          profile!.address!,
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      if (profile?.phones?.trim().isNotEmpty == true)
                        pw.Text(
                          'هاتف: ${profile!.phones}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                    ],
                  ),
                ),
                pw.Text(
                  'تقرير جرد مخزني',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 15,
                    color: PdfColors.blue900,
                  ),
                ),
              ],
            ),
          ),
        ),
        footer: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'أنشئ بواسطة: $generatedBy',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'صفحة ${context.pageNumber} من ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 12),
                pw.Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _labelValue('رقم الجرد', '${count['document_no']}'),
                    _labelValue('المخزن', '${count['warehouse_name']}'),
                    _labelValue('الحالة', _statusLabel('${count['status']}')),
                    _labelValue('تاريخ الإنشاء', '${count['created_at']}'),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.TableHelper.fromTextArray(
                  border: pw.TableBorder.all(
                    color: PdfColors.blueGrey200,
                    width: .4,
                  ),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey100,
                  ),
                  headerStyle: pw.TextStyle(font: bold, fontSize: 8),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  cellAlignment: pw.Alignment.centerRight,
                  headers: const [
                    '#',
                    'الرمز',
                    'الصنف',
                    'الدفتر',
                    'الفعلي',
                    'الفرق',
                    'الوحدة',
                  ],
                  data: List<List<String>>.generate(lines.length, (index) {
                    final line = lines[index];
                    final variance = line['variance_qty_minor'] as int;
                    return [
                      '${index + 1}',
                      '${line['sku']}',
                      '${line['name_ar']}',
                      '${line['system_qty_minor']}',
                      '${line['counted_qty_minor']}',
                      '${variance > 0 ? '+' : ''}$variance',
                      '${line['unit_name']}',
                    ];
                  }),
                ),
                pw.SizedBox(height: 14),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blueGrey50,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                    'إجمالي فرق الكميات: ${totalVariance > 0 ? '+' : ''}$totalVariance',
                    style: pw.TextStyle(font: bold, fontSize: 11),
                  ),
                ),
                if ((count['notes'] as String?)?.trim().isNotEmpty == true) ...[
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'ملاحظات: ${count['notes']}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<void> printStockCount({
    required Map<String, Object?> count,
    required List<Map<String, Object?>> lines,
    required String organizationName,
    required String generatedBy,
  }) async {
    await Printing.layoutPdf(
      name: 'جرد-${count['document_no']}.pdf',
      onLayout: (_) => stockCountPdf(
        count: count,
        lines: lines,
        organizationName: organizationName,
        generatedBy: generatedBy,
      ),
    );
  }

  Future<void> shareStockCount({
    required Map<String, Object?> count,
    required List<Map<String, Object?>> lines,
    required String organizationName,
    required String generatedBy,
  }) async {
    final bytes = await stockCountPdf(
      count: count,
      lines: lines,
      organizationName: organizationName,
      generatedBy: generatedBy,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'جرد-${count['document_no']}.pdf',
    );
  }

  pw.Widget _labelValue(String label, String value) => pw.RichText(
    text: pw.TextSpan(
      children: [
        pw.TextSpan(
          text: '$label: ',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        ),
        pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 9)),
      ],
    ),
  );

  String _statusLabel(String status) => switch (status) {
    'draft' => 'مسودة',
    'approved' => 'معتمد',
    'cancelled' => 'ملغي',
    _ => status,
  };
}
