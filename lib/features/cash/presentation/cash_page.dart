import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/providers.dart';
import '../../../shared/widgets/app_scaffold.dart';

class CashPage extends ConsumerWidget {
  const CashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FutureBuilder<List<List<Map<String, Object?>>>>(
        future: Future.wait([
          ref.watch(masterRepositoryProvider).cashboxes(),
          ref.watch(masterRepositoryProvider).customers(),
          ref.watch(masterRepositoryProvider).suppliers(),
          ref.watch(referenceDataRepositoryProvider).list('currencies'),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return EmptyState(
              message: '${context.tr('error')}: ${snapshot.error}',
            );
          final cashboxes = snapshot.data![0];
          final customers = snapshot.data![1];
          final suppliers = snapshot.data![2];
          final currencies = snapshot.data![3];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'عمليات نقدية سريعة',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _action(
                context,
                Icons.south_west,
                context.tr('newReceipt'),
                customers.isEmpty
                    ? null
                    : () => _openPayment(context, ref, customers, currencies, true),
              ),
              _action(
                context,
                Icons.north_east,
                context.tr('newVoucher'),
                suppliers.isEmpty
                    ? null
                    : () => _openPayment(context, ref, suppliers, currencies, false),
              ),
              _action(
                context,
                Icons.swap_horiz,
                context.tr('cashTransfer'),
                cashboxes.length < 2
                    ? null
                    : () => _openTransfer(context, ref, cashboxes, currencies),
              ),
              const SizedBox(height: 20),
              Text(
                'الصناديق المتاحة',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...cashboxes.map(
                (box) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(box['name_ar'] as String),
                    subtitle: Text(box['code'] as String),
                  ),
                ),
              ),
              if (customers.isEmpty || suppliers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    'أنشئ العملاء والموردين أولاً لتفعيل سندات القبض والصرف.',
                  ),
                ),
            ],
          );
        },
      );

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? onTap,
  ) => Card(
    child: ListTile(
      enabled: onTap != null,
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_left),
      onTap: onTap,
    ),
  );

  Future<void> _openPayment(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, Object?>> parties,
    List<Map<String, Object?>> currencies,
    bool receipt,
  ) async {
    final result = await showDialog<_PaymentData>(
      context: context,
      builder: (_) => _PaymentDialog(parties: parties, currencies: currencies, receipt: receipt),
    );
    if (result == null || !context.mounted) return;
    final actor = ref.read(sessionProvider);
    if (actor?.cashboxId == null) {
      showAppMessage(context, 'لا يوجد صندوق مخصص للجلسة', error: true);
      return;
    }
    try {
      final number = receipt
          ? await ref
                .read(cashAccountingProvider)
                .receiveFromCustomer(
                  actor: actor!,
                  customerId: result.partyId,
                  cashboxId: actor.cashboxId!,
                  amountMinor: result.amount,
                  date: DateTime.now(),
                  currencyCode: result.currencyCode,
                  ratePpm: result.ratePpm,
                  notes: result.notes,
                )
          : await ref
                .read(cashAccountingProvider)
                .paySupplier(
                  actor: actor!,
                  supplierId: result.partyId,
                  cashboxId: actor.cashboxId!,
                  amountMinor: result.amount,
                  date: DateTime.now(),
                  currencyCode: result.currencyCode,
                  ratePpm: result.ratePpm,
                  notes: result.notes,
                );
      if (context.mounted) showAppMessage(context, 'تم ترحيل السند $number');
    } catch (error) {
      if (context.mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    }
  }

  Future<void> _openTransfer(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, Object?>> cashboxes,
    List<Map<String, Object?>> currencies,
  ) async {
    final result = await showDialog<_TransferData>(
      context: context,
      builder: (_) => _TransferDialog(cashboxes: cashboxes, currencies: currencies),
    );
    if (result == null) return;
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    try {
      final number = await ref
          .read(cashAccountingProvider)
          .transferCash(
            actor: actor,
            fromCashboxId: result.from,
            toCashboxId: result.to,
            amountMinor: result.amount,
            date: DateTime.now(),
            currencyCode: result.currencyCode,
            ratePpm: result.ratePpm,
          );
      if (context.mounted) showAppMessage(context, 'تم ترحيل التحويل $number');
    } catch (error) {
      if (context.mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    }
  }
}

class _PaymentData {
  const _PaymentData(this.partyId, this.amount, this.notes, this.currencyCode, this.ratePpm);
  final String partyId;
  final int amount;
  final String? notes;
  final String currencyCode;
  final int ratePpm;
}

class _TransferData {
  const _TransferData(this.from, this.to, this.amount, this.currencyCode, this.ratePpm);
  final String from;
  final String to;
  final int amount;
  final String currencyCode;
  final int ratePpm;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.parties, required this.currencies, required this.receipt});
  final List<Map<String, Object?>> parties;
  final List<Map<String, Object?>> currencies;
  final bool receipt;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String? _party;
  String _currencyCode = 'YER';
  int _ratePpm = 1000000;
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.receipt ? context.tr('newReceipt') : context.tr('newVoucher'),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _party,
          decoration: InputDecoration(
            labelText: widget.receipt
                ? context.tr('customer')
                : context.tr('supplier'),
          ),
          items: widget.parties
              .map(
                (p) => DropdownMenuItem(
                  value: p['id'] as String,
                  child: Text(p['name'] as String),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _party = v),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: widget.currencies.any((row) => row['code'] == _currencyCode) ? _currencyCode : null,
          decoration: const InputDecoration(labelText: 'العملة'),
          items: widget.currencies.map((row) => DropdownMenuItem(value: row['code'] as String, child: Text('${row['code']} — ${row['name_ar']}'))).toList(),
          onChanged: (value) {
            if (value == null) return;
            final row = widget.currencies.firstWhere((item) => item['code'] == value);
            final rate = row['rate_ppm'];
            if (rate is! int || rate <= 0) {
              showAppMessage(context, 'لا يوجد سعر صرف محفوظ لهذه العملة.', error: true);
              return;
            }
            setState(() { _currencyCode = value; _ratePpm = rate; });
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: '${context.tr('amount')} ($_currencyCode)'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notes,
          decoration: InputDecoration(labelText: context.tr('notes')),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('cancel')),
      ),
      FilledButton(
        onPressed: () {
          final value = int.tryParse(_amount.text);
          if (_party == null || value == null || value <= 0) {
            showAppMessage(
              context,
              'اختر الطرف وأدخل مبلغاً صحيحاً',
              error: true,
            );
            return;
          }
          Navigator.pop(
            context,
            _PaymentData(
              _party!,
              value,
              _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              _currencyCode,
              _ratePpm,
            ),
          );
        },
        child: Text(context.tr('save')),
      ),
    ],
  );
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.cashboxes, required this.currencies});
  final List<Map<String, Object?>> cashboxes;
  final List<Map<String, Object?>> currencies;
  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  String? _from;
  String? _to;
  String _currencyCode = 'YER';
  int _ratePpm = 1000000;
  final _amount = TextEditingController();
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('cashTransfer')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _from,
          decoration: const InputDecoration(labelText: 'من الصندوق'),
          items: widget.cashboxes
              .map(
                (b) => DropdownMenuItem(
                  value: b['id'] as String,
                  child: Text(b['name_ar'] as String),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _from = v),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _to,
          decoration: const InputDecoration(labelText: 'إلى الصندوق'),
          items: widget.cashboxes
              .map(
                (b) => DropdownMenuItem(
                  value: b['id'] as String,
                  child: Text(b['name_ar'] as String),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _to = v),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: widget.currencies.any((row) => row['code'] == _currencyCode) ? _currencyCode : null,
          decoration: const InputDecoration(labelText: 'العملة'),
          items: widget.currencies.map((row) => DropdownMenuItem(value: row['code'] as String, child: Text('${row['code']} — ${row['name_ar']}'))).toList(),
          onChanged: (value) {
            if (value == null) return;
            final row = widget.currencies.firstWhere((item) => item['code'] == value);
            final rate = row['rate_ppm'];
            if (rate is! int || rate <= 0) {
              showAppMessage(context, 'لا يوجد سعر صرف محفوظ لهذه العملة.', error: true);
              return;
            }
            setState(() { _currencyCode = value; _ratePpm = rate; });
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: '${context.tr('amount')} ($_currencyCode)'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('cancel')),
      ),
      FilledButton(
        onPressed: () {
          final value = int.tryParse(_amount.text);
          if (_from == null ||
              _to == null ||
              _from == _to ||
              value == null ||
              value <= 0) {
            showAppMessage(context, 'تحقق من الصناديق والمبلغ', error: true);
            return;
          }
          Navigator.pop(context, _TransferData(_from!, _to!, value, _currencyCode, _ratePpm));
        },
        child: Text(context.tr('save')),
      ),
    ],
  );
}
