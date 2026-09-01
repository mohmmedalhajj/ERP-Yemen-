import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../db/erp_database.dart';
import 'organization_profile_service.dart';

class ReportExportService {
  ReportExportService(ErpDatabase database)
    : _organizationService = OrganizationProfileService(database);

  final OrganizationProfileService _organizationService;

  Future<Uint8List> pdf({
    required String title,
    required String organizationName,
    required List<String> headers,
    required List<List<String>> rows,
    required String generatedBy,
    String? period,
    String? filters,
    List<List<String>>? totals,
  }) async {
    final profile = await _organizationService.current();
    final logoBytes = await _organizationService.logoBytes(profile);
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoKufiArabic-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf'),
    );
    final document = pw.Document();
    final effectiveName = profile?.nameAr ?? organizationName;
    final detailLines = <String>[
      if (_filled(profile?.address)) profile!.address!,
      if (_filled(profile?.phones)) 'هاتف: ${profile!.phones}',
      if (_filled(profile?.email)) 'البريد: ${profile!.email}',
      if (_filled(profile?.taxNumber)) 'الرقم الضريبي: ${profile!.taxNumber}',
      if (_filled(profile?.commercialRegister))
        'السجل التجاري: ${profile!.commercialRegister}',
    ];
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 24),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        textDirection: pw.TextDirection.rtl,
        header: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 56,
                    height: 56,
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.blueGrey200),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          effectiveName,
                          style: pw.TextStyle(font: bold, fontSize: 12),
                        ),
                        ...detailLines.map(
                          (line) => pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 2),
                            child: pw.Text(
                              line,
                              style: const pw.TextStyle(fontSize: 6.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    width: 215,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blueGrey50,
                      border: pw.Border.all(color: PdfColors.blueGrey200),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          title,
                          style: pw.TextStyle(
                            font: bold,
                            fontSize: 13,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'الفترة: ${period ?? 'حسب البيانات المعروضة'}',
                          style: const pw.TextStyle(fontSize: 6.5),
                        ),
                        if (_filled(filters))
                          pw.Text(
                            'الفلاتر: $filters',
                            style: const pw.TextStyle(fontSize: 6.5),
                          ),
                        pw.Text(
                          'المستخدم: $generatedBy',
                          style: const pw.TextStyle(fontSize: 6.5),
                        ),
                        pw.Text(
                          'تاريخ الإنشاء: ${DateTime.now().toLocal().toIso8601String().replaceFirst('T', ' ').substring(0, 16)}',
                          style: const pw.TextStyle(fontSize: 6.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
            ],
          ),
        ),
        footer: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Container(
            padding: const pw.EdgeInsets.only(top: 5),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.blueGrey200, width: .35),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'وثيقة صادرة من $effectiveName',
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
                pw.Text(
                  'صفحة ${context.pageNumber} من ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
              ],
            ),
          ),
        ),
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              headerStyle: pw.TextStyle(font: bold, fontSize: 7.5),
              cellStyle: pw.TextStyle(font: regular, fontSize: 6.5),
              cellAlignment: pw.Alignment.centerRight,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey100,
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 3,
                vertical: 4,
              ),
              border: pw.TableBorder.all(
                color: PdfColors.blueGrey200,
                width: .3,
              ),
            ),
          ),
          if (totals != null && totals.isNotEmpty) ...[
            pw.SizedBox(height: 9),
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.TableHelper.fromTextArray(
                data: totals,
                cellStyle: pw.TextStyle(font: bold, fontSize: 7),
                cellPadding: const pw.EdgeInsets.all(4),
                border: pw.TableBorder.all(
                  color: PdfColors.blueGrey200,
                  width: .3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return document.save();
  }

  Future<void> printReport({
    required String title,
    required String organizationName,
    required List<String> headers,
    required List<List<String>> rows,
    required String generatedBy,
    String? period,
    String? filters,
    List<List<String>>? totals,
  }) => Printing.layoutPdf(
    name: '${_safeFileName(title)}.pdf',
    onLayout: (_) => pdf(
      title: title,
      organizationName: organizationName,
      headers: headers,
      rows: rows,
      generatedBy: generatedBy,
      period: period,
      filters: filters,
      totals: totals,
    ),
  );

  Future<void> sharePdf({
    required String title,
    required String organizationName,
    required List<String> headers,
    required List<List<String>> rows,
    required String generatedBy,
    String? period,
    String? filters,
    List<List<String>>? totals,
  }) async {
    final bytes = await pdf(
      title: title,
      organizationName: organizationName,
      headers: headers,
      rows: rows,
      generatedBy: generatedBy,
      period: period,
      filters: filters,
      totals: totals,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${_safeFileName(title)}.pdf',
    );
  }

  Future<File> createXlsx({
    required List<String> headers,
    required List<List<String>> rows,
    required String fileName,
    String? title,
    String? generatedBy,
    List<List<String>>? totals,
  }) async {
    final workbook = Excel.createExcel();
    final sheetName = workbook.getDefaultSheet() ?? 'تقرير';
    final sheet = workbook[sheetName];
    final headerColor = ExcelColor.fromHexString('#163A63');
    final titleColor = ExcelColor.fromHexString('#EAF2FA');
    final titleStyle = CellStyle(
      bold: true,
      fontSize: 15,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      backgroundColorHex: titleColor,
    );
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: headerColor,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final totalStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#EAF2FA'),
    );
    var rowOffset = 0;
    if (title != null) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        ..value = TextCellValue(title)
        ..cellStyle = titleStyle;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(
          columnIndex: headers.length > 1 ? headers.length - 1 : 0,
          rowIndex: 0,
        ),
      );
      sheet.setRowHeight(0, 28);
      rowOffset = 2;
    }
    if (generatedBy != null) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        ..value = TextCellValue('أُنشئ بواسطة: $generatedBy')
        ..cellStyle = CellStyle(italic: true);
    }
    for (var column = 0; column < headers.length; column++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowOffset),
      );
      cell
        ..value = TextCellValue(headers[column])
        ..cellStyle = headerStyle;
    }
    for (var row = 0; row < rows.length; row++) {
      for (var column = 0; column < rows[row].length; column++) {
        sheet
            .cell(
              CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: rowOffset + row + 1,
              ),
            )
            .value = _typedValue(
          rows[row][column],
        );
      }
    }
    if (totals != null) {
      final start = rowOffset + rows.length + 2;
      for (var row = 0; row < totals.length; row++) {
        for (var column = 0; column < totals[row].length; column++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: column,
              rowIndex: start + row,
            ),
          );
          cell
            ..value = _typedValue(totals[row][column])
            ..cellStyle = totalStyle;
        }
      }
    }
    final bytes = workbook.encode();
    if (bytes == null) throw StateError('تعذر إنشاء ملف Excel');
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${_safeFileName(fileName)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> shareXlsx({
    required List<String> headers,
    required List<List<String>> rows,
    required String fileName,
    required String text,
    String? title,
    String? generatedBy,
    List<List<String>>? totals,
  }) async {
    final file = await createXlsx(
      headers: headers,
      rows: rows,
      fileName: fileName,
      title: title,
      generatedBy: generatedBy,
      totals: totals,
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text),
    );
  }

  CellValue _typedValue(String value) {
    final normalized = value
        .replaceAll('٬', '')
        .replaceAll(',', '')
        .replaceAll('٫', '.')
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        .trim();
    final date = DateTime.tryParse(normalized);
    if (date != null && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(normalized)) {
      return DateCellValue(year: date.year, month: date.month, day: date.day);
    }
    final integer = int.tryParse(normalized);
    if (integer != null) return IntCellValue(integer);
    final decimal = double.tryParse(normalized);
    if (decimal != null) return DoubleCellValue(decimal);
    return TextCellValue(value);
  }

  bool _filled(String? value) => value != null && value.trim().isNotEmpty;

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '_');
}
