import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/security.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/models/money.dart';
import '../../../core/services/providers.dart';
import '../../../data/repositories/master_repository.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/erp_ui.dart';

class MasterPage extends ConsumerStatefulWidget {
  const MasterPage({super.key, required this.type});
  final String type;

  @override
  ConsumerState<MasterPage> createState() => _MasterPageState();
}

class _MasterPageState extends ConsumerState<MasterPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == 'products'
        ? context.tr('products')
        : context.tr(widget.type);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: '${context.tr('search')} $title',
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(context.tr('add')),
              ),
            ],
          ),
        ),
        Expanded(child: _list()),
      ],
    );
  }

  Widget _list() {
    final repository = ref.watch(masterRepositoryProvider);
    final future = widget.type == 'products'
        ? repository.products(search: _query)
        : widget.type == 'customers'
        ? repository.customers(search: _query)
        : repository.suppliers(search: _query);
    return FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return EmptyState(
            message: '${context.tr('error')}: ${snapshot.error}',
          );
        final rows = snapshot.data!;
        if (rows.isEmpty) return EmptyState(message: context.tr('empty'));
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            if (widget.type == 'products') {
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text((row['name_ar'] as String).substring(0, 1)),
                  ),
                  title: Text(row['name_ar'] as String),
                  subtitle: Text(
                    '${row['sku']} • ${row['unit_name'] ?? ''}\n${context.tr('quantity')}: ${row['stock_quantity_minor'] ?? 0}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Money(
                          (row['retail_price_minor'] as int?) ?? 0,
                        ).format(withSymbol: false),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') _edit(row);
                          if (action == 'archive') _archive(row);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('تعديل')),
                          PopupMenuItem(value: 'archive', child: Text('أرشفة')),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    widget.type == 'customers'
                        ? Icons.person_outline
                        : Icons.local_shipping_outlined,
                  ),
                ),
                title: Text(row['name'] as String),
                subtitle: Text(
                  '${row['code']} ${row['phone'] == null ? '' : '• ${row['phone']}'}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') _edit(row);
                    if (action == 'archive') _archive(row);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'archive', child: Text('أرشفة')),
                  ],
                ),
                onTap: () => _edit(row),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _add() async {
    final saved = widget.type == 'products'
        ? await showDialog<bool>(
            context: context,
            builder: (_) => const _ProductDialog(),
          )
        : await showDialog<bool>(
            context: context,
            builder: (_) => _PartyDialog(type: widget.type),
          );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _edit(Map<String, Object?> row) async {
    final saved = widget.type == 'products'
        ? await showDialog<bool>(
            context: context,
            builder: (_) => _ProductDialog(initial: row),
          )
        : await showDialog<bool>(
            context: context,
            builder: (_) => _PartyDialog(type: widget.type, initial: row),
          );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _archive(Map<String, Object?> row) async {
    final entity = widget.type == 'products'
        ? 'الصنف'
        : widget.type == 'customers'
        ? 'العميل'
        : 'المورد';
    final name = widget.type == 'products' ? row['name_ar'] : row['name'];
    final confirmed = await showErpConfirmation(
      context,
      title: 'أرشفة $entity',
      message:
          'سيتم إيقاف «$name» عن الاستخدام الجديد مع الاحتفاظ بسجلاته التاريخية. لا تُحذف الحركات المرتبطة به.',
      confirmLabel: 'أرشفة',
      destructive: true,
    );
    if (!confirmed) return;
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    try {
      await ref
          .read(masterRepositoryProvider)
          .archive(
            actor,
            widget.type,
            widget.type == 'products'
                ? 'product'
                : widget.type == 'customers'
                ? 'customer'
                : 'supplier',
            row['id'] as String,
            widget.type == 'products'
                ? Permissions.productsManage
                : widget.type == 'customers'
                ? Permissions.customersManage
                : Permissions.suppliersManage,
          );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString(), error: true);
    }
  }
}

class _ProductDialog extends ConsumerStatefulWidget {
  const _ProductDialog({this.initial});
  final Map<String, Object?>? initial;
  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog> {
  final _form = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _price = TextEditingController(text: '0');
  final _purchasePrice = TextEditingController(text: '0');
  final _reorder = TextEditingController(text: '0');
  final _minimum = TextEditingController(text: '0');
  final _maximum = TextEditingController();
  String? _categoryId;
  String? _unitId;
  String? _taxId;
  bool _allowNegative = false;
  bool _batchEnabled = false;
  bool _expiryEnabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    if (item != null) {
      _sku.text = item['sku'] as String? ?? '';
      _name.text = item['name_ar'] as String? ?? '';
      _price.text = '${item['retail_price_minor'] ?? 0}';
      _purchasePrice.text = '${item['purchase_price_minor'] ?? 0}';
      _reorder.text = '${item['reorder_point_minor'] ?? 0}';
      _minimum.text = '${item['min_stock_minor'] ?? 0}';
      _maximum.text = item['max_stock_minor']?.toString() ?? '';
      _categoryId = item['category_id'] as String?;
      _unitId = item['stock_unit_id'] as String?;
      _taxId = item['default_tax_id'] as String?;
      _allowNegative = item['allow_negative_stock'] == 1;
      _batchEnabled = item['batch_enabled'] == 1;
      _expiryEnabled = item['expiry_enabled'] == 1;
    }
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _price.dispose();
    _purchasePrice.dispose();
    _reorder.dispose();
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final actor = ref.read(sessionProvider);
      if (actor == null) throw StateError('انتهت الجلسة');
      await ref
          .read(masterRepositoryProvider)
          .saveProduct(
            actor,
            ProductInput(
              id: widget.initial?['id'] as String?,
              sku: _sku.text,
              nameAr: _name.text,
              categoryId: _categoryId,
              stockUnitId: _unitId ?? 'unit-piece',
              purchaseUnitId: _unitId,
              salesUnitId: _unitId,
              defaultTaxId: _taxId,
              retailPriceMinor: int.tryParse(_price.text.trim()) ?? 0,
              purchasePriceMinor: int.tryParse(_purchasePrice.text.trim()) ?? 0,
              reorderPointMinor: int.tryParse(_reorder.text.trim()) ?? 0,
              minStockMinor: int.tryParse(_minimum.text.trim()) ?? 0,
              maxStockMinor: _maximum.text.trim().isEmpty
                  ? null
                  : int.tryParse(_maximum.text.trim()),
              allowNegativeStock: _allowNegative,
              batchEnabled: _batchEnabled,
              expiryEnabled: _expiryEnabled,
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? context.tr('newProduct') : 'تعديل الصنف',
    ),
    content: FutureBuilder<List<List<Map<String, Object?>>>>(
      future: Future.wait([
        ref.watch(referenceDataRepositoryProvider).list('categories'),
        ref.watch(referenceDataRepositoryProvider).list('units'),
        ref.watch(referenceDataRepositoryProvider).list('taxes'),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final categories = snapshot.data![0];
        final units = snapshot.data![1];
        final taxes = snapshot.data![2];
        return SizedBox(
          width: 460,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _sku,
                    decoration: InputDecoration(labelText: context.tr('sku')),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: context.tr('nameArabic'),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'التصنيف'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('دون تصنيف'),
                      ),
                      ...categories.map(
                        (row) => DropdownMenuItem(
                          value: row['id'] as String,
                          child: Text(row['name_ar'] as String),
                        ),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _categoryId = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _unitId,
                    decoration: const InputDecoration(
                      labelText: 'وحدة المخزون',
                    ),
                    items: units
                        .map(
                          (row) => DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text('${row['name_ar']} (${row['code']})'),
                          ),
                        )
                        .toList(),
                    validator: (_) =>
                        _unitId == null ? 'اختر وحدة للصنف' : null,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _unitId = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _taxId,
                    decoration: const InputDecoration(
                      labelText: 'الضريبة الافتراضية',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('دون ضريبة'),
                      ),
                      ...taxes.map(
                        (row) => DropdownMenuItem(
                          value: row['id'] as String,
                          child: Text(
                            '${row['name_ar']} (${((row['rate_basis_points'] as int) / 100).toStringAsFixed(2)}%)',
                          ),
                        ),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _taxId = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _price,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'سعر البيع',
                          ),
                          validator: _nonNegative,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'سعر الشراء',
                          ),
                          validator: _nonNegative,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _reorder,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'حد إعادة الطلب',
                          ),
                          validator: _nonNegative,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _minimum,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'الحد الأدنى',
                          ),
                          validator: _nonNegative,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _maximum,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الحد الأقصى (اختياري)',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? null
                        : _nonNegative(value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allowNegative,
                    title: const Text('السماح برصيد سالب لهذا الصنف'),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _allowNegative = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _batchEnabled,
                    title: const Text('تتبع الدفعات'),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _batchEnabled = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _expiryEnabled,
                    title: const Text('تتبع تاريخ الصلاحية'),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _expiryEnabled = value),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text(context.tr('cancel')),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(context.tr('save')),
      ),
    ],
  );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? context.tr('required') : null;
  String? _nonNegative(String? value) => (int.tryParse(value ?? '') ?? -1) >= 0
      ? null
      : context.tr('invalidAmount');
}

class _PartyDialog extends ConsumerStatefulWidget {
  const _PartyDialog({required this.type, this.initial});
  final String type;
  final Map<String, Object?>? initial;
  @override
  ConsumerState<_PartyDialog> createState() => _PartyDialogState();
}

class _PartyDialogState extends ConsumerState<_PartyDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    if (item != null) {
      _name.text = item['name'] as String? ?? '';
      _phone.text = item['phone'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final actor = ref.read(sessionProvider);
      if (actor == null) throw StateError('انتهت الجلسة');
      final input = PartyInput(
        id: widget.initial?['id'] as String?,
        name: _name.text,
        phone: _phone.text,
      );
      if (widget.type == 'customers') {
        await ref.read(masterRepositoryProvider).saveCustomer(actor, input);
      } else {
        await ref.read(masterRepositoryProvider).saveSupplier(actor, input);
      }
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial != null
          ? 'تعديل ${widget.type == 'customers' ? 'العميل' : 'المورد'}'
          : (widget.type == 'customers'
                ? context.tr('newCustomer')
                : context.tr('newSupplier')),
    ),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: context.tr('nameArabic')),
            validator: (value) => value == null || value.trim().isEmpty
                ? context.tr('required')
                : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'الهاتف'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text(context.tr('cancel')),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(context.tr('save')),
      ),
    ],
  );
}
