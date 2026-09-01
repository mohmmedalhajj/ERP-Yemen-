import 'package:intl/intl.dart';

/// قيمة مالية دقيقة بوحدة صغرى؛ لا تستخدم double داخل منطق ERP.
class Money implements Comparable<Money> {
  const Money(this.minor, {this.currencyCode = 'YER', this.decimals = 0});

  final int minor;
  final String currencyCode;
  final int decimals;

  static Money zero({String currencyCode = 'YER', int decimals = 0}) =>
      Money(0, currencyCode: currencyCode, decimals: decimals);

  factory Money.fromMajor(
    String value, {
    String currencyCode = 'YER',
    int decimals = 0,
  }) {
    final normalized = value
        .trim()
        .replaceAll('٬', '')
        .replaceAll(',', '')
        .replaceAll('٫', '.')
        .splitMapJoin(
          RegExp(r'[٠-٩]'),
          onMatch: (match) {
            const arabic = '٠١٢٣٤٥٦٧٨٩';
            return arabic.indexOf(match.group(0)!).toString();
          },
        );
    final sign = normalized.startsWith('-') ? -1 : 1;
    final parts = normalized.replaceFirst('-', '').split('.');
    final whole = int.tryParse(parts.first) ?? 0;
    final fraction = parts.length > 1 ? parts[1] : '';
    final scale = _pow10(decimals);
    final padded = (fraction + ('0' * decimals)).substring(0, decimals);
    final fractionMinor = decimals == 0 ? 0 : int.parse(padded);
    return Money(
      sign * ((whole * scale) + fractionMinor),
      currencyCode: currencyCode,
      decimals: decimals,
    );
  }

  factory Money.fromRatio(
    int numerator,
    int denominator, {
    String currencyCode = 'YER',
    int decimals = 0,
  }) {
    if (denominator == 0) throw ArgumentError('لا يمكن القسمة على صفر');
    return Money(
      _roundHalfUp(numerator, denominator),
      currencyCode: currencyCode,
      decimals: decimals,
    );
  }

  Money operator +(Money other) => _same(other, minor + other.minor);
  Money operator -(Money other) => _same(other, minor - other.minor);
  Money operator -() =>
      Money(-minor, currencyCode: currencyCode, decimals: decimals);
  Money operator *(int factor) =>
      Money(minor * factor, currencyCode: currencyCode, decimals: decimals);
  Money ratio(int numerator, int denominator) => Money.fromRatio(
    minor * numerator,
    denominator,
    currencyCode: currencyCode,
    decimals: decimals,
  );

  Money percentage(int basisPoints) => ratio(basisPoints, 10000);

  bool get isNegative => minor < 0;
  bool get isZero => minor == 0;

  String format({bool withSymbol = true, String? locale}) {
    final formatter = NumberFormat.currency(
      locale: locale ?? 'ar',
      name: withSymbol ? currencyCode : '',
      decimalDigits: decimals,
      symbol: withSymbol ? '$currencyCode ' : '',
    );
    return formatter.format(minor / _pow10(decimals));
  }

  @override
  int compareTo(Money other) {
    _assertCompatible(other);
    return minor.compareTo(other.minor);
  }

  void _assertCompatible(Money other) {
    if (currencyCode != other.currencyCode || decimals != other.decimals) {
      throw ArgumentError('لا يمكن جمع عملتين أو سياستي دقة مختلفتين');
    }
  }

  Money _same(Money other, int value) {
    _assertCompatible(other);
    return Money(value, currencyCode: currencyCode, decimals: decimals);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      minor == other.minor &&
      currencyCode == other.currencyCode &&
      decimals == other.decimals;

  @override
  int get hashCode => Object.hash(minor, currencyCode, decimals);

  @override
  String toString() => '$currencyCode:$minor@$decimals';

  static int _pow10(int n) =>
      n == 0 ? 1 : List<int>.filled(n, 10).fold(1, (a, b) => a * b);

  static int _roundHalfUp(int numerator, int denominator) {
    final negative = (numerator < 0) != (denominator < 0);
    final n = numerator.abs();
    final d = denominator.abs();
    final rounded = (n + (d ~/ 2)) ~/ d;
    return negative ? -rounded : rounded;
  }
}

class FinancialRounding {
  const FinancialRounding._();

  static int percentageOf(int amountMinor, int basisPoints) =>
      Money.fromRatio(amountMinor * basisPoints, 10000).minor;

  static int weightedAverage({
    required int existingQuantity,
    required int existingUnitCostMinor,
    required int receivedQuantity,
    required int receivedUnitCostMinor,
  }) {
    if (existingQuantity < 0 || receivedQuantity <= 0) {
      throw ArgumentError('كميات المتوسط المرجح غير صالحة');
    }
    final totalQuantity = existingQuantity + receivedQuantity;
    if (totalQuantity == 0) return 0;
    return Money.fromRatio(
      (existingQuantity * existingUnitCostMinor) +
          (receivedQuantity * receivedUnitCostMinor),
      totalQuantity,
    ).minor;
  }
}
