import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';
import '../../core/services/license_service.dart';
import '../../data/repositories/auth_repository.dart';

class ReturnPostingService {
  ReturnPostingService(this._database, {LicenseService? licenseService})
    : _licenseService = licenseService ?? LicenseService(_database);

  final ErpDatabase _database;
  final LicenseService _licenseService;

  Future<String> postSaleReturn({
    required AuthUser actor,
    required String originalInvoiceId,
    required String originalLineId,
    required int quantityMinor,
    String? notes,
  }) async {
    final license = await _licenseService.currentStatus();
    if (!license.permitsNewTransactions) throw StateError(license.message);
    requirePermission(actor.permissions, Permissions.salesPost);
    if (quantityMinor <= 0)
      throw ArgumentError('كمية المرتجع يجب أن تكون أكبر من صفر');
    final id = await _database.newId();
    final now = DateTime.now().toUtc();
    await _database.transaction((txn) async {
      final original = await _loadHeader(
        txn,
        'sales_invoices',
        originalInvoiceId,
      );
      if (original['status'] != 'posted' ||
          original['original_invoice_id'] != null) {
        throw StateError('يمكن الإرجاع من فاتورة مبيعات مرحلة أصلية فقط');
      }
      final line = await _loadLine(
        txn,
        'sales_lines',
        originalLineId,
        originalInvoiceId,
      );
      final originalQty = line['quantity_minor'] as int;
      final returned = line['returned_qty_minor'] as int;
      if (quantityMinor > originalQty - returned)
        throw StateError('كمية المرتجع أكبر من الكمية المتبقية في الفاتورة');
      final gross = (line['unit_price_minor'] as int) * quantityMinor;
      final discount =
          ((line['discount_minor'] as int) * quantityMinor) ~/ originalQty;
      final tax = ((line['tax_minor'] as int) * quantityMinor) ~/ originalQty;
      final total = gross - discount + tax;
      final refund = await _availableSaleRefund(
        txn,
        originalInvoiceId,
        original['paid_minor'] as int,
        total,
      );
      final originalNo = original['invoice_no'] as String;
      final number = await _database.nextDocumentNumber(
        txn,
        documentType: 'sale_return',
        branchId: actor.branchId,
        prefix: 'SRT',
      );
      await txn.insert('sales_invoices', {
        'id': id,
        'invoice_no': number,
        'branch_id': original['branch_id'],
        'warehouse_id': original['warehouse_id'],
        'customer_id': original['customer_id'],
        'cashbox_id': original['cashbox_id'],
        'status': 'posted',
        'sale_type': 'return',
        'invoice_date': now.toIso8601String().substring(0, 10),
        'currency_code': original['currency_code'],
        'rate_ppm': original['rate_ppm'],
        'subtotal_minor': -gross,
        'discount_minor': -discount,
        'tax_minor': -tax,
        'total_minor': -total,
        'paid_minor': -refund,
        'due_minor': -(total - refund),
        'cost_minor':
            -((line['unit_cost_minor'] as int) *
                quantityMinor *
                (line['conversion_factor'] as int)),
        'original_invoice_id': originalInvoiceId,
        'created_by': actor.id,
        'posted_at': now.toIso8601String(),
        'notes': notes?.trim(),
      });
      await txn.insert('sales_lines', {
        'id': await _database.newId(),
        'invoice_id': id,
        'product_id': line['product_id'],
        'unit_id': line['unit_id'],
        'quantity_minor': quantityMinor,
        'conversion_factor': line['conversion_factor'],
        'unit_price_minor': line['unit_price_minor'],
        'discount_minor': discount,
        'tax_rate_basis_points': line['tax_rate_basis_points'],
        'tax_minor': -tax,
        'line_total_minor': -total,
        'unit_cost_minor': line['unit_cost_minor'],
      });
      await txn.update(
        'sales_lines',
        {'returned_qty_minor': returned + quantityMinor},
        where: 'id = ?',
        whereArgs: [originalLineId],
      );
      await _increaseStock(
        txn,
        productId: line['product_id'] as String,
        warehouseId: original['warehouse_id'] as String,
        quantityMinor: quantityMinor * (line['conversion_factor'] as int),
        unitCostMinor: line['unit_cost_minor'] as int,
        sourceId: id,
        userId: actor.id,
        type: 'sale_return',
      );
      if (refund > 0 && original['cashbox_id'] != null) {
        await txn.insert('cash_movements', {
          'id': await _database.newId(),
          'cashbox_id': original['cashbox_id'],
          'movement_type': 'sale_refund',
          'amount_minor': -refund,
          'currency_code': original['currency_code'],
          'rate_ppm': original['rate_ppm'],
          'source_type': 'sale_return',
          'source_id': id,
          'occurred_at': now.toIso8601String(),
          'description': 'رد مبيعات من $originalNo',
          'user_id': actor.id,
        });
      }
      await _postSaleReturnJournal(
        txn,
        actor: actor,
        returnId: id,
        number: number,
        date: now,
        netMinor: gross - discount,
        taxMinor: tax,
        refundMinor: refund,
        creditMinor: total - refund,
        costMinor:
            (line['unit_cost_minor'] as int) *
            quantityMinor *
            (line['conversion_factor'] as int),
        customerId: original['customer_id'] as String?,
        cashboxId: original['cashbox_id'] as String?,
        currency: original['currency_code'] as String,
        rate: original['rate_ppm'] as int,
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'sale_return.posted',
        entityType: 'sales_invoice',
        entityId: id,
        afterJson: 'original=$originalNo; total=$total',
      );
    });
    return id;
  }

  Future<String> postPurchaseReturn({
    required AuthUser actor,
    required String originalInvoiceId,
    required String originalLineId,
    required int quantityMinor,
    String? notes,
  }) async {
    final license = await _licenseService.currentStatus();
    if (!license.permitsNewTransactions) throw StateError(license.message);
    requirePermission(actor.permissions, Permissions.purchasesPost);
    requirePermission(actor.permissions, Permissions.inventoryManage);
    if (quantityMinor <= 0)
      throw ArgumentError('كمية المرتجع يجب أن تكون أكبر من صفر');
    final id = await _database.newId();
    final now = DateTime.now().toUtc();
    await _database.transaction((txn) async {
      final original = await _loadHeader(
        txn,
        'purchase_invoices',
        originalInvoiceId,
      );
      if (original['status'] != 'posted' ||
          original['original_invoice_id'] != null)
        throw StateError('يمكن الإرجاع من فاتورة مشتريات مرحلة أصلية فقط');
      final line = await _loadLine(
        txn,
        'purchase_lines',
        originalLineId,
        originalInvoiceId,
      );
      final originalQty = line['quantity_minor'] as int;
      final gross = (line['unit_cost_minor'] as int) * quantityMinor;
      final tax = ((line['tax_minor'] as int) * quantityMinor) ~/ originalQty;
      final total = gross + tax;
      final stockQty = quantityMinor * (line['conversion_factor'] as int);
      await _decreaseStock(
        txn,
        productId: line['product_id'] as String,
        warehouseId: original['warehouse_id'] as String,
        quantityMinor: stockQty,
        unitCostMinor: line['unit_cost_minor'] as int,
        sourceId: id,
        userId: actor.id,
        type: 'purchase_return',
      );
      final number = await _database.nextDocumentNumber(
        txn,
        documentType: 'purchase_return',
        branchId: actor.branchId,
        prefix: 'PRT',
      );
      await txn.insert('purchase_invoices', {
        'id': id,
        'invoice_no': number,
        'branch_id': original['branch_id'],
        'warehouse_id': original['warehouse_id'],
        'supplier_id': original['supplier_id'],
        'cashbox_id': original['cashbox_id'],
        'status': 'posted',
        'purchase_type': 'return',
        'invoice_date': now.toIso8601String().substring(0, 10),
        'currency_code': original['currency_code'],
        'rate_ppm': original['rate_ppm'],
        'subtotal_minor': -gross,
        'discount_minor': 0,
        'tax_minor': -tax,
        'extra_cost_minor': 0,
        'total_minor': -total,
        'paid_minor': -total,
        'due_minor': 0,
        'original_invoice_id': originalInvoiceId,
        'created_by': actor.id,
        'posted_at': now.toIso8601String(),
        'notes': notes?.trim(),
      });
      await txn.insert('purchase_lines', {
        'id': await _database.newId(),
        'invoice_id': id,
        'product_id': line['product_id'],
        'unit_id': line['unit_id'],
        'quantity_minor': quantityMinor,
        'conversion_factor': line['conversion_factor'],
        'unit_cost_minor': line['unit_cost_minor'],
        'discount_minor': 0,
        'allocated_extra_cost_minor': 0,
        'tax_rate_basis_points': line['tax_rate_basis_points'],
        'tax_minor': -tax,
        'line_total_minor': -total,
      });
      if (original['cashbox_id'] != null) {
        await txn.insert('cash_movements', {
          'id': await _database.newId(),
          'cashbox_id': original['cashbox_id'],
          'movement_type': 'purchase_refund',
          'amount_minor': total,
          'currency_code': original['currency_code'],
          'rate_ppm': original['rate_ppm'],
          'source_type': 'purchase_return',
          'source_id': id,
          'occurred_at': now.toIso8601String(),
          'description': 'تحصيل مرتجع مشتريات $number',
          'user_id': actor.id,
        });
      }
      await _postPurchaseReturnJournal(
        txn,
        actor: actor,
        returnId: id,
        number: number,
        date: now,
        totalMinor: total,
        supplierId: original['supplier_id'] as String?,
        cashboxId: original['cashbox_id'] as String?,
        currency: original['currency_code'] as String,
        rate: original['rate_ppm'] as int,
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'purchase_return.posted',
        entityType: 'purchase_invoice',
        entityId: id,
      );
    });
    return id;
  }

  Future<Map<String, Object?>> _loadHeader(
    dynamic txn,
    String table,
    String id,
  ) async {
    final rows = await txn.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('الفاتورة الأصلية غير موجودة');
    return rows.first;
  }

  Future<Map<String, Object?>> _loadLine(
    dynamic txn,
    String table,
    String lineId,
    String invoiceId,
  ) async {
    final rows = await txn.query(
      table,
      where: 'id = ? AND invoice_id = ?',
      whereArgs: [lineId, invoiceId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('سطر الفاتورة غير موجود');
    return rows.first;
  }

  Future<int> _availableSaleRefund(
    dynamic txn,
    String originalId,
    int originallyPaid,
    int requested,
  ) async {
    final rows = await txn.rawQuery(
      'SELECT COALESCE(SUM(-paid_minor), 0) AS refunded FROM sales_invoices WHERE original_invoice_id = ? AND sale_type = ?',
      [originalId, 'return'],
    );
    final refunded = rows.first['refunded'] as int;
    final remaining = originallyPaid - refunded;
    return requested < remaining
        ? requested
        : remaining < 0
        ? 0
        : remaining;
  }

  Future<void> _increaseStock(
    dynamic txn, {
    required String productId,
    required String warehouseId,
    required int quantityMinor,
    required int unitCostMinor,
    required String sourceId,
    required String userId,
    required String type,
  }) async {
    final rows = await txn.query(
      'inventory_balances',
      where: 'product_id = ? AND warehouse_id = ?',
      whereArgs: [productId, warehouseId],
      limit: 1,
    );
    final oldQty = rows.isEmpty ? 0 : rows.first['quantity_minor'] as int;
    final oldCost = rows.isEmpty
        ? unitCostMinor
        : rows.first['average_cost_minor'] as int;
    final next = oldQty + quantityMinor;
    final cost = next == 0
        ? 0
        : ((oldQty * oldCost) + (quantityMinor * unitCostMinor)) ~/ next;
    if (rows.isEmpty) {
      await txn.insert('inventory_balances', {
        'id': await _database.newId(),
        'product_id': productId,
        'warehouse_id': warehouseId,
        'quantity_minor': next,
        'average_cost_minor': cost,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      await txn.update(
        'inventory_balances',
        {
          'quantity_minor': next,
          'average_cost_minor': cost,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
    await txn.insert('inventory_movements', {
      'id': await _database.newId(),
      'product_id': productId,
      'warehouse_id': warehouseId,
      'movement_type': type,
      'quantity_minor': quantityMinor,
      'unit_cost_minor': unitCostMinor,
      'balance_after_minor': next,
      'source_type': type,
      'source_id': sourceId,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'user_id': userId,
    });
  }

  Future<void> _decreaseStock(
    dynamic txn, {
    required String productId,
    required String warehouseId,
    required int quantityMinor,
    required int unitCostMinor,
    required String sourceId,
    required String userId,
    required String type,
  }) async {
    final rows = await txn.query(
      'inventory_balances',
      where: 'product_id = ? AND warehouse_id = ?',
      whereArgs: [productId, warehouseId],
      limit: 1,
    );
    if (rows.isEmpty || (rows.first['quantity_minor'] as int) < quantityMinor)
      throw StateError('رصيد المخزون غير كافٍ لتنفيذ مرتجع المشتريات');
    final next = (rows.first['quantity_minor'] as int) - quantityMinor;
    await txn.update(
      'inventory_balances',
      {
        'quantity_minor': next,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    await txn.insert('inventory_movements', {
      'id': await _database.newId(),
      'product_id': productId,
      'warehouse_id': warehouseId,
      'movement_type': type,
      'quantity_minor': -quantityMinor,
      'unit_cost_minor': unitCostMinor,
      'balance_after_minor': next,
      'source_type': type,
      'source_id': sourceId,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'user_id': userId,
    });
  }

  Future<void> _postSaleReturnJournal(
    dynamic txn, {
    required AuthUser actor,
    required String returnId,
    required String number,
    required DateTime date,
    required int netMinor,
    required int taxMinor,
    required int refundMinor,
    required int creditMinor,
    required int costMinor,
    required String? customerId,
    required String? cashboxId,
    required String currency,
    required int rate,
  }) async {
    final journal = await _createJournal(
      txn,
      actor,
      'sale_return',
      returnId,
      'قيد مرتجع مبيعات $number',
      date,
    );
    await _line(
      txn,
      journal,
      'acc-sales',
      debit: netMinor,
      currency: currency,
      rate: rate,
    );
    if (taxMinor > 0)
      await _line(
        txn,
        journal,
        'acc-tax',
        debit: taxMinor,
        currency: currency,
        rate: rate,
      );
    if (refundMinor > 0)
      await _line(
        txn,
        journal,
        'acc-cash',
        credit: refundMinor,
        cashboxId: cashboxId,
        currency: currency,
        rate: rate,
      );
    if (creditMinor > 0)
      await _line(
        txn,
        journal,
        'acc-ar',
        credit: creditMinor,
        customerId: customerId,
        currency: currency,
        rate: rate,
      );
    if (costMinor > 0) {
      await _line(
        txn,
        journal,
        'acc-inventory',
        debit: costMinor,
        currency: currency,
        rate: rate,
      );
      await _line(
        txn,
        journal,
        'acc-cogs',
        credit: costMinor,
        currency: currency,
        rate: rate,
      );
    }
  }

  Future<void> _postPurchaseReturnJournal(
    dynamic txn, {
    required AuthUser actor,
    required String returnId,
    required String number,
    required DateTime date,
    required int totalMinor,
    required String? supplierId,
    required String? cashboxId,
    required String currency,
    required int rate,
  }) async {
    final journal = await _createJournal(
      txn,
      actor,
      'purchase_return',
      returnId,
      'قيد مرتجع مشتريات $number',
      date,
    );
    if (cashboxId != null) {
      await _line(
        txn,
        journal,
        'acc-cash',
        debit: totalMinor,
        cashboxId: cashboxId,
        currency: currency,
        rate: rate,
      );
    } else {
      await _line(
        txn,
        journal,
        'acc-ap',
        debit: totalMinor,
        supplierId: supplierId,
        currency: currency,
        rate: rate,
      );
    }
    await _line(
      txn,
      journal,
      'acc-inventory',
      credit: totalMinor,
      currency: currency,
      rate: rate,
    );
  }

  Future<String> _createJournal(
    dynamic txn,
    AuthUser actor,
    String sourceType,
    String sourceId,
    String description,
    DateTime date,
  ) async {
    final id = await _database.newId();
    final no = await _database.nextDocumentNumber(
      txn,
      documentType: 'JRN',
      branchId: actor.branchId,
      prefix: 'QYD',
    );
    await txn.insert('journal_entries', {
      'id': id,
      'entry_no': no,
      'entry_date': date.toIso8601String().substring(0, 10),
      'status': 'posted',
      'source_type': sourceType,
      'source_id': sourceId,
      'description': description,
      'created_by': actor.id,
      'posted_by': actor.id,
      'posted_at': date.toIso8601String(),
      'created_at': date.toIso8601String(),
    });
    return id;
  }

  Future<void> _line(
    dynamic txn,
    String journalId,
    String accountId, {
    int debit = 0,
    int credit = 0,
    String? customerId,
    String? supplierId,
    String? cashboxId,
    required String currency,
    required int rate,
  }) async {
    if (debit == 0 && credit == 0) return;
    await txn.insert('journal_lines', {
      'id': await _database.newId(),
      'journal_entry_id': journalId,
      'account_id': accountId,
      'debit_minor': debit,
      'credit_minor': credit,
      'currency_code': currency,
      'rate_ppm': rate,
      'customer_id': customerId,
      'supplier_id': supplierId,
      'cashbox_id': cashboxId,
    });
  }
}
