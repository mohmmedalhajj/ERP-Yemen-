import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';
import '../../core/services/license_service.dart';
import '../../data/repositories/auth_repository.dart';

class ManualJournalLine {
  const ManualJournalLine({
    required this.accountId,
    this.debitMinor = 0,
    this.creditMinor = 0,
    this.description,
  });

  final String accountId;
  final int debitMinor;
  final int creditMinor;
  final String? description;
}

class CashAccountingService {
  CashAccountingService(this._database, {LicenseService? licenseService})
    : _licenseService = licenseService ?? LicenseService(_database);
  final ErpDatabase _database;
  final LicenseService _licenseService;

  Future<String> receiveFromCustomer({
    required AuthUser actor,
    required String customerId,
    required String cashboxId,
    required int amountMinor,
    required DateTime date,
    String currencyCode = 'YER',
    int ratePpm = 1000000,
    String? notes,
  }) => _postPayment(
    actor: actor,
    partyType: 'customer',
    partyId: customerId,
    cashboxId: cashboxId,
    amountMinor: amountMinor,
    date: date,
    currencyCode: currencyCode,
    ratePpm: ratePpm,
    notes: notes,
  );

  Future<String> paySupplier({
    required AuthUser actor,
    required String supplierId,
    required String cashboxId,
    required int amountMinor,
    required DateTime date,
    String currencyCode = 'YER',
    int ratePpm = 1000000,
    String? notes,
  }) => _postPayment(
    actor: actor,
    partyType: 'supplier',
    partyId: supplierId,
    cashboxId: cashboxId,
    amountMinor: amountMinor,
    date: date,
    currencyCode: currencyCode,
    ratePpm: ratePpm,
    notes: notes,
  );

  Future<String> _postPayment({
    required AuthUser actor,
    required String partyType,
    required String partyId,
    required String cashboxId,
    required int amountMinor,
    required DateTime date,
    required String currencyCode,
    required int ratePpm,
    String? notes,
  }) async {
    final license = await _licenseService.currentStatus();
    if (!license.permitsNewTransactions) {
      throw StateError(license.message);
    }
    requirePermission(actor.permissions, Permissions.cashManage);
    if (amountMinor <= 0 || ratePpm <= 0)
      throw ArgumentError('المبلغ أو سعر الصرف غير صالح');
    final id = await _database.newId();
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.transaction((txn) async {
      final no = await _database.nextDocumentNumber(
        txn,
        documentType: partyType == 'customer' ? 'receipt' : 'voucher',
        branchId: actor.branchId,
        prefix: partyType == 'customer' ? 'REC' : 'PAY',
      );
      await txn.insert('payments', {
        'id': id,
        'document_no': no,
        'payment_type': partyType == 'customer' ? 'receipt' : 'payment',
        'party_type': partyType,
        'customer_id': partyType == 'customer' ? partyId : null,
        'supplier_id': partyType == 'supplier' ? partyId : null,
        'cashbox_id': cashboxId,
        'amount_minor': amountMinor,
        'currency_code': currencyCode,
        'rate_ppm': ratePpm,
        'payment_date': _date(date),
        'status': 'posted',
        'notes': notes,
        'created_by': actor.id,
        'created_at': now,
      });
      await txn.insert('cash_movements', {
        'id': await _database.newId(),
        'cashbox_id': cashboxId,
        'movement_type': partyType == 'customer'
            ? 'receipt'
            : 'supplier_payment',
        'amount_minor': partyType == 'customer' ? amountMinor : -amountMinor,
        'currency_code': currencyCode,
        'rate_ppm': ratePpm,
        'source_type': 'payment',
        'source_id': id,
        'occurred_at': now,
        'description': notes ?? no,
        'user_id': actor.id,
      });
      await _journal(
        txn,
        actor: actor,
        sourceId: id,
        sourceType: 'payment',
        date: date,
        description: no,
        currencyCode: currencyCode,
        ratePpm: ratePpm,
        lines: partyType == 'customer'
            ? [
                _CashJournalLine('acc-cash', debit: amountMinor),
                _CashJournalLine('acc-ar', credit: amountMinor),
              ]
            : [
                _CashJournalLine('acc-ap', debit: amountMinor),
                _CashJournalLine('acc-cash', credit: amountMinor),
              ],
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'payment.posted',
        entityType: 'payment',
        entityId: id,
        afterJson: '{"document_no":"$no","amount_minor":$amountMinor}',
      );
      return no;
    });
  }

  Future<String> transferCash({
    required AuthUser actor,
    required String fromCashboxId,
    required String toCashboxId,
    required int amountMinor,
    required DateTime date,
    String currencyCode = 'YER',
    int ratePpm = 1000000,
    String? notes,
  }) async {
    final license = await _licenseService.currentStatus();
    if (!license.permitsNewTransactions) {
      throw StateError(license.message);
    }
    requirePermission(actor.permissions, Permissions.cashManage);
    if (fromCashboxId == toCashboxId)
      throw ArgumentError('يجب أن يختلف الصندوق المستلم عن المرسل');
    if (amountMinor <= 0 || ratePpm <= 0)
      throw ArgumentError('المبلغ أو سعر الصرف غير صالح');
    final id = await _database.newId();
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.transaction((txn) async {
      final no = await _database.nextDocumentNumber(
        txn,
        documentType: 'cash_transfer',
        branchId: actor.branchId,
        prefix: 'TRF',
      );
      for (final item in [
        (fromCashboxId, -amountMinor),
        (toCashboxId, amountMinor),
      ]) {
        await txn.insert('cash_movements', {
          'id': await _database.newId(),
          'cashbox_id': item.$1,
          'movement_type': 'transfer',
          'amount_minor': item.$2,
          'currency_code': currencyCode,
          'rate_ppm': ratePpm,
          'source_type': 'cash_transfer',
          'source_id': id,
          'occurred_at': now,
          'description': notes ?? no,
          'user_id': actor.id,
        });
      }
      await _journal(
        txn,
        actor: actor,
        sourceId: id,
        sourceType: 'cash_transfer',
        date: date,
        description: no,
        currencyCode: currencyCode,
        ratePpm: ratePpm,
        lines: [
          _CashJournalLine('acc-cash', debit: amountMinor),
          _CashJournalLine('acc-cash', credit: amountMinor),
        ],
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'cash.transfer_posted',
        entityType: 'cash_transfer',
        entityId: id,
        afterJson: '{"document_no":"$no","amount_minor":$amountMinor}',
      );
      return no;
    });
  }

  Future<String> postManualJournal({
    required AuthUser actor,
    required DateTime date,
    required String description,
    required List<ManualJournalLine> lines,
  }) async {
    final license = await _licenseService.currentStatus();
    if (!license.permitsNewTransactions) {
      throw StateError(license.message);
    }
    requirePermission(actor.permissions, Permissions.accountingPost);
    if (lines.isEmpty) throw ArgumentError('القيد يحتاج إلى سطور');
    final debit = lines.fold<int>(0, (sum, line) => sum + line.debitMinor);
    final credit = lines.fold<int>(0, (sum, line) => sum + line.creditMinor);
    if (debit <= 0 || debit != credit) throw StateError('القيد غير متوازن');
    final entryId = await _database.newId();
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.transaction((txn) async {
      final no = await _database.nextDocumentNumber(
        txn,
        documentType: 'journal',
        branchId: null,
        prefix: 'JRN',
      );
      await txn.insert('journal_entries', {
        'id': entryId,
        'entry_no': no,
        'entry_date': _date(date),
        'status': 'posted',
        'source_type': 'manual',
        'source_id': entryId,
        'description': description,
        'created_by': actor.id,
        'posted_by': actor.id,
        'posted_at': now,
        'created_at': now,
      });
      for (final line in lines) {
        if (line.debitMinor < 0 ||
            line.creditMinor < 0 ||
            (line.debitMinor == 0) == (line.creditMinor == 0)) {
          throw ArgumentError('سطر القيد غير صالح');
        }
        await txn.insert('journal_lines', {
          'id': await _database.newId(),
          'journal_entry_id': entryId,
          'account_id': line.accountId,
          'debit_minor': line.debitMinor,
          'credit_minor': line.creditMinor,
          'description': line.description,
        });
      }
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'journal.manual_posted',
        entityType: 'journal_entry',
        entityId: entryId,
        afterJson: '{"entry_no":"$no"}',
      );
      return no;
    });
  }

  Future<void> _journal(
    dynamic txn, {
    required AuthUser actor,
    required String sourceId,
    required String sourceType,
    required DateTime date,
    required String description,
    required String currencyCode,
    required int ratePpm,
    required List<_CashJournalLine> lines,
  }) async {
    final debit = lines.fold<int>(0, (sum, line) => sum + line.debit);
    final credit = lines.fold<int>(0, (sum, line) => sum + line.credit);
    if (debit != credit || debit <= 0)
      throw StateError('تم منع القيد غير المتوازن');
    final id = await _database.newId();
    final no = await _database.nextDocumentNumber(
      txn,
      documentType: 'journal',
      branchId: null,
      prefix: 'JRN',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.insert('journal_entries', {
      'id': id,
      'entry_no': no,
      'entry_date': _date(date),
      'status': 'posted',
      'source_type': sourceType,
      'source_id': sourceId,
      'description': description,
      'created_by': actor.id,
      'posted_by': actor.id,
      'posted_at': now,
      'created_at': now,
    });
    for (final line in lines) {
      await txn.insert('journal_lines', {
        'id': await _database.newId(),
        'journal_entry_id': id,
        'account_id': line.accountId,
        'debit_minor': line.debit,
        'credit_minor': line.credit,
        'currency_code': currencyCode,
        'rate_ppm': ratePpm,
      });
    }
  }

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);
}

class _CashJournalLine {
  const _CashJournalLine(this.accountId, {this.debit = 0, this.credit = 0});
  final String accountId;
  final int debit;
  final int credit;
}
