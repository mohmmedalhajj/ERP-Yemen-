import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/money.dart';
import '../../../core/services/providers.dart';
import '../../../domain/services/other_income_expense_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/erp_ui.dart';

class FinanceOperationsPage extends ConsumerStatefulWidget {
  const FinanceOperationsPage({super.key});

  @override
  ConsumerState<FinanceOperationsPage> createState() =>
      _FinanceOperationsPageState();
}

class _FinanceOperationsPageState extends ConsumerState<FinanceOperationsPage> {
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
    final future = ref.watch(otherIncomeExpenseProvider).list(search: _query);
    return FutureBuilder<List<Map<String, Object?>>>(
      key: ValueKey(_refresh),
      future: future,
      builder: (context, snapshot) => Column(
        children: [
          ErpPageHeader(
            title: 'المصروفات والإيرادات',
            subtitle: 'تُرحّل العمليات المعتمدة إلى الصندوق والقيد المحاسبي تلقائياً ولا تُحذف بعد الترحيل.',
            actions: [
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('عملية جديدة'),
              ),
            ],
          ),
          ErpSearchFilterBar(
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            hint: 'ابحث برقم السند أو الفئة أو الطرف',
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
        message: 'تعذر تحميل العمليات: ${snapshot.error}',
        onRetry: () => setState(() => _refresh++),
      );
    final rows = snapshot.data ?? const [];
    if (rows.isEmpty)
      return EmptyState(
        message: 'لا توجد مصروفات أو إيرادات مسجلة.',
        icon: Icons.receipt_long_outlined,
        action: FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('إضافة عملية'),
        ),
      );
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        final income = row['operation_type'] == 'income';
        final color = income ? Colors.green : Colors.red;
        return ErpSectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: .12),
              child: Icon(
                income ? Icons.arrow_downward : Icons.arrow_upward,
                color: color,
              ),
            ),
            title: Text('${income ? 'إيراد' : 'مصروف'} • ${row['category']}'),
            subtitle: Text(
              '${row['document_no']} • ${row['party_name'] ?? 'دون طرف'}\n${row['operation_date']} • ${row['description'] ?? ''}',
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Money(row['amount_minor'] as int).format(withSymbol: false),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
                const ErpStatusChip(status: 'posted'),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _create() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.remove_circle_outline,
                color: Colors.red,
              ),
              title: const Text('تسجيل مصروف'),
              onTap: () => Navigator.pop(context, 'expense'),
            ),
            ListTile(
              leading: const Icon(
                Icons.add_circle_outline,
                color: Colors.green,
              ),
              title: const Text('تسجيل إيراد آخر'),
              onTap: () => Navigator.pop(context, 'income'),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FinanceOperationDialog(isExpense: type == 'expense'),
    );
    if (saved == true && mounted) setState(() => _refresh++);
  }
}

class _FinanceOperationDialog extends ConsumerStatefulWidget {
  const _FinanceOperationDialog({required this.isExpense});
  final bool isExpense;

  @override
  ConsumerState<_FinanceOperationDialog> createState() =>
      _FinanceOperationDialogState();
}

class _FinanceOperationDialogState
    extends ConsumerState<_FinanceOperationDialog> {
  final _form = GlobalKey<FormState>();
  final _category = TextEditingController();
  final _amount = TextEditingController();
  final _party = TextEditingController();
  final _description = TextEditingController();
  String? _cashboxId;
  bool _saving = false;

  @override
  void dispose() {
    _category.dispose();
    _amount.dispose();
    _party.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _cashboxId == null) {
      if (_cashboxId == null)
        showAppMessage(context, 'اختر الصندوق.', error: true);
      return;
    }
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final input = OtherCashOperationInput(
        category: _category.text,
        cashboxId: _cashboxId!,
        amountMinor: int.parse(_amount.text.trim()),
        date: DateTime.now(),
        partyName: _party.text,
        description: _description.text,
      );
      if (widget.isExpense) {
        await ref.read(otherIncomeExpenseProvider).postExpense(user, input);
      } else {
        await ref.read(otherIncomeExpenseProvider).postIncome(user, input);
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
  Widget build(BuildContext context) {
    final cashboxes = ref.watch(administrationRepositoryProvider).cashboxes();
    return AlertDialog(
      title: Text(widget.isExpense ? 'تسجيل مصروف' : 'تسجيل إيراد آخر'),
      content: FutureBuilder<List<Map<String, Object?>>>(
        future: cashboxes,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          return SizedBox(
            width: 420,
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _category,
                      decoration: const InputDecoration(labelText: 'الفئة'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'الفئة مطلوبة'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'المبلغ'),
                      validator: (value) => (int.tryParse(value ?? '') ?? 0) > 0
                          ? null
                          : 'أدخل مبلغاً أكبر من صفر',
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _cashboxId,
                      decoration: const InputDecoration(labelText: 'الصندوق'),
                      items: snapshot.data!
                          .map(
                            (row) => DropdownMenuItem(
                              value: row['id'] as String,
                              child: Text(row['name_ar'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _cashboxId = value),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _party,
                      decoration: InputDecoration(
                        labelText: widget.isExpense
                            ? 'المستفيد (اختياري)'
                            : 'الدافع (اختياري)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'الوصف أو الملاحظات',
                      ),
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
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الترحيل...' : 'ترحيل العملية'),
        ),
      ],
    );
  }
}
