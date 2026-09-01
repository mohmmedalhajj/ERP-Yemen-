import 'package:flutter_test/flutter_test.dart';
import 'package:integratederp/core/auth/security.dart';
import 'package:integratederp/core/models/money.dart';
import 'package:integratederp/core/models/date_range_filter.dart';
import 'package:integratederp/domain/services/invoice_posting_service.dart';

void main() {
  group('Money', () {
    test('يحوّل الأرقام العربية إلى وحدة صغرى بدقة', () {
      final amount = Money.fromMajor('١٢٣٬٤٥٦', currencyCode: 'YER');
      expect(amount.minor, 123456);
    });

    test('يقرب نصف الوحدة إلى أعلى وفق السياسة المركزية', () {
      expect(Money.fromRatio(5, 2).minor, 3);
      expect(Money.fromRatio(-5, 2).minor, -3);
    });

    test('يحسب المتوسط المرجح المتحرك', () {
      expect(
        FinancialRounding.weightedAverage(
          existingQuantity: 10,
          existingUnitCostMinor: 100,
          receivedQuantity: 20,
          receivedUnitCostMinor: 160,
        ),
        140,
      );
    });
  });

  group('Totals', () {
    test('يجمع الخصم والضريبة دون استخدام double', () {
      final totals = InvoiceTotals.fromLines([
        const InvoiceLineInput(
          productId: 'p1',
          unitId: 'u1',
          quantityMinor: 2,
          conversionFactor: 1,
          unitAmountMinor: 100,
          discountMinor: 20,
          taxRateBasisPoints: 500,
        ),
        const InvoiceLineInput(
          productId: 'p2',
          unitId: 'u1',
          quantityMinor: 1,
          conversionFactor: 1,
          unitAmountMinor: 50,
          taxRateBasisPoints: 1000,
        ),
      ]);
      expect(totals.subtotalMinor, 250);
      expect(totals.discountMinor, 20);
      expect(totals.taxMinor, 14);
      expect(totals.totalMinor, 244);
    });

    test('يرفض كمية أو خصماً غير صالحين', () {
      expect(
        () => InvoiceTotals.fromLines([
          const InvoiceLineInput(
            productId: 'p1',
            unitId: 'u1',
            quantityMinor: 0,
            conversionFactor: 1,
            unitAmountMinor: 10,
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => InvoiceTotals.fromLines([
          const InvoiceLineInput(
            productId: 'p1',
            unitId: 'u1',
            quantityMinor: 1,
            conversionFactor: 1,
            unitAmountMinor: 10,
            discountMinor: 11,
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('Date ranges', () {
    final now = DateTime(2026, 9, 1);

    test('يحسب اليوم والأمس بصيغة تاريخ ثابتة', () {
      expect(DateRangeSelection.today(now).fromIso, '2026-09-01');
      expect(DateRangeSelection.resolve(DateRangePreset.yesterday, now: now).fromIso, '2026-08-31');
    });

    test('يحسب بداية ونهاية الأسبوع والشهر والسنة', () {
      final week = DateRangeSelection.resolve(DateRangePreset.thisWeek, now: now);
      expect(week.fromIso, '2026-08-31');
      expect(week.toIso, '2026-09-06');
      final month = DateRangeSelection.resolve(DateRangePreset.thisMonth, now: now);
      expect(month.fromIso, '2026-09-01');
      expect(month.toIso, '2026-09-30');
      final year = DateRangeSelection.resolve(DateRangePreset.thisYear, now: now);
      expect(year.fromIso, '2026-01-01');
      expect(year.toIso, '2026-12-31');
    });

    test('يرفض فترة مخصصة معكوسة', () {
      expect(() => DateRangeSelection.resolve(DateRangePreset.custom, customFrom: DateTime(2026, 9, 2), customTo: DateTime(2026, 9, 1)), throwsArgumentError);
    });
  });

  test('تتحقق تجزئة كلمة المرور المملحة ولا تقبل الخطأ', () async {
    final hasher = PasswordHasher();
    final result = await hasher.hash('StrongPass#2026');
    expect(result.hashBase64, isNot(contains('StrongPass')));
    expect(
      await hasher.verify(
        password: 'StrongPass#2026',
        saltBase64: result.saltBase64,
        expectedHashBase64: result.hashBase64,
      ),
      isTrue,
    );
    expect(
      await hasher.verify(
        password: 'wrong-password',
        saltBase64: result.saltBase64,
        expectedHashBase64: result.hashBase64,
      ),
      isFalse,
    );
  });
}
