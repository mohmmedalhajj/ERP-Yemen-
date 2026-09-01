import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/money.dart';
import '../../../core/models/date_range_filter.dart';
import '../../../core/services/providers.dart';
import '../../../data/repositories/report_repository.dart';
import '../../../shared/widgets/app_scaffold.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  DateRangeSelection _range = DateRangeSelection.today();
  String _currency = 'YER';

  @override
  Widget build(BuildContext context) => FutureBuilder<DashboardMetrics>(
    future: ref
        .watch(reportRepositoryProvider)
        .dashboard(
          DateTime.now(),
          from: _range.from,
          to: _range.to,
          currencyCode: _currency,
        ),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError)
        return EmptyState(message: '${context.tr('error')}: ${snapshot.error}');
      final data = snapshot.data!;
      final tiles = <({String label, int value, IconData icon, Color color})>[
        (
          label: context.tr('todaySales'),
          value: data.salesToday,
          icon: Icons.trending_up,
          color: Colors.teal,
        ),
        (
          label: context.tr('todayPurchases'),
          value: data.purchasesToday,
          icon: Icons.shopping_cart,
          color: Colors.indigo,
        ),
        (
          label: context.tr('cashBalance'),
          value: data.cashBalance,
          icon: Icons.account_balance_wallet,
          color: Colors.amber.shade800,
        ),
        (
          label: context.tr('customerDebt'),
          value: data.customerDebt,
          icon: Icons.people,
          color: Colors.deepOrange,
        ),
        (
          label: context.tr('supplierDue'),
          value: data.supplierDue,
          icon: Icons.local_shipping,
          color: Colors.purple,
        ),
        (
          label: context.tr('lowStock'),
          value: data.lowStockCount,
          icon: Icons.warning_amber,
          color: Colors.red,
        ),
      ];
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(reportRepositoryProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, version) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'الإصدار المثبت: ${version.hasData ? '${version.data!.version} (${version.data!.buildNumber})' : 'جارٍ التحقق...'}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DateRangeFilterBar(
                  value: _range,
                  onChanged: (value) => setState(() => _range = value),
                ),
                SizedBox(
                  width: 132,
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'العملة',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'YER', child: Text('ر. ي')),
                      DropdownMenuItem(value: 'SAR', child: Text('ر. س')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (value) =>
                        setState(() => _currency = value ?? 'YER'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('ملخص الفترة', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 780 ? 3 : 2;
                final width =
                    (constraints.maxWidth - ((count - 1) * 12)) / count;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final tile in tiles)
                      SizedBox(
                        width: width,
                        child: _MetricCard(
                          label: tile.label,
                          value: tile.value,
                          icon: tile.icon,
                          color: tile.color,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SizedBox(
                  height: 210,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مقارنة حركة اليوم',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                            titlesData: const FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            barGroups: [
                              _bar(0, data.salesToday, Colors.teal),
                              _bar(1, data.purchasesToday, Colors.indigo),
                              _bar(2, data.expensesToday, Colors.deepOrange),
                            ],
                          ),
                        ),
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text('المبيعات'),
                          Text('المشتريات'),
                          Text('المصروفات'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  BarChartGroupData _bar(int x, int value, Color color) => BarChartGroupData(
    x: x,
    barRods: [
      BarChartRodData(
        toY: value.toDouble(),
        color: color,
        width: 30,
        borderRadius: BorderRadius.circular(6),
      ),
    ],
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(
            Money(value).format(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}
