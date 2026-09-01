import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';
import '../../core/services/license_service.dart';
import '../../data/repositories/auth_repository.dart';

class OtherCashOperationInput {
  const OtherCashOperationInput({
    required this.category,
    required this.cashboxId,
    required this.amountMinor,
    required this.date,
    this.partyName,
    this.description,
    this.currencyCode = 'YER',
    this.ratePpm = 1000000,
  });

  final String category;
  final String cashboxId;
  final int amountMinor;
  final DateTime date;
  final String? partyName;
  final String? description;
  final String currencyCode;
  final int ratePpm;
}

class OtherIncomeExpenseService {
  OtherIncomeExpenseService(this._database, {LicenseService? licenseService})
    : _licenseService = licenseService ?? LicenseService(_database);

  final ErpDatabase _database;
  final LicenseService _licenseService;

  Future<String> postExpense(AuthUser actor, OtherCashOperationInput input) =>
      _post(actor, input, isExpense: true);
  Future<String> postIncome(AuthUser actor, OtherCashOperationInput input) =>
      _post(actor, input, isExpense: false);

  Future<String> _post(
    AuthUser actor,
    OtherCashOperationInput input, {
    required bool isExpense,
  }) async {
    final license = await _licenseService.currentStatus();
    if (!license.permitsNewTransactions) throw StateError(license.message);
    requirePermission(actor.permissions, Permissions.cashManage);
    requirePermission(actor.permissions, Permissions.accountingPost);
    if (input.category.trim().isEmpty ||
        input.cashboxId.trim().isEmpty ||
        input.amountMinor <= 0 ||
        input.ratePpm <= 0) {
      throw ArgumentError('تحقق من الفئة والصندوق والمبلغ وسعر الصرف');
    }
    final id = await _database.newId();
    final table = isExpense ? 'expenses' : 'other_incomes';
    final documentType = isExpense ? 'EXP' : 'INC';
    final now = DateTime.now().toUtc();
    await _database.transaction((txn) async {
      final documentNo = await _database.nextDocumentNumber(
        txn,
        documentType: documentType,
        branchId: actor.branchId,
        prefix: documentType,
      );
      await txn.insert(table, {
        'id': id,
        'document_no': documentNo,
        'category': input.category.trim(),
        isExpense ? 'expense_date' : 'income_date': input.date
            .toUtc()
            .toIso8601String()
            .substring(0, 10),
        'cashbox_id': input.cashboxId,
        'amount_minor': input.amountMinor,
        'currency_code': input.currencyCode,
        'rate_ppm': input.ratePpm,
        isExpense ? 'payee' : 'payer': input.partyName?.trim(),
        'description': input.description?.trim(),
        'status': 'posted',
        'created_by': actor.id,
        'posted_at': now.toIso8601String(),
      });
      await txn.insert('cash_movements', {
        'id': await _database.newId(),
        'cashbox_id': input.cashboxId,
        'movement_type': isExpense ? 'expense' : 'other_income',
        'amount_minor': isExpense ? -input.amountMinor : input.amountMinor,
        'currency_code': input.currencyCode,
        'rate_ppm': input.ratePpm,
        'source_type': isExpense ? 'expense' : 'other_income',
        'source_id': id,
        'occurred_at': now.toIso8601String(),
        'description': '${isExpense ? 'مصروف' : 'إيراد'} $documentNo',
        'user_id': actor.id,
      });
      final journalId = await _database.newId();
      final journalNo = await _database.nextDocumentNumber(
        txn,
        documentType: 'JRN',
        branchId: actor.branchId,
        prefix: 'QYD',
      );
      await txn.insert('journal_entries', {
        'id': journalId,
        'entry_no': journalNo,
        'entry_date': input.date.toUtc().toIso8601String().substring(0, 10),
        'status': 'posted',
        'source_type': isExpense ? 'expense' : 'other_income',
        'source_id': id,
        'description': '${isExpense ? 'قيد مصروف' : 'قيد إيراد'} $documentNo',
        'created_by': actor.id,
        'posted_by': actor.id,
        'posted_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      });
      final primaryAccount = isExpense ? 'acc-expense' : 'acc-other-income';
      final firstDebit = isExpense ? input.amountMinor : input.amountMinor;
      await txn.insert('journal_lines', {
        'id': await _database.newId(),
        'journal_entry_id': journalId,
        'account_id': isExpense ? primaryAccount : 'acc-cash',
        'debit_minor': firstDebit,
        'credit_minor': 0,
        'cashbox_id': isExpense ? null : input.cashboxId,
        'currency_code': input.currencyCode,
        'rate_ppm': input.ratePpm,
      });
      await txn.insert('journal_lines', {
        'id': await _database.newId(),
        'journal_entry_id': journalId,
        'account_id': isExpense ? 'acc-cash' : primaryAccount,
        'debit_minor': 0,
        'credit_minor': input.amountMinor,
        'cashbox_id': isExpense ? input.cashboxId : null,
        'currency_code': input.currencyCode,
        'rate_ppm': input.ratePpm,
      });
      await _database.audit(
        txn,
        userId: actor.id,
        action: isExpense ? 'expense.posted' : 'other_income.posted',
        entityType: isExpense ? 'expense' : 'other_income',
        entityId: id,
        afterJson: 'document=$documentNo; amount=${input.amountMinor}',
      );
    });
    return id;
  }

  Future<List<Map<String, Object?>>> list({
    String search = '',
    int limit = 100,
  }) {
    final pattern = '%${search.trim()}%';
    return _database.raw.rawQuery(
      '''SELECT id, document_no, category, expense_date AS operation_date, cashbox_id,
                amount_minor, currency_code, payee AS party_name, description, status,
                'expense' AS operation_type FROM expenses
          WHERE document_no LIKE ? OR category LIKE ? OR payee LIKE ?
          UNION ALL
          SELECT id, document_no, category, income_date AS operation_date, cashbox_id,
                amount_minor, currency_code, payer AS party_name, description, status,
                'income' AS operation_type FROM other_incomes
          WHERE document_no LIKE ? OR category LIKE ? OR payer LIKE ?
          ORDER BY operation_date DESC, document_no DESC LIMIT ?''',
      [pattern, pattern, pattern, pattern, pattern, pattern, limit],
    );
  }
}
