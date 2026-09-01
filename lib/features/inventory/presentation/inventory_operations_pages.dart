import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/providers.dart';
import '../../../domain/services/inventory_count_service.dart';
import '../../../domain/services/stock_transfer_service.dart';
import 'barcode_scanner_page.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/erp_ui.dart';

class StockCountsPage extends ConsumerStatefulWidget {
  const StockCountsPage({super.key});

  @override
  ConsumerState<StockCountsPage> createState() => _StockCountsPageState();
}

class _StockCountsPageState extends ConsumerState<StockCountsPage> {
  final _search = TextEditingController();
  String _query = '';
  String? _status;
  int _refresh = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final future = ref
        .watch(inventoryCountProvider)
        .counts(search: _query, status: _status);
    return FutureBuilder<List<Map<String, Object?>>>(
      key: ValueKey(_refresh),
      future: future,
      builder: (context, snapshot) {
        return Column(
          children: [
            ErpPageHeader(
              title: 'الجرد والتسويات',
              subtitle:
                  'أنشئ جلسة جرد واحفظها كمسودة ثم اعتمد الفروقات بحركة مخزون وقيد محاسبي.',
              actions: [
                FilledButton.icon(
                  onPressed: _createCount,
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('جلسة جرد جديدة'),
                ),
              ],
            ),
            ErpSearchFilterBar(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              hint: 'ابحث برقم الجرد أو الملاحظة',
              filterLabel: _status == null
                  ? 'كل الحالات'
                  : 'الحالة: ${_status == 'draft'
                        ? 'مسودة'
                        : _status == 'approved'
                        ? 'معتمد'
                        : 'ملغي'}',
              onFilter: _selectStatus,
            ),
            Expanded(child: _body(snapshot)),
          ],
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<List<Map<String, Object?>>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done)
      return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError)
      return ErpErrorState(
        message: 'تعذر تحميل جلسات الجرد: ${snapshot.error}',
        onRetry: () => setState(() => _refresh++),
      );
    final rows = snapshot.data ?? const [];
    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.fact_check_outlined,
        message: 'لا توجد جلسات جرد مطابقة.',
        action: FilledButton.icon(
          onPressed: _createCount,
          icon: const Icon(Icons.add),
          label: const Text('إنشاء جلسة جرد'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => setState(() => _refresh++),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = rows[index];
          final type = switch (row['count_type']) {
            'monthly' => 'شهري',
            'quarterly' => 'ربع سنوي',
            'yearly' => 'سنوي',
            _ => 'مخصص',
          };
          return ErpSectionCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              leading: const CircleAvatar(
                child: Icon(Icons.inventory_2_outlined),
              ),
              title: Text('${row['document_no']} • جرد $type'),
              subtitle: Text(
                '${row['warehouse_name']} • ${row['lines_count']} صنف • فرق الكميات: ${row['variance_qty_minor']}',
              ),
              trailing: ErpStatusChip(status: row['status'] as String),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StockCountDetailPage(count: row),
                  ),
                );
                if (mounted) setState(() => _refresh++);
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _selectStatus() async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('كل الحالات'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('مسودة'),
              onTap: () => Navigator.pop(context, 'draft'),
            ),
            ListTile(
              title: const Text('معتمد'),
              onTap: () => Navigator.pop(context, 'approved'),
            ),
            ListTile(
              title: const Text('ملغي'),
              onTap: () => Navigator.pop(context, 'cancelled'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => _status = result);
  }

  Future<void> _createCount() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateCountDialog(),
    );
    if (created == true && mounted) setState(() => _refresh++);
  }
}

class _CreateCountDialog extends ConsumerStatefulWidget {
  const _CreateCountDialog();
  @override
  ConsumerState<_CreateCountDialog> createState() => _CreateCountDialogState();
}

class _CreateCountDialogState extends ConsumerState<_CreateCountDialog> {
  String _type = 'custom';
  String? _warehouseId;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_warehouseId == null) {
      showAppMessage(context, 'اختر المخزن أولاً.', error: true);
      return;
    }
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(inventoryCountProvider)
          .createCount(
            user,
            StockCountInput(
              warehouseId: _warehouseId!,
              countType: _type,
              notes: _notes.text,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(masterRepositoryProvider).warehouses();
    return AlertDialog(
      title: const Text('جلسة جرد جديدة'),
      content: FutureBuilder<List<Map<String, Object?>>>(
        future: warehouses,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          final rows = snapshot.data!;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _warehouseId,
                  decoration: const InputDecoration(labelText: 'المخزن'),
                  items: rows
                      .map(
                        (row) => DropdownMenuItem(
                          value: row['id'] as String,
                          child: Text(row['name_ar'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _warehouseId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'نوع الجرد'),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                    DropdownMenuItem(
                      value: 'quarterly',
                      child: Text('ربع سنوي'),
                    ),
                    DropdownMenuItem(value: 'yearly', child: Text('سنوي')),
                    DropdownMenuItem(value: 'custom', child: Text('مخصص')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _type = value ?? 'custom'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'ملاحظات الجرد'),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الإنشاء...' : 'إنشاء مسودة'),
        ),
      ],
    );
  }
}

class StockCountDetailPage extends ConsumerStatefulWidget {
  const StockCountDetailPage({super.key, required this.count});
  final Map<String, Object?> count;

  @override
  ConsumerState<StockCountDetailPage> createState() =>
      _StockCountDetailPageState();
}

class _StockCountDetailPageState extends ConsumerState<StockCountDetailPage> {
  final _search = TextEditingController();
  String _query = '';
  int _refresh = 0;

  bool get _draft => widget.count['status'] == 'draft';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final future = ref
        .watch(inventoryCountProvider)
        .countLines(widget.count['id'] as String, search: _query);
    return Scaffold(
      appBar: AppBar(title: Text('جلسة ${widget.count['document_no']}')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        key: ValueKey(_refresh),
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return ErpErrorState(
              message: 'تعذر تحميل تفاصيل الجرد: ${snapshot.error}',
              onRetry: () => setState(() => _refresh++),
            );
          final rows = snapshot.data ?? const [];
          return Column(
            children: [
              ErpPageHeader(
                title: 'تفاصيل الجرد',
                subtitle:
                    '${widget.count['warehouse_name']} • ${widget.count['lines_count']} صنف',
                actions: [
                  OutlinedButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('مسح باركود'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _print,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('طباعة PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('مشاركة'),
                  ),
                  if (_draft) ...[
                    OutlinedButton.icon(
                      onPressed: _cancel,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('إلغاء المسودة'),
                    ),
                    FilledButton.icon(
                      onPressed: _approve,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('اعتماد الجرد'),
                    ),
                  ],
                ],
              ),
              ErpSearchFilterBar(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                hint: 'ابحث بالاسم أو الرمز أو الباركود',
              ),
              Expanded(
                child: rows.isEmpty
                    ? const EmptyState(message: 'لا توجد أصناف في هذه الجلسة.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _lineCard(rows[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _lineCard(Map<String, Object?> line) {
    final variance = line['variance_qty_minor'] as int;
    final color = variance == 0
        ? Colors.green
        : variance > 0
        ? Colors.blue
        : Colors.red;
    return ErpSectionCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        title: Text(line['name_ar'] as String),
        subtitle: Text(
          'الرمز: ${line['sku']} • الدفتر: ${line['system_qty_minor']} ${line['unit_name']}\nالفعلي: ${line['counted_qty_minor']} • الفرق: ${variance > 0 ? '+' : ''}$variance',
        ),
        isThreeLine: true,
        trailing: _draft
            ? IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'إدخال الكمية الفعلية',
                onPressed: () => _editLine(line),
              )
            : Icon(Icons.circle, size: 12, color: color),
      ),
    );
  }

  Future<void> _editLine(Map<String, Object?> line) async {
    final controller = TextEditingController(
      text: '${line['counted_qty_minor']}',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('الكمية الفعلية: ${line['name_ar']}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'الكمية الفعلية'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (save != true) return;
    final quantity = int.tryParse(controller.text.trim());
    if (quantity == null || quantity < 0) {
      if (mounted)
        showAppMessage(
          context,
          'أدخل كمية صحيحة تساوي صفراً أو أكبر.',
          error: true,
        );
      return;
    }
    final user = ref.read(sessionProvider);
    if (user == null) return;
    try {
      await ref
          .read(inventoryCountProvider)
          .updateCountedQuantity(
            user,
            countId: widget.count['id'] as String,
            lineId: line['id'] as String,
            quantityMinor: quantity,
          );
      if (mounted) setState(() => _refresh++);
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString(), error: true);
    }
  }

  Future<void> _scan() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || barcode == null) return;
    setState(() => _query = barcode);
  }

  Future<void> _print() async {
    await _export(print: true);
  }

  Future<void> _share() async {
    await _export(print: false);
  }

  Future<void> _export({required bool print}) async {
    try {
      final lines = await ref
          .read(inventoryCountProvider)
          .countLines(widget.count['id'] as String);
      final organizations = await ref
          .read(databaseProvider)
          .raw
          .query('organizations', limit: 1);
      final actor = ref.read(sessionProvider);
      final organizationName = organizations.isEmpty
          ? 'المؤسسة'
          : organizations.first['name_ar'] as String;
      final service = ref.read(pdfExportServiceProvider);
      if (print) {
        await service.printStockCount(
          count: widget.count,
          lines: lines,
          organizationName: organizationName,
          generatedBy: actor?.displayName ?? 'النظام',
        );
      } else {
        await service.shareStockCount(
          count: widget.count,
          lines: lines,
          organizationName: organizationName,
          generatedBy: actor?.displayName ?? 'النظام',
        );
      }
    } catch (error) {
      if (mounted)
        showAppMessage(context, 'تعذر إنشاء التقرير: $error', error: true);
    }
  }

  Future<void> _approve() async {
    final confirmed = await showErpConfirmation(
      context,
      title: 'اعتماد الجرد',
      message:
          'سيتم إنشاء تسويات مخزنية وقيود محاسبية للفروقات. لا يمكن تعديل الجرد بعد الاعتماد.',
      confirmLabel: 'اعتماد الجرد',
    );
    if (!confirmed) return;
    final user = ref.read(sessionProvider);
    if (user == null) return;
    try {
      await ref
          .read(inventoryCountProvider)
          .approve(user, widget.count['id'] as String);
      if (mounted) {
        showAppMessage(context, 'تم اعتماد الجرد وإنشاء التسويات المطلوبة.');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString(), error: true);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showErpConfirmation(
      context,
      title: 'إلغاء جلسة الجرد',
      message:
          'سيتم إلغاء المسودة الحالية. لا تؤثر العملية في أرصدة المخزون لأنها غير معتمدة.',
      confirmLabel: 'إلغاء الجلسة',
      destructive: true,
    );
    if (!confirmed) return;
    final user = ref.read(sessionProvider);
    if (user == null) return;
    try {
      await ref
          .read(inventoryCountProvider)
          .cancelDraft(user, widget.count['id'] as String);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString(), error: true);
    }
  }
}

class StockTransfersPage extends ConsumerStatefulWidget {
  const StockTransfersPage({super.key});
  @override
  ConsumerState<StockTransfersPage> createState() => _StockTransfersPageState();
}

class _StockTransfersPageState extends ConsumerState<StockTransfersPage> {
  final _search = TextEditingController();
  String _query = '';
  int _refresh = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final future = ref.watch(stockTransferProvider).list(search: _query);
    return FutureBuilder<List<Map<String, Object?>>>(
      key: ValueKey(_refresh),
      future: future,
      builder: (context, snapshot) {
        return Column(
          children: [
            ErpPageHeader(
              title: 'تحويلات المخزون',
              subtitle:
                  'إرسال الأصناف من مخزن واستلامها في مخزن آخر مع حركة مخزون كاملة.',
              actions: [
                FilledButton.icon(
                  onPressed: _createTransfer,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('تحويل جديد'),
                ),
              ],
            ),
            ErpSearchFilterBar(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              hint: 'ابحث برقم التحويل أو المخزن',
            ),
            Expanded(child: _body(snapshot)),
          ],
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<List<Map<String, Object?>>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done)
      return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError)
      return ErpErrorState(
        message: 'تعذر تحميل التحويلات: ${snapshot.error}',
        onRetry: () => setState(() => _refresh++),
      );
    final rows = snapshot.data ?? const [];
    if (rows.isEmpty)
      return EmptyState(
        message: 'لا توجد تحويلات مخزون.',
        icon: Icons.swap_horiz_outlined,
        action: FilledButton.icon(
          onPressed: _createTransfer,
          icon: const Icon(Icons.add),
          label: const Text('تحويل جديد'),
        ),
      );
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        return ErpSectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            leading: const CircleAvatar(child: Icon(Icons.swap_horiz)),
            title: Text(row['document_no'] as String),
            subtitle: Text(
              '${row['from_warehouse_name']} ← ${row['to_warehouse_name']} • ${row['lines_count']} صنف',
            ),
            trailing: _transferActions(row),
            onTap: () => _showTransferLines(row),
          ),
        );
      },
    );
  }

  Widget _transferActions(Map<String, Object?> row) {
    final status = row['status'] as String;
    if (status == 'draft')
      return IconButton(
        icon: const Icon(Icons.send_outlined),
        tooltip: 'إرسال التحويل',
        onPressed: () => _dispatch(row),
      );
    if (status == 'sent')
      return IconButton(
        icon: const Icon(Icons.inventory_outlined),
        tooltip: 'استلام التحويل',
        onPressed: () => _receive(row),
      );
    return ErpStatusChip(status: status);
  }

  Future<void> _createTransfer() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateTransferDialog(),
    );
    if (created == true && mounted) setState(() => _refresh++);
  }

  Future<void> _showTransferLines(Map<String, Object?> row) async {
    final lines = await ref
        .read(stockTransferProvider)
        .lines(row['id'] as String);
    if (!mounted) return;
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
                'أصناف التحويل ${row['document_no']}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...lines.map(
                (line) => ListTile(
                  title: Text(line['name_ar'] as String),
                  subtitle: Text(
                    '${line['sku']} • ${line['quantity_minor']} ${line['unit_name']}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _dispatch(Map<String, Object?> row) async {
    final confirmed = await showErpConfirmation(
      context,
      title: 'إرسال التحويل',
      message:
          'سيُخصم رصيد الأصناف من المخزن المرسل وتصبح العملية بانتظار الاستلام.',
      confirmLabel: 'إرسال',
    );
    if (!confirmed) return;
    final user = ref.read(sessionProvider);
    if (user == null) return;
    try {
      await ref.read(stockTransferProvider).dispatch(user, row['id'] as String);
      if (mounted) setState(() => _refresh++);
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString(), error: true);
    }
  }

  Future<void> _receive(Map<String, Object?> row) async {
    final confirmed = await showErpConfirmation(
      context,
      title: 'استلام التحويل',
      message:
          'سيُضاف رصيد الأصناف إلى المخزن المستلم ولا يمكن التراجع مباشرة بعد الاستلام.',
      confirmLabel: 'استلام',
    );
    if (!confirmed) return;
    final user = ref.read(sessionProvider);
    if (user == null) return;
    try {
      await ref.read(stockTransferProvider).receive(user, row['id'] as String);
      if (mounted) setState(() => _refresh++);
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString(), error: true);
    }
  }
}

class _TransferDraftLine {
  String? productId;
  String quantity = '1';
  String cost = '0';
}

class _CreateTransferDialog extends ConsumerStatefulWidget {
  const _CreateTransferDialog();
  @override
  ConsumerState<_CreateTransferDialog> createState() =>
      _CreateTransferDialogState();
}

class _CreateTransferDialogState extends ConsumerState<_CreateTransferDialog> {
  String? _from;
  String? _to;
  final _lines = <_TransferDraftLine>[_TransferDraftLine()];
  bool _saving = false;

  Future<void> _save() async {
    if (_from == null || _to == null) {
      showAppMessage(context, 'اختر المخزن المرسل والمستلم.', error: true);
      return;
    }
    final lines = <StockTransferLineInput>[];
    for (final line in _lines) {
      final quantity = int.tryParse(line.quantity.trim());
      final cost = int.tryParse(line.cost.trim()) ?? 0;
      if (line.productId == null ||
          quantity == null ||
          quantity <= 0 ||
          cost < 0) {
        showAppMessage(context, 'أكمل بيانات كل سطر بكمية صحيحة.', error: true);
        return;
      }
      lines.add(
        StockTransferLineInput(
          productId: line.productId!,
          quantityMinor: quantity,
          unitCostMinor: cost,
        ),
      );
    }
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(stockTransferProvider)
          .createDraft(
            user,
            fromWarehouseId: _from!,
            toWarehouseId: _to!,
            lines: lines,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(masterRepositoryProvider).warehouses();
    final products = ref.watch(masterRepositoryProvider).products(limit: 250);
    return AlertDialog(
      title: const Text('تحويل مخزون جديد'),
      content: FutureBuilder<List<List<Map<String, Object?>>>>(
        future: Future.wait([warehouses, products]),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const SizedBox(
              height: 140,
              child: Center(child: CircularProgressIndicator()),
            );
          final warehouseRows = snapshot.data![0];
          final productRows = snapshot.data![1];
          return SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _from,
                    decoration: const InputDecoration(
                      labelText: 'المخزن المرسل',
                    ),
                    items: warehouseRows
                        .map(
                          (row) => DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text(row['name_ar'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _from = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _to,
                    decoration: const InputDecoration(
                      labelText: 'المخزن المستلم',
                    ),
                    items: warehouseRows
                        .map(
                          (row) => DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text(row['name_ar'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _to = value),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'الأصناف المحولة',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < _lines.length; index++) ...[
                    _transferLineEditor(productRows, index),
                    const SizedBox(height: 8),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _lines.add(_TransferDraftLine()),
                            ),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة صنف'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ مسودة'),
        ),
      ],
    );
  }

  Widget _transferLineEditor(List<Map<String, Object?>> products, int index) {
    final line = _lines[index];
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: line.productId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الصنف'),
            items: products
                .map(
                  (row) => DropdownMenuItem(
                    value: row['id'] as String,
                    child: Text(
                      '${row['name_ar']} (${row['sku']})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => line.productId = value),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 76,
          child: TextFormField(
            initialValue: line.quantity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'كمية'),
            onChanged: (value) => line.quantity = value,
          ),
        ),
        const SizedBox(width: 8),
        if (_lines.length > 1)
          IconButton(
            onPressed: _saving
                ? null
                : () => setState(() => _lines.removeAt(index)),
            icon: const Icon(Icons.remove_circle_outline),
          ),
      ],
    );
  }
}
