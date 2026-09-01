import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/providers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/erp_ui.dart';

class ReferenceDataPage extends ConsumerStatefulWidget {
  const ReferenceDataPage({super.key});

  @override
  ConsumerState<ReferenceDataPage> createState() => _ReferenceDataPageState();
}

class _ReferenceDataPageState extends ConsumerState<ReferenceDataPage> {
  final _search = TextEditingController();
  String _type = 'branches';
  String _query = '';
  int _refresh = 0;

  static const _types = <_ReferenceType>[
    _ReferenceType('branches', 'الفروع', Icons.account_tree_outlined),
    _ReferenceType('warehouses', 'المخازن', Icons.warehouse_outlined),
    _ReferenceType(
      'cashboxes',
      'الصناديق والبنوك',
      Icons.account_balance_wallet_outlined,
    ),
    _ReferenceType(
      'currencies',
      'العملات وأسعار الصرف',
      Icons.currency_exchange_outlined,
    ),
    _ReferenceType('taxes', 'الضرائب', Icons.percent_outlined),
    _ReferenceType('categories', 'التصنيفات', Icons.category_outlined),
    _ReferenceType('units', 'الوحدات', Icons.straighten_outlined),
    _ReferenceType(
      'fiscal_periods',
      'الفترات المالية',
      Icons.calendar_month_outlined,
    ),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  _ReferenceType get _current =>
      _types.firstWhere((type) => type.table == _type);

  @override
  Widget build(BuildContext context) {
    final future = ref
        .watch(referenceDataRepositoryProvider)
        .list(_type, search: _query);
    return FutureBuilder<List<Map<String, Object?>>>(
      key: ValueKey('$_type-$_query-$_refresh'),
      future: future,
      builder: (context, snapshot) => Column(
        children: [
          ErpPageHeader(
            title: 'البيانات المرجعية',
            subtitle: 'إدارة الفروع والمخازن والعملات والضرائب والوحدات والفترات. تُحفظ التغييرات محلياً مع سجل تدقيق.',
            actions: [
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text('إضافة ${_current.label}'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'نوع البيانات المرجعية',
                prefixIcon: Icon(Icons.tune_outlined),
              ),
              items: _types
                  .map(
                    (type) => DropdownMenuItem(
                      value: type.table,
                      child: Text(type.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _type = value;
                  _query = '';
                  _search.clear();
                });
              },
            ),
          ),
          ErpSearchFilterBar(
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            hint: 'ابحث بالاسم أو الرمز',
          ),
          Expanded(child: _body(snapshot)),
        ],
      ),
    );
  }

  Widget _body(AsyncSnapshot<List<Map<String, Object?>>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done)
      return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError)
      return ErpErrorState(
        message: 'تعذر تحميل ${_current.label}: ${snapshot.error}',
        onRetry: () => setState(() => _refresh++),
      );
    final rows = snapshot.data ?? const [];
    if (rows.isEmpty)
      return EmptyState(
        message: 'لا توجد ${_current.label} مطابقة.',
        icon: _current.icon,
        action: FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('إضافة سجل'),
        ),
      );
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _row(rows[index]),
    );
  }

  Widget _row(Map<String, Object?> row) {
    final active = row['active'] == null || row['active'] == 1;
    final closed = row['closed'] == 1;
    return ErpSectionCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: CircleAvatar(child: Icon(_current.icon)),
        title: Text(_title(row)),
        subtitle: Text(_subtitle(row)),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_type == 'fiscal_periods')
              ErpStatusChip(status: closed ? 'closed' : 'open')
            else
              ErpStatusChip(status: active ? 'active' : 'archived'),
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _edit(row);
                if (action == 'archive') _archive(row);
                if (action == 'close') _closePeriod(row);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                if (_type == 'fiscal_periods' && !closed)
                  const PopupMenuItem(
                    value: 'close',
                    child: Text('إقفال الفترة'),
                  ),
                if (_type != 'fiscal_periods')
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('أرشفة / تعطيل'),
                  ),
              ],
            ),
          ],
        ),
        onTap: () => _edit(row),
      ),
    );
  }

  String _title(Map<String, Object?> row) => switch (_type) {
    'branches' ||
    'warehouses' ||
    'cashboxes' => '${row['code']} — ${row['name_ar']}',
    'currencies' => '${row['code']} — ${row['name_ar']}',
    'taxes' || 'categories' || 'units' => '${row['name_ar']}',
    'fiscal_periods' => '${row['name']}',
    _ => '',
  };

  String _subtitle(Map<String, Object?> row) => switch (_type) {
    'branches' =>
      '${row['address'] ?? 'دون عنوان'} • ${row['phone'] ?? 'دون هاتف'}',
    'warehouses' || 'cashboxes' =>
      '${row['branch_name'] ?? ''}${_type == 'cashboxes' ? ' • ${row['type'] == 'bank' ? 'بنك' : 'صندوق نقدي'}' : ''}',
    'currencies' =>
      'الرمز: ${row['symbol'] ?? '-'} • سعر الصرف الأخير: ${row['rate_ppm'] ?? '-'}',
    'taxes' =>
      'النسبة: ${((row['rate_basis_points'] as int? ?? 0) / 100).toStringAsFixed(2)}% • ${row['inclusive'] == 1 ? 'شامل' : 'غير شامل'}',
    'categories' => 'التصنيف الأب: ${row['parent_name'] ?? 'رئيسي'}',
    'units' => 'الكود: ${row['code']} • الدقة: ${row['precision_digits']}',
    'fiscal_periods' => 'من ${row['start_date']} إلى ${row['end_date']}',
    _ => '',
  };

  Future<void> _add() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ReferenceDialog(type: _type),
    );
    if (saved == true && mounted) setState(() => _refresh++);
  }

  Future<void> _edit(Map<String, Object?> row) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ReferenceDialog(type: _type, initial: row),
    );
    if (saved == true && mounted) setState(() => _refresh++);
  }

  Future<void> _archive(Map<String, Object?> row) async {
    final confirmed = await showErpConfirmation(
      context,
      title: 'أرشفة ${_current.label}',
      message:
          'سيتم تعطيل «${_title(row)}» عند وجود سجلات مرتبطة، أو حذفه إذا لم يكن مرتبطاً. لا تُحذف الحركات التاريخية.',
      confirmLabel: 'متابعة',
      destructive: true,
    );
    if (!confirmed) return;
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    try {
      await ref
          .read(referenceDataRepositoryProvider)
          .archive(actor, _type, row);
      if (mounted) {
        showAppMessage(context, 'تمت العملية بنجاح.');
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

  Future<void> _closePeriod(Map<String, Object?> row) async {
    final confirmed = await showErpConfirmation(
      context,
      title: 'إقفال الفترة المالية',
      message: 'سيمنع الإقفال إضافة قيود جديدة إلى هذه الفترة بعد التحقق من عدم وجود قيود مسودة. لا يمكن التراجع من هذه الشاشة.',
      confirmLabel: 'إقفال',
    );
    if (!confirmed) return;
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    try {
      await ref
          .read(referenceDataRepositoryProvider)
          .closePeriod(actor, row['id'] as String);
      if (mounted) {
        showAppMessage(context, 'تم إقفال الفترة المالية.');
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

class _ReferenceDialog extends ConsumerStatefulWidget {
  const _ReferenceDialog({required this.type, this.initial});
  final String type;
  final Map<String, Object?>? initial;

  @override
  ConsumerState<_ReferenceDialog> createState() => _ReferenceDialogState();
}

class _ReferenceDialogState extends ConsumerState<_ReferenceDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _english;
  late final TextEditingController _extra1;
  late final TextEditingController _extra2;
  String? _branchId;
  String? _parentId;
  String _cashType = 'cash';
  bool _active = true;
  bool _inclusive = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final row = widget.initial;
    _code = TextEditingController(text: '${row?['code'] ?? ''}');
    _name = TextEditingController(
      text: '${row?['name_ar'] ?? row?['name'] ?? ''}',
    );
    _english = TextEditingController(text: '${row?['name_en'] ?? ''}');
    _extra1 = TextEditingController(text: _initialExtra1(row));
    _extra2 = TextEditingController(text: _initialExtra2(row));
    _branchId = row?['branch_id'] as String?;
    _parentId = row?['parent_id'] as String?;
    _cashType = row?['type'] == 'bank' ? 'bank' : 'cash';
    _active = row?['active'] == null || row?['active'] == 1;
    _inclusive = row?['inclusive'] == 1;
  }

  String _initialExtra1(Map<String, Object?>? row) => switch (widget.type) {
    'branches' => '${row?['address'] ?? ''}',
    'currencies' => '${row?['symbol'] ?? ''}',
    'taxes' => ((row?['rate_basis_points'] as int? ?? 0) / 100).toStringAsFixed(
      2,
    ),
    'units' => '${row?['precision_digits'] ?? 3}',
    'fiscal_periods' => '${row?['start_date'] ?? ''}',
    _ => '',
  };

  String _initialExtra2(Map<String, Object?>? row) => switch (widget.type) {
    'branches' => '${row?['phone'] ?? ''}',
    'currencies' => '${row?['rate_ppm'] ?? ''}',
    'fiscal_periods' => '${row?['end_date'] ?? ''}',
    _ => '',
  };

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _english.dispose();
    _extra1.dispose();
    _extra2.dispose();
    super.dispose();
  }

  bool get _requiresBranch =>
      widget.type == 'warehouses' || widget.type == 'cashboxes';

  @override
  Widget build(BuildContext context) {
    final branches = ref
        .watch(referenceDataRepositoryProvider)
        .list('branches');
    final categories = ref
        .watch(referenceDataRepositoryProvider)
        .list('categories');
    return AlertDialog(
      title: Text(widget.initial == null ? 'إضافة $_label' : 'تعديل $_label'),
      content: FutureBuilder<List<List<Map<String, Object?>>>>(
        future: Future.wait([branches, categories]),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          return SizedBox(
            width: 460,
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _fields(snapshot.data![0], snapshot.data![1]),
                ),
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
          child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    );
  }

  String get _label => switch (widget.type) {
    'branches' => 'فرع',
    'warehouses' => 'مخزن',
    'cashboxes' => 'صندوق أو بنك',
    'currencies' => 'عملة',
    'taxes' => 'ضريبة',
    'categories' => 'تصنيف',
    'units' => 'وحدة',
    'fiscal_periods' => 'فترة مالية',
    _ => 'سجل',
  };

  List<Widget> _fields(
    List<Map<String, Object?>> branches,
    List<Map<String, Object?>> categories,
  ) {
    final widgets = <Widget>[];
    if (widget.type == 'currencies' ||
        widget.type == 'branches' ||
        widget.type == 'warehouses' ||
        widget.type == 'cashboxes' ||
        widget.type == 'units') {
      widgets.add(
        _text(
          _code,
          widget.type == 'currencies' ? 'كود العملة (مثال: YER)' : 'الكود',
          required: true,
          enabled: !(widget.type == 'currencies' && widget.initial != null),
        ),
      );
    }
    widgets.add(
      _text(
        _name,
        widget.type == 'fiscal_periods' ? 'اسم الفترة المالية' : 'الاسم العربي',
        required: true,
      ),
    );
    if (widget.type != 'fiscal_periods')
      widgets.add(_text(_english, 'الاسم الإنجليزي (اختياري)'));
    if (_requiresBranch) {
      widgets.add(
        _dropdown(
          'الفرع',
          _branchId,
          branches
              .map(
                (row) => DropdownMenuItem(
                  value: row['id'] as String,
                  child: Text(row['name_ar'] as String),
                ),
              )
              .toList(),
          (value) => setState(() => _branchId = value),
        ),
      );
    }
    if (widget.type == 'cashboxes') {
      widgets.add(
        _dropdown('النوع', _cashType, const [
          DropdownMenuItem(value: 'cash', child: Text('صندوق نقدي')),
          DropdownMenuItem(value: 'bank', child: Text('حساب بنكي')),
        ], (value) => setState(() => _cashType = value ?? 'cash')),
      );
    }
    if (widget.type == 'categories') {
      widgets.add(
        _dropdown('التصنيف الأب (اختياري)', _parentId, [
          const DropdownMenuItem(value: null, child: Text('تصنيف رئيسي')),
          ...categories
              .where((row) => row['id'] != widget.initial?['id'])
              .map(
                (row) => DropdownMenuItem(
                  value: row['id'] as String,
                  child: Text(row['name_ar'] as String),
                ),
              ),
        ], (value) => setState(() => _parentId = value)),
      );
    }
    if (widget.type == 'branches') {
      widgets.add(_text(_extra1, 'العنوان'));
      widgets.add(_text(_extra2, 'الهاتف'));
    }
    if (widget.type == 'currencies') {
      widgets.add(_text(_extra1, 'رمز العملة'));
      widgets.add(
        _text(
          _extra2,
          'سعر الصرف PPM (1000000 للعملة الأساسية)',
          keyboard: TextInputType.number,
        ),
      );
    }
    if (widget.type == 'taxes') {
      widgets.add(
        _text(
          _extra1,
          'نسبة الضريبة %',
          keyboard: TextInputType.number,
          required: true,
        ),
      );
      widgets.add(
        SwitchListTile(
          value: _inclusive,
          title: const Text('ضريبة شاملة في السعر'),
          onChanged: (value) => setState(() => _inclusive = value),
        ),
      );
    }
    if (widget.type == 'units')
      widgets.add(
        _text(
          _extra1,
          'عدد المنازل العشرية',
          keyboard: TextInputType.number,
          required: true,
        ),
      );
    if (widget.type == 'fiscal_periods') {
      widgets.add(_date(_extra1, 'تاريخ البداية'));
      widgets.add(_date(_extra2, 'تاريخ النهاية'));
    }
    if (widget.type != 'fiscal_periods')
      widgets.add(
        SwitchListTile(
          value: _active,
          title: const Text('نشط'),
          onChanged: (value) => setState(() => _active = value),
        ),
      );
    return widgets;
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool enabled = true,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (value) =>
                value == null || value.trim().isEmpty ? '$label مطلوب' : null
          : null,
    ),
  );
  Widget _dropdown(
    String label,
    String? value,
    List<DropdownMenuItem<String?>> items,
    ValueChanged<String?> changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: _saving ? null : changed,
    ),
  );
  Widget _date(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null)
          controller.text = picked.toIso8601String().substring(0, 10);
      },
      validator: (value) =>
          DateTime.tryParse(value ?? '') == null ? 'اختر تاريخاً صحيحاً' : null,
    ),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate() ||
        (_requiresBranch && _branchId == null)) {
      if (_requiresBranch && _branchId == null)
        showAppMessage(context, 'اختر الفرع.', error: true);
      return;
    }
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    final fields = <String, Object?>{
      'id': widget.initial?['id'],
      'code': _code.text.trim(),
      'name_ar': _name.text.trim(),
      'name_en': _english.text.trim(),
      'active': _active,
      'branch_id': _branchId,
      'parent_id': _parentId,
      'type': _cashType,
      'address': _extra1.text.trim(),
      'phone': _extra2.text.trim(),
      'symbol': _extra1.text.trim(),
      'rate_ppm': int.tryParse(_extra2.text.trim()) ?? 0,
      'rate_basis_points': ((double.tryParse(_extra1.text.trim()) ?? 0) * 100)
          .round(),
      'inclusive': _inclusive,
      'precision_digits': int.tryParse(_extra1.text.trim()) ?? 0,
      'name': _name.text.trim(),
      'start_date': _extra1.text.trim(),
      'end_date': _extra2.text.trim(),
    };
    setState(() => _saving = true);
    try {
      await ref
          .read(referenceDataRepositoryProvider)
          .save(actor, widget.type, fields);
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
}

class _ReferenceType {
  const _ReferenceType(this.table, this.label, this.icon);
  final String table;
  final String label;
  final IconData icon;
}
