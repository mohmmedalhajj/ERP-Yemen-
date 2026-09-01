import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/providers.dart';
import '../../../domain/services/cash_accounting_service.dart';
import '../../../shared/widgets/app_scaffold.dart';

class AccountingPage extends ConsumerWidget {
  const AccountingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FutureBuilder<List<Map<String, Object?>>>(
        future: ref
            .watch(databaseProvider)
            .raw
            .query('accounts', where: 'active = 1', orderBy: 'code'),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return EmptyState(
              message: '${context.tr('error')}: ${snapshot.error}',
            );
          final accounts = snapshot.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: accounts.length < 2
                        ? null
                        : () async {
                            final saved = await showDialog<bool>(
                              context: context,
                              builder: (_) =>
                                  _JournalDialog(accounts: accounts),
                            );
                            if (saved == true && context.mounted)
                              showAppMessage(context, 'تم ترحيل القيد بنجاح');
                          },
                    icon: const Icon(Icons.add_chart_outlined),
                    label: Text(context.tr('manualJournal')),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final item = accounts[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text('${item['code']} — ${item['name_ar']}'),
                        subtitle: Text(item['account_type'] as String),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
}

class _JournalDialog extends ConsumerStatefulWidget {
  const _JournalDialog({required this.accounts});
  final List<Map<String, Object?>> accounts;
  @override
  ConsumerState<_JournalDialog> createState() => _JournalDialogState();
}

class _JournalDialogState extends ConsumerState<_JournalDialog> {
  String? _debitAccount;
  String? _creditAccount;
  final _amount = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text.trim());
    if (_debitAccount == null ||
        _creditAccount == null ||
        _debitAccount == _creditAccount ||
        amount == null ||
        amount <= 0) {
      showAppMessage(
        context,
        'اختر حسابين مختلفين وأدخل مبلغاً صحيحاً',
        error: true,
      );
      return;
    }
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(cashAccountingProvider)
          .postManualJournal(
            actor: actor,
            date: DateTime.now(),
            description: _description.text.trim().isEmpty
                ? 'قيد يدوي'
                : _description.text.trim(),
            lines: [
              ManualJournalLine(accountId: _debitAccount!, debitMinor: amount),
              ManualJournalLine(
                accountId: _creditAccount!,
                creditMinor: amount,
              ),
            ],
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
    title: Text(context.tr('manualJournal')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _debitAccount,
            decoration: const InputDecoration(labelText: 'الحساب المدين'),
            items: widget.accounts
                .map(
                  (a) => DropdownMenuItem(
                    value: a['id'] as String,
                    child: Text('${a['code']} — ${a['name_ar']}'),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _debitAccount = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _creditAccount,
            decoration: const InputDecoration(labelText: 'الحساب الدائن'),
            items: widget.accounts
                .map(
                  (a) => DropdownMenuItem(
                    value: a['id'] as String,
                    child: Text('${a['code']} — ${a['name_ar']}'),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _creditAccount = value),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.tr('amount')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            decoration: InputDecoration(labelText: context.tr('notes')),
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
