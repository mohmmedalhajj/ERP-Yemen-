import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/providers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/erp_ui.dart';

class ReturnsPage extends ConsumerStatefulWidget {
  const ReturnsPage({super.key, required this.kind});
  final String kind; // sale | purchase

  @override
  ConsumerState<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends ConsumerState<ReturnsPage> {
  final _search = TextEditingController();
  String _query = '';
  int _refresh = 0;

  bool get _sale => widget.kind == 'sale';
  String get _table => _sale ? 'sales_invoices' : 'purchase_invoices';
  String get _partyTable => _sale ? 'customers' : 'suppliers';
  String get _partyColumn => _sale ? 'customer_id' : 'supplier_id';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, Object?>>> _originalInvoices() {
    final pattern = '%${_query.trim()}%';
    return ref
        .read(databaseProvider)
        .raw
        .rawQuery(
          '''SELECT i.*, p.name AS party_name
         FROM $_table i
         LEFT JOIN $_partyTable p ON p.id = i.$_partyColumn
         WHERE i.status = 'posted' AND i.original_invoice_id IS NULL
           AND (i.invoice_no LIKE ? OR p.name LIKE ?)
         ORDER BY i.invoice_date DESC, i.invoice_no DESC LIMIT 100''',
          [pattern, pattern],
        );
  }

  Future<List<Map<String, Object?>>> _returnInvoices() => ref
      .read(databaseProvider)
      .raw
      .rawQuery('''SELECT i.*, o.invoice_no AS original_no, p.name AS party_name
       FROM $_table i
       LEFT JOIN $_table o ON o.id = i.original_invoice_id
       LEFT JOIN $_partyTable p ON p.id = i.$_partyColumn
       WHERE i.original_invoice_id IS NOT NULL
       ORDER BY i.invoice_date DESC, i.invoice_no DESC LIMIT 100''');

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        ErpPageHeader(
          title: _sale ? 'مرتجعات المبيعات' : 'مرتجعات المشتريات',
          subtitle:
              'يُنشأ المرتجع من فاتورة أصلية مرحلة فقط، ويُحدّث المخزون والصندوق والقيود تلقائياً.',
        ),
        TabBar(
          tabs: [
            Tab(text: _sale ? 'فواتير المبيعات' : 'فواتير المشتريات'),
            const Tab(text: 'المرتجعات المرحلة'),
          ],
        ),
        Expanded(child: TabBarView(children: [_originalsTab(), _returnsTab()])),
      ],
    ),
  );

  Widget _originalsTab() => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('o$_refresh'),
    future: _originalInvoices(),
    builder: (context, snapshot) => Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 10),
          child: ErpSearchFilterBar(
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            hint: 'ابحث برقم الفاتورة أو الطرف',
          ),
        ),
        Expanded(child: _invoiceList(snapshot)),
      ],
    ),
  );

  Widget _returnsTab() => FutureBuilder<List<Map<String, Object?>>>(
    key: ValueKey('r$_refresh'),
    future: _returnInvoices(),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError)
        return ErpErrorState(
          message: 'تعذر تحميل المرتجعات: ${snapshot.error}',
          onRetry: () => setState(() => _refresh++),
        );
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty)
        return const EmptyState(
          message: 'لا توجد مرتجعات مرحلة.',
          icon: Icons.assignment_return_outlined,
        );
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = rows[index];
          return ErpSectionCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.assignment_return_outlined),
              ),
              title: Text(row['invoice_no'] as String),
              subtitle: Text(
                'الأصل: ${row['original_no']} • ${row['party_name'] ?? 'دون طرف'}\n${row['invoice_date']} • الإجمالي: ${row['total_minor']}',
              ),
              isThreeLine: true,
              trailing: const ErpStatusChip(status: 'posted'),
            ),
          );
        },
      );
    },
  );

  Widget _invoiceList(AsyncSnapshot<List<Map<String, Object?>>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done)
      return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError)
      return ErpErrorState(
        message: 'تعذر تحميل الفواتير: ${snapshot.error}',
        onRetry: () => setState(() => _refresh++),
      );
    final rows = snapshot.data ?? const [];
    if (rows.isEmpty)
      return const EmptyState(
        message: 'لا توجد فواتير مرحلة مطابقة.',
        icon: Icons.receipt_long_outlined,
      );
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        return ErpSectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.receipt_long_outlined),
            ),
            title: Text(row['invoice_no'] as String),
            subtitle: Text(
              '${row['party_name'] ?? 'دون طرف'} • ${row['invoice_date']}\nإجمالي الفاتورة: ${row['total_minor']}',
            ),
            isThreeLine: true,
            trailing: FilledButton.tonalIcon(
              onPressed: () => _selectLine(row),
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('إرجاع'),
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectLine(Map<String, Object?> invoice) async {
    final lineRows = await ref.read(databaseProvider).raw.rawQuery(
      _sale
          ? '''SELECT l.*, p.name_ar, p.sku, (l.quantity_minor - l.returned_qty_minor) AS returnable_qty_minor
              FROM sales_lines l JOIN products p ON p.id = l.product_id
              WHERE l.invoice_id = ? AND (l.quantity_minor - l.returned_qty_minor) > 0'''
          : '''SELECT l.*, p.name_ar, p.sku, l.quantity_minor AS returnable_qty_minor
              FROM purchase_lines l JOIN products p ON p.id = l.product_id
              WHERE l.invoice_id = ?''',
      [invoice['id']],
    );
    if (!mounted) return;
    if (lineRows.isEmpty) {
      showAppMessage(
        context,
        'لا توجد كمية متبقية قابلة للإرجاع في هذه الفاتورة.',
        error: true,
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'اختر الصنف المرتجع من ${invoice['invoice_no']}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...lineRows.map(
                (line) => ListTile(
                  title: Text(line['name_ar'] as String),
                  subtitle: Text(
                    '${line['sku']} • الكمية المتاحة للإرجاع: ${line['returnable_qty_minor']}',
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () {
                    Navigator.pop(context);
                    _quantityDialog(invoice, line);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _quantityDialog(
    Map<String, Object?> invoice,
    Map<String, Object?> line,
  ) async {
    final controller = TextEditingController(text: '1');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('إرجاع: ${line['name_ar']}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'الكمية (الحد: ${line['returnable_qty_minor']})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ترحيل المرتجع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final quantity = int.tryParse(controller.text.trim());
    final allowed = line['returnable_qty_minor'] as int;
    if (quantity == null || quantity <= 0 || quantity > allowed) {
      if (mounted)
        showAppMessage(
          context,
          'أدخل كمية صحيحة لا تتجاوز الحد المتاح.',
          error: true,
        );
      return;
    }
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    try {
      if (_sale) {
        await ref
            .read(returnPostingProvider)
            .postSaleReturn(
              actor: actor,
              originalInvoiceId: invoice['id'] as String,
              originalLineId: line['id'] as String,
              quantityMinor: quantity,
            );
      } else {
        await ref
            .read(returnPostingProvider)
            .postPurchaseReturn(
              actor: actor,
              originalInvoiceId: invoice['id'] as String,
              originalLineId: line['id'] as String,
              quantityMinor: quantity,
            );
      }
      if (mounted) {
        showAppMessage(context, 'تم ترحيل المرتجع بنجاح.');
        setState(() => _refresh++);
      }
    } catch (error) {
      if (mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    }
  }
}
