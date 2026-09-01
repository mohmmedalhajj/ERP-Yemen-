import '../../core/db/erp_database.dart';

class DashboardMetrics {
  const DashboardMetrics({
    required this.salesToday,
    required this.purchasesToday,
    required this.expensesToday,
    required this.cashBalance,
    required this.customerDebt,
    required this.supplierDue,
    required this.lowStockCount,
  });

  final int salesToday;
  final int purchasesToday;
  final int expensesToday;
  final int cashBalance;
  final int customerDebt;
  final int supplierDue;
  final int lowStockCount;
}

class ReportRepository {
  ReportRepository(this._database);
  final ErpDatabase _database;

  Future<DashboardMetrics> dashboard(DateTime date, {DateTime? from, DateTime? to, String currencyCode = 'YER'}) async {
    final start = _date(from ?? date);
    final end = _date(to ?? date);
    final currency = ' AND currency_code = ?';
    final currencyArgs = <Object?>[currencyCode];
    final queries = await Future.wait([
      _singleInt("SELECT COALESCE(SUM(total_minor),0) AS value FROM sales_invoices WHERE status = 'posted' AND invoice_date BETWEEN ? AND ?$currency", [start, end, ...currencyArgs]),
      _singleInt("SELECT COALESCE(SUM(total_minor),0) AS value FROM purchase_invoices WHERE status = 'posted' AND invoice_date BETWEEN ? AND ?$currency", [start, end, ...currencyArgs]),
      _singleInt("SELECT COALESCE(SUM(amount_minor),0) AS value FROM expenses WHERE status = 'posted' AND expense_date BETWEEN ? AND ?$currency", [start, end, ...currencyArgs]),
      _singleInt("SELECT COALESCE(SUM(amount_minor),0) AS value FROM cash_movements WHERE substr(occurred_at, 1, 10) BETWEEN ? AND ?$currency", [start, end, ...currencyArgs]),
      _singleInt("SELECT COALESCE(SUM(due_minor),0) AS value FROM sales_invoices WHERE status = 'posted' AND invoice_date BETWEEN ? AND ?$currency", [start, end, ...currencyArgs]),
      _singleInt("SELECT COALESCE(SUM(due_minor),0) AS value FROM purchase_invoices WHERE status = 'posted' AND invoice_date BETWEEN ? AND ?$currency", [start, end, ...currencyArgs]),
      _singleInt('''SELECT COUNT(*) AS value FROM inventory_balances ib
        JOIN products p ON p.id = ib.product_id
        WHERE p.active = 1 AND ib.quantity_minor <= p.reorder_point_minor''', const []),
    ]);
    return DashboardMetrics(
      salesToday: queries[0],
      purchasesToday: queries[1],
      expensesToday: queries[2],
      cashBalance: queries[3],
      customerDebt: queries[4],
      supplierDue: queries[5],
      lowStockCount: queries[6],
    );
  }

  Future<List<Map<String, Object?>>> salesReport({
    DateTime? from,
    DateTime? to,
    String currencyCode = 'YER',
  }) {
    final currency = ' AND s.currency_code = ?';
    final args = <Object?>[
      _date(from ?? DateTime.now().subtract(const Duration(days: 30))),
      _date(to ?? DateTime.now()),
      currencyCode,
    ];
    return _database.raw.rawQuery(
      '''SELECT s.invoice_no, s.invoice_date, s.total_minor, s.paid_minor, s.due_minor, s.currency_code, c.name AS customer_name,
          u.display_name AS user_name FROM sales_invoices s
          LEFT JOIN customers c ON c.id = s.customer_id LEFT JOIN users u ON u.id = s.created_by
          WHERE s.status = 'posted' AND s.invoice_date BETWEEN ? AND ?$currency ORDER BY s.invoice_date DESC, s.invoice_no DESC''',
      args,
    );
  }

  Future<List<Map<String, Object?>>>
  inventoryReport() => _database.raw.rawQuery(
    '''SELECT p.sku, p.name_ar, w.name_ar AS warehouse_name, ib.quantity_minor, ib.average_cost_minor,
          (ib.quantity_minor * ib.average_cost_minor) AS inventory_value_minor
          FROM inventory_balances ib JOIN products p ON p.id = ib.product_id JOIN warehouses w ON w.id = ib.warehouse_id
          ORDER BY p.name_ar''',
  );

  Future<List<Map<String, Object?>>> trialBalance() => _database.raw.rawQuery(
    '''SELECT a.code, a.name_ar,
          COALESCE(SUM(jl.debit_minor),0) AS debit_minor, COALESCE(SUM(jl.credit_minor),0) AS credit_minor
          FROM accounts a LEFT JOIN journal_lines jl ON jl.account_id = a.id
          LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id AND je.status = 'posted'
          GROUP BY a.id HAVING debit_minor <> 0 OR credit_minor <> 0 ORDER BY a.code''',
  );

  Future<List<Map<String, Object?>>> auditLog({
    int limit = 100,
  }) => _database.raw.rawQuery(
    '''SELECT a.*, u.display_name FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id
        ORDER BY a.created_at DESC LIMIT ?''',
    [limit],
  );

  Future<int> _singleInt(String sql, List<Object?> args) async {
    final rows = await _database.raw.rawQuery(sql, args);
    final value = rows.first['value'];
    return value is int ? value : (value as num).toInt();
  }

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);
}
