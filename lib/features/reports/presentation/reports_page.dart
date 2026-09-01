import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/money.dart';
import '../../../core/models/date_range_filter.dart';
import '../../../core/services/providers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/erp_ui.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  String _type = 'sales';
  String _currency = 'YER';
  DateRangeSelection _range = DateRangeSelection.resolve(DateRangePreset.thisMonth);
  int _refresh = 0;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(reportRepositoryProvider);
    final future = switch (_type) {
      'sales' => repository.salesReport(from: _range.from, to: _range.to, currencyCode: _currency),
      'inventory' => repository.inventoryReport(),
      'trial' => repository.trialBalance(),
      _ => repository.auditLog(),
    };
    return FutureBuilder<List<Map<String, Object?>>>(
      key: ValueKey(_refresh),
      future: future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, Object?>>[];
        final definition = _definition(rows);
        return Column(
          children: [
            ErpPageHeader(
              title: 'التقارير',
              subtitle:
                  'استعرض البيانات محلياً ثم اطبع PDF أو شارك ملف Excel أصلياً.',
              actions: [
                OutlinedButton.icon(
                  onPressed: rows.isEmpty
                      ? null
                      : () => _export('xlsx', definition),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: rows.isEmpty
                      ? null
                      : () => _export('pdf', definition),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
                FilledButton.icon(
                  onPressed: rows.isEmpty
                      ? null
                      : () => _export('print', definition),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('طباعة'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DateRangeFilterBar(value: _range, onChanged: (value) => setState(() => _range = value)),
                  SizedBox(
                    width: 132,
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: const InputDecoration(labelText: 'العملة', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'YER', child: Text('ر. ي')),
                        DropdownMenuItem(value: 'SAR', child: Text('ر. س')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                      ],
                      onChanged: (value) => setState(() => _currency = value ?? 'YER'),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  _chip('sales', 'المبيعات'),
                  _chip('inventory', 'المخزون'),
                  _chip('trial', 'ميزان المراجعة'),
                  _chip('audit', 'سجل التدقيق'),
                ],
              ),
            ),
            Expanded(child: _body(snapshot, definition)),
          ],
        );
      },
    );
  }

  Widget _body(
    AsyncSnapshot<List<Map<String, Object?>>> snapshot,
    _ReportDefinition definition,
  ) {
    if (snapshot.connectionState != ConnectionState.done)
      return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError)
      return ErpErrorState(
        message: 'تعذر تحميل التقرير: ${snapshot.error}',
        onRetry: () => setState(() => _refresh++),
      );
    if ((snapshot.data ?? const []).isEmpty)
      return const EmptyState(
        message: 'لا توجد بيانات لهذا التقرير.',
        icon: Icons.assessment_outlined,
      );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 760) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.primaryContainer,
              ),
              columns: definition.headers
                  .map((header) => DataColumn(label: Text(header)))
                  .toList(),
              rows: definition.rows
                  .map(
                    (row) => DataRow(
                      cells: row.map((value) => DataCell(Text(value))).toList(),
                    ),
                  )
                  .toList(),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, index) => _rowCard(snapshot.data![index]),
        );
      },
    );
  }

  Widget _chip(String type, String label) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _type == type,
      onSelected: (_) => setState(() => _type = type),
    ),
  );

  Widget _rowCard(Map<String, Object?> row) {
    if (_type == 'sales') {
      return ErpSectionCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          title: Text(row['invoice_no'] as String),
          subtitle: Text(
            '${row['invoice_date']} • ${row['customer_name'] ?? 'نقدي'}',
          ),
          trailing: Text(
            Money(row['total_minor'] as int).format(withSymbol: false),
          ),
        ),
      );
    }
    if (_type == 'inventory') {
      return ErpSectionCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          title: Text(row['name_ar'] as String),
          subtitle: Text(
            '${row['warehouse_name']} • ${row['sku']}\nالكمية: ${row['quantity_minor']}',
          ),
          isThreeLine: true,
          trailing: Text(
            Money(
              row['inventory_value_minor'] as int,
            ).format(withSymbol: false),
          ),
        ),
      );
    }
    if (_type == 'trial') {
      return ErpSectionCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          title: Text('${row['code']} — ${row['name_ar']}'),
          subtitle: Text(
            'مدين: ${row['debit_minor']} • دائن: ${row['credit_minor']}',
          ),
        ),
      );
    }
    return ErpSectionCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        title: Text(row['action'] as String),
        subtitle: Text(
          '${row['entity_type']} • ${row['created_at']}\n${row['display_name'] ?? 'النظام'}',
        ),
        isThreeLine: true,
      ),
    );
  }

  _ReportDefinition _definition(List<Map<String, Object?>> data) {
    if (_type == 'sales') {
      return _ReportDefinition(
        'تقرير المبيعات',
        const [
          'رقم الفاتورة',
          'التاريخ',
          'العميل',
          'الإجمالي',
          'المدفوع',
          'المتبقي',
        ],
        data
            .map(
              (row) => [
                '${row['invoice_no']}',
                '${row['invoice_date']}',
                '${row['customer_name'] ?? 'نقدي'}',
                '${row['total_minor']} ${row['currency_code'] ?? ''}',
                '${row['paid_minor']} ${row['currency_code'] ?? ''}',
                '${row['due_minor']} ${row['currency_code'] ?? ''}',
              ],
            )
            .toList(),
      );
    }
    if (_type == 'inventory') {
      return _ReportDefinition(
        'تقرير المخزون',
        const [
          'الرمز',
          'الصنف',
          'المخزن',
          'الكمية',
          'متوسط التكلفة',
          'قيمة المخزون',
        ],
        data
            .map(
              (row) => [
                '${row['sku']}',
                '${row['name_ar']}',
                '${row['warehouse_name']}',
                '${row['quantity_minor']}',
                '${row['average_cost_minor']}',
                '${row['inventory_value_minor']}',
              ],
            )
            .toList(),
      );
    }
    if (_type == 'trial') {
      return _ReportDefinition(
        'ميزان المراجعة',
        const ['الكود', 'الحساب', 'مدين', 'دائن'],
        data
            .map(
              (row) => [
                '${row['code']}',
                '${row['name_ar']}',
                '${row['debit_minor']}',
                '${row['credit_minor']}',
              ],
            )
            .toList(),
      );
    }
    return _ReportDefinition(
      'سجل التدقيق',
      const ['الإجراء', 'الكيان', 'المستخدم', 'التاريخ'],
      data
          .map(
            (row) => [
              '${row['action']}',
              '${row['entity_type']}',
              '${row['display_name'] ?? 'النظام'}',
              '${row['created_at']}',
            ],
          )
          .toList(),
    );
  }

  Future<void> _export(String type, _ReportDefinition definition) async {
    try {
      final organizations = await ref
          .read(databaseProvider)
          .raw
          .query('organizations', limit: 1);
      final organization = organizations.isEmpty
          ? 'المؤسسة'
          : organizations.first['name_ar'] as String;
      final user = ref.read(sessionProvider);
      final service = ref.read(reportExportServiceProvider);
      if (type == 'xlsx') {
        await service.shareXlsx(
          headers: definition.headers,
          rows: definition.rows,
          fileName: definition.title,
          text: definition.title,
          title: definition.title,
          generatedBy: user?.displayName ?? 'النظام',
        );
      } else if (type == 'pdf') {
        await service.sharePdf(
          title: definition.title,
          organizationName: organization,
          headers: definition.headers,
          rows: definition.rows,
          generatedBy: user?.displayName ?? 'النظام',
        );
      } else {
        await service.printReport(
          title: definition.title,
          organizationName: organization,
          headers: definition.headers,
          rows: definition.rows,
          generatedBy: user?.displayName ?? 'النظام',
        );
      }
    } catch (error) {
      if (mounted)
        showAppMessage(context, 'تعذر تصدير التقرير: $error', error: true);
    }
  }
}

class _ReportDefinition {
  const _ReportDefinition(this.title, this.headers, this.rows);
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
}
