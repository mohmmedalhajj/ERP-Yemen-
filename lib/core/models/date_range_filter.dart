import 'package:flutter/material.dart';

enum DateRangePreset { today, yesterday, thisWeek, previousWeek, thisMonth, previousMonth, thisYear, previousYear, custom }

class DateRangeSelection {
  const DateRangeSelection({required this.preset, required this.from, required this.to});
  final DateRangePreset preset;
  final DateTime from;
  final DateTime to;

  factory DateRangeSelection.today([DateTime? now]) {
    final date = _date(now ?? DateTime.now());
    return DateRangeSelection(preset: DateRangePreset.today, from: date, to: date);
  }

  factory DateRangeSelection.resolve(DateRangePreset preset, {DateTime? now, DateTime? customFrom, DateTime? customTo}) {
    final date = _date(now ?? DateTime.now());
    switch (preset) {
      case DateRangePreset.today:
        return DateRangeSelection(preset: preset, from: date, to: date);
      case DateRangePreset.yesterday:
        final day = date.subtract(const Duration(days: 1));
        return DateRangeSelection(preset: preset, from: day, to: day);
      case DateRangePreset.thisWeek:
        final from = date.subtract(Duration(days: date.weekday - 1));
        return DateRangeSelection(preset: preset, from: from, to: from.add(const Duration(days: 6)));
      case DateRangePreset.previousWeek:
        final thisWeek = date.subtract(Duration(days: date.weekday - 1));
        final from = thisWeek.subtract(const Duration(days: 7));
        return DateRangeSelection(preset: preset, from: from, to: from.add(const Duration(days: 6)));
      case DateRangePreset.thisMonth:
        final from = DateTime(date.year, date.month);
        return DateRangeSelection(preset: preset, from: from, to: DateTime(date.year, date.month + 1, 0));
      case DateRangePreset.previousMonth:
        final from = DateTime(date.year, date.month - 1);
        return DateRangeSelection(preset: preset, from: from, to: DateTime(date.year, date.month, 0));
      case DateRangePreset.thisYear:
        return DateRangeSelection(preset: preset, from: DateTime(date.year), to: DateTime(date.year, 12, 31));
      case DateRangePreset.previousYear:
        return DateRangeSelection(preset: preset, from: DateTime(date.year - 1), to: DateTime(date.year - 1, 12, 31));
      case DateRangePreset.custom:
        final from = _date(customFrom ?? date);
        final to = _date(customTo ?? from);
        if (to.isBefore(from)) throw ArgumentError('نهاية الفترة يجب أن تكون بعد بدايتها');
        return DateRangeSelection(preset: preset, from: from, to: to);
    }
  }

  String get label => switch (preset) {
    DateRangePreset.today => 'اليوم',
    DateRangePreset.yesterday => 'أمس',
    DateRangePreset.thisWeek => 'هذا الأسبوع',
    DateRangePreset.previousWeek => 'الأسبوع السابق',
    DateRangePreset.thisMonth => 'هذا الشهر',
    DateRangePreset.previousMonth => 'الشهر السابق',
    DateRangePreset.thisYear => 'هذه السنة',
    DateRangePreset.previousYear => 'السنة السابقة',
    DateRangePreset.custom => 'فترة مخصصة',
  };

  String get fromIso => _iso(from);
  String get toIso => _iso(to);

  static DateTime _date(DateTime value) => DateTime(value.year, value.month, value.day);
  static String _iso(DateTime value) => value.toIso8601String().substring(0, 10);
}

class DateRangeFilterBar extends StatelessWidget {
  const DateRangeFilterBar({super.key, required this.value, required this.onChanged});
  final DateRangeSelection value;
  final ValueChanged<DateRangeSelection> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      InputChip(label: Text(value.label), avatar: const Icon(Icons.date_range, size: 18), onPressed: () => _select(context)),
      Text('${value.fromIso} — ${value.toIso}', style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Future<void> _select(BuildContext context) async {
    final preset = await showModalBottomSheet<DateRangePreset>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          for (final item in DateRangePreset.values)
            ListTile(title: Text(DateRangeSelection.resolve(item).label), onTap: () => Navigator.pop(context, item)),
        ]),
      ),
    );
    if (!context.mounted || preset == null) return;
    if (preset != DateRangePreset.custom) {
      onChanged(DateRangeSelection.resolve(preset));
      return;
    }
    if (!context.mounted) return;
    final dates = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDateRange: DateTimeRange(start: value.from, end: value.to));
    if (!context.mounted || dates == null) return;
    onChanged(DateRangeSelection.resolve(DateRangePreset.custom, customFrom: dates.start, customTo: dates.end));
  }
}
