import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/money.dart';
import '../../../core/services/providers.dart';
import '../../../domain/services/invoice_posting_service.dart';
import '../../../core/services/invoice_document_service.dart';
import '../../../core/services/thermal_printer_service.dart';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../inventory/presentation/barcode_scanner_page.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/erp_ui.dart';

class TransactionPage extends ConsumerStatefulWidget {
  const TransactionPage({super.key, required this.kind});
  final String kind;

  @override
  ConsumerState<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends ConsumerState<TransactionPage> {
  final List<_CartLine> _lines = [];
  String? _partyId;
  String _currencyCode = 'YER';
  int _ratePpm = 1000000;
  bool _posting = false;
  final _paid = TextEditingController();

  bool get _isSale => widget.kind == 'sale';

  @override
  void dispose() {
    _paid.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  int get _total => _lines.fold(0, (sum, line) => sum + line.total);

  @override
  Widget build(BuildContext context) {
    final master = ref.watch(masterRepositoryProvider);
    return FutureBuilder<List<List<Map<String, Object?>>>>(
      future: Future.wait([
        master.products(limit: 200),
        _isSale ? master.customers() : master.suppliers(),
        ref.read(referenceDataRepositoryProvider).list('currencies'),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return EmptyState(
            message: '${context.tr('error')}: ${snapshot.error}',
          );
        final products = snapshot.data![0];
        final parties = snapshot.data![1];
        final currencies = snapshot.data![2];
        return Column(
          children: [
            ErpPageHeader(
              title: _isSale ? 'المبيعات ونقطة البيع' : 'المشتريات',
              subtitle: _isSale
                  ? 'أنشئ فاتورة ثم راجع المستندات المرحلة والمرتجعات من القائمة.'
                  : 'سجل المشتريات مع الترحيل الفوري للمخزون والقيود.',
              actions: [
                OutlinedButton.icon(
                  onPressed: _scanProduct,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('مسح باركود'),
                ),
                OutlinedButton.icon(
                  onPressed: _showHistory,
                  icon: const Icon(Icons.history),
                  label: const Text('المستندات المرحلة'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: DropdownButtonFormField<String>(
                initialValue: _partyId,
                decoration: InputDecoration(
                  labelText: _isSale
                      ? context.tr('customer')
                      : context.tr('supplier'),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(_isSale ? 'عميل نقدي' : 'غير محدد'),
                  ),
                  ...parties.map(
                    (party) => DropdownMenuItem(
                      value: party['id'] as String,
                      child: Text(party['name'] as String),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _partyId = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: DropdownButtonFormField<String>(
                initialValue: _currencyCode,
                decoration: const InputDecoration(
                  labelText: 'عملة العملية',
                  prefixIcon: Icon(Icons.currency_exchange),
                ),
                items: currencies
                    .where(
                      (item) => item['active'] == 1 || item['active'] == true,
                    )
                    .map(
                      (item) => DropdownMenuItem(
                        value: item['code'] as String,
                        child: Text('${item['code']} — ${item['name_ar']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final row = currencies.firstWhere(
                    (item) => item['code'] == value,
                    orElse: () => {
                      'code': value,
                      'rate_ppm': value == 'YER' ? 1000000 : null,
                    },
                  );
                  final rate = row['rate_ppm'];
                  if (rate is! int || rate <= 0) {
                    showAppMessage(
                      context,
                      'لا يوجد سعر صرف محفوظ لهذه العملة.',
                      error: true,
                    );
                    return;
                  }
                  setState(() {
                    _currencyCode = value;
                    _ratePpm = rate;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                initialValue: null,
                decoration: InputDecoration(
                  labelText: context.tr('product'),
                  prefixIcon: const Icon(Icons.add_shopping_cart),
                ),
                items: products
                    .map(
                      (product) => DropdownMenuItem(
                        value: product['id'] as String,
                        child: Text(
                          '${product['name_ar']} (${product['sku']})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  final product = products.firstWhere(
                    (item) => item['id'] == id,
                  );
                  _addProduct(product);
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _lines.isEmpty
                  ? EmptyState(
                      message:
                          'أضف الأصناف لبدء ${_isSale ? 'البيع' : 'الشراء'}',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _lines.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _lineCard(_lines[index]),
                    ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: const [
                    BoxShadow(color: Color(0x1A000000), blurRadius: 8),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.tr('total')),
                        Text(
                          Money(_total, currencyCode: _currencyCode).format(),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _paid,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            '${context.tr('paid')} (اتركه فارغاً للدفع الكامل)',
                        prefixIcon: const Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _posting || _lines.isEmpty ? null : _post,
                        icon: _posting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _isSale
                              ? context.tr('postSale')
                              : context.tr('postPurchase'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _lineCard(_CartLine line) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  line.dispose();
                  _lines.remove(line);
                }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: line.quantity,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.tr('quantity'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: line.price,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText:
                        '${_isSale ? context.tr('price') : 'تكلفة الوحدة'} ($_currencyCode)',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(Money(line.total).format(withSymbol: false)),
            ],
          ),
        ],
      ),
    ),
  );

  void _addProduct(Map<String, Object?> product) {
    if (_lines.any((line) => line.productId == product['id'])) return;
    final productCurrency =
        (product['purchase_currency_code'] as String? ?? 'YER').toUpperCase();
    final productRate =
        (product['purchase_rate_ppm'] as num?)?.toInt() ?? 1000000;
    if (!_isSale) {
      if (productRate <= 0) {
        showAppMessage(
          context,
          'سعر صرف عملة شراء المنتج غير صالح.',
          error: true,
        );
        return;
      }
      if (_lines.isEmpty && productCurrency != _currencyCode) {
        setState(() {
          _currencyCode = productCurrency;
          _ratePpm = productRate;
        });
      } else if (_lines.isNotEmpty && productCurrency != _currencyCode) {
        showAppMessage(
          context,
          'لا يمكن خلط عملات مختلفة في فاتورة شراء واحدة.',
          error: true,
        );
        return;
      }
    }
    final price = _isSale
        ? (product['retail_price_minor'] as int? ?? 0)
        : (product['purchase_price_minor'] as int? ?? 0);
    setState(
      () => _lines.add(
        _CartLine(
          productId: product['id'] as String,
          unitId: product['stock_unit_id'] as String,
          name: product['name_ar'] as String,
          price: price,
        ),
      ),
    );
  }

  Future<void> _scanProduct() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || barcode == null) return;
    final product = await ref
        .read(masterRepositoryProvider)
        .productByBarcode(barcode);
    if (!mounted) return;
    if (product == null) {
      showAppMessage(
        context,
        'لم يتم العثور على صنف بهذا الباركود.',
        error: true,
      );
      return;
    }
    if (_lines.any((line) => line.productId == product['id'])) {
      showAppMessage(context, 'الصنف موجود بالفعل في الفاتورة.');
      return;
    }
    _addProduct(product);
  }

  Future<void> _showHistory() async {
    final table = _isSale ? 'sales_invoices' : 'purchase_invoices';
    final partyTable = _isSale ? 'customers' : 'suppliers';
    final partyColumn = _isSale ? 'customer_id' : 'supplier_id';
    final rows = await ref.read(databaseProvider).raw.rawQuery(
      '''SELECT i.*, p.name AS party_name
         FROM $table i LEFT JOIN $partyTable p ON p.id = i.$partyColumn
         ORDER BY i.invoice_date DESC, i.invoice_no DESC LIMIT 100''',
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .7,
          minChildSize: .35,
          maxChildSize: .95,
          builder: (context, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _isSale ? 'المبيعات المرحلة' : 'المشتريات المرحلة',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const EmptyState(
                        message: 'لا توجد مستندات مرحلة.',
                        icon: Icons.receipt_long_outlined,
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final isReturn = row['original_invoice_id'] != null;
                          return ErpSectionCard(
                            padding: EdgeInsets.zero,
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  isReturn
                                      ? Icons.assignment_return_outlined
                                      : Icons.receipt_long_outlined,
                                ),
                              ),
                              title: Text(row['invoice_no'] as String),
                              subtitle: Text(
                                '${row['party_name'] ?? 'نقدي'} • ${row['invoice_date']}\nالإجمالي: ${row['total_minor']} • المدفوع: ${row['paid_minor']}',
                              ),
                              isThreeLine: true,
                              trailing: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ErpStatusChip(
                                    status: row['status'] as String,
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (action) =>
                                        _invoiceOutput(row, action),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'print_a4',
                                        child: Text('طباعة A4'),
                                      ),
                                      PopupMenuItem(
                                        value: 'print_80',
                                        child: Text('طباعة حرارية 80mm'),
                                      ),
                                      PopupMenuItem(
                                        value: 'print_58',
                                        child: Text('طباعة حرارية 58mm'),
                                      ),
                                      PopupMenuItem(
                                        value: 'bt_80',
                                        child: Text('Bluetooth 80mm'),
                                      ),
                                      PopupMenuItem(
                                        value: 'bt_58',
                                        child: Text('Bluetooth 58mm'),
                                      ),
                                      PopupMenuItem(
                                        value: 'share_pdf',
                                        child: Text('مشاركة PDF'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _invoiceOutput(Map<String, Object?> row, String action) async {
    if (action == 'bt_80' || action == 'bt_58') {
      await _bluetoothOutput(row, action == 'bt_58' ? 58 : 80);
      return;
    }
    try {
      final service = ref.read(invoiceDocumentServiceProvider);
      final format = switch (action) {
        'print_80' => InvoicePrintFormat.thermal80,
        'print_58' => InvoicePrintFormat.thermal58,
        _ => InvoicePrintFormat.a4,
      };
      if (action == 'share_pdf') {
        await service.share(
          kind: _isSale ? 'sale' : 'purchase',
          invoiceId: row['id'] as String,
          format: format,
        );
      } else {
        await service.print(
          kind: _isSale ? 'sale' : 'purchase',
          invoiceId: row['id'] as String,
          format: format,
        );
      }
    } catch (error) {
      if (mounted)
        showAppMessage(context, 'تعذرت طباعة الفاتورة: $error', error: true);
    }
  }

  Future<void> _bluetoothOutput(
    Map<String, Object?> row,
    int millimeters,
  ) async {
    try {
      final service = ThermalPrinterService();
      final devices = await service.discover();
      if (!mounted) {
        await service.dispose();
        return;
      }
      if (devices.isEmpty) {
        showAppMessage(
          context,
          'لم يتم العثور على طابعة Bluetooth.',
          error: true,
        );
        await service.dispose();
        return;
      }
      final device = await showModalBottomSheet<BluetoothInfo>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('اختر الطابعة')),
              for (final item in devices)
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: Text(item.name),
                  subtitle: Text(item.macAdress),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
      );
      if (device == null) {
        await service.dispose();
        return;
      }
      final table = _isSale ? 'sales_lines' : 'purchase_lines';
      final lines = await ref
          .read(databaseProvider)
          .raw
          .rawQuery(
            '''SELECT p.name_ar, l.quantity_minor, l.line_total_minor FROM $table l JOIN products p ON p.id = l.product_id WHERE l.invoice_id = ? ORDER BY l.id''',
            [row['id']],
          );
      await service.printReceipt(
        device: device,
        title:
            '${_isSale ? 'فاتورة بيع' : 'فاتورة شراء'} — ${row['invoice_no']}',
        lines: [
          for (final line in lines)
            (
              name: line['name_ar'] as String,
              quantity: '${line['quantity_minor']}',
              total: '${line['line_total_minor']}',
            ),
        ],
        total: '${row['total_minor']}',
        millimeters: millimeters,
      );
      await service.saveDefault(device);
      if (mounted) showAppMessage(context, 'تم إرسال الفاتورة إلى الطابعة.');
      await service.dispose();
    } catch (error) {
      if (mounted)
        showAppMessage(context, 'تعذرت الطباعة الحرارية: $error', error: true);
    }
  }

  Future<void> _post() async {
    final actor = ref.read(sessionProvider);
    if (actor == null ||
        actor.branchId == null ||
        actor.warehouseId == null ||
        actor.cashboxId == null) {
      showAppMessage(
        context,
        'لا توجد صلاحيات أو إعدادات فرع ومخزن وصندوق للجلسة',
        error: true,
      );
      return;
    }
    final invalid = _lines.any(
      (line) => line.quantityValue <= 0 || line.priceValue < 0,
    );
    if (invalid) {
      showAppMessage(
        context,
        'تحقق من الكميات والأسعار قبل الترحيل',
        error: true,
      );
      return;
    }
    final paid = _paid.text.trim().isEmpty
        ? _total
        : int.tryParse(_paid.text.trim()) ?? -1;
    if (paid < 0 || paid > _total) {
      showAppMessage(context, 'قيمة المدفوع غير صالحة', error: true);
      return;
    }
    if (paid < _total && _partyId == null) {
      showAppMessage(
        context,
        'حدد ${_isSale ? 'عميلاً' : 'مورداً'} عند وجود رصيد آجل',
        error: true,
      );
      return;
    }
    setState(() => _posting = true);
    try {
      final lines = _lines
          .map(
            (line) => InvoiceLineInput(
              productId: line.productId,
              unitId: line.unitId,
              quantityMinor: line.quantityValue,
              conversionFactor: 1,
              unitAmountMinor: line.priceValue,
            ),
          )
          .toList();
      final document = _isSale
          ? await ref
                .read(invoicePostingProvider)
                .postSale(
                  actor: actor,
                  input: SalePostingInput(
                    branchId: actor.branchId!,
                    warehouseId: actor.warehouseId!,
                    cashboxId: actor.cashboxId!,
                    customerId: _partyId,
                    invoiceDate: DateTime.now(),
                    currencyCode: _currencyCode,
                    ratePpm: _ratePpm,
                    paidMinor: paid,
                    lines: lines,
                  ),
                )
          : await ref
                .read(invoicePostingProvider)
                .postPurchase(
                  actor: actor,
                  input: PurchasePostingInput(
                    branchId: actor.branchId!,
                    warehouseId: actor.warehouseId!,
                    cashboxId: actor.cashboxId!,
                    supplierId: _partyId,
                    invoiceDate: DateTime.now(),
                    currencyCode: _currencyCode,
                    ratePpm: _ratePpm,
                    paidMinor: paid,
                    lines: lines,
                  ),
                );
      if (mounted) {
        showAppMessage(context, 'تم ترحيل المستند ${document.number}');
        setState(() {
          for (final line in _lines) {
            line.dispose();
          }
          _lines.clear();
          _paid.clear();
          _partyId = null;
          _currencyCode = 'YER';
          _ratePpm = 1000000;
        });
      }
    } catch (error) {
      if (mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }
}

class _CartLine {
  _CartLine({
    required this.productId,
    required this.unitId,
    required this.name,
    required int price,
  }) : price = TextEditingController(text: '$price'),
       quantity = TextEditingController(text: '1');
  final String productId;
  final String unitId;
  final String name;
  final TextEditingController price;
  final TextEditingController quantity;
  int get priceValue => int.tryParse(price.text.trim()) ?? -1;
  int get quantityValue => int.tryParse(quantity.text.trim()) ?? 0;
  int get total => quantityValue * (priceValue < 0 ? 0 : priceValue);
  void dispose() {
    price.dispose();
    quantity.dispose();
  }
}
