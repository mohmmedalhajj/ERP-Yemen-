import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';
import '../../core/models/money.dart';
import '../../core/services/license_service.dart';
import '../../data/repositories/auth_repository.dart';

class InvoiceLineInput {
  const InvoiceLineInput({
    required this.productId,
    required this.unitId,
    required this.quantityMinor,
    required this.conversionFactor,
    required this.unitAmountMinor,
    this.discountMinor = 0,
    this.taxRateBasisPoints = 0,
    this.batchNo,
    this.productionDate,
    this.expiryDate,
  });

  final String productId;
  final String unitId;
  final int quantityMinor;
  final int conversionFactor;
  final int unitAmountMinor;
  final int discountMinor;
  final int taxRateBasisPoints;
  final String? batchNo;
  final String? productionDate;
  final String? expiryDate;

  int get stockQuantityMinor => quantityMinor * conversionFactor;

  int get grossMinor => quantityMinor * unitAmountMinor;

  int get netBeforeTaxMinor {
    if (quantityMinor <= 0 || conversionFactor <= 0 || unitAmountMinor < 0) {
      throw ArgumentError('بيانات سطر الفاتورة غير صالحة');
    }
    if (discountMinor < 0 || discountMinor > grossMinor) {
      throw ArgumentError('خصم السطر غير صالح');
    }
    return grossMinor - discountMinor;
  }

  int get taxMinor =>
      FinancialRounding.percentageOf(netBeforeTaxMinor, taxRateBasisPoints);
  int get totalMinor => netBeforeTaxMinor + taxMinor;
}

class InvoiceTotals {
  const InvoiceTotals({
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
  });

  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int totalMinor;

  factory InvoiceTotals.fromLines(List<InvoiceLineInput> lines) {
    if (lines.isEmpty) throw ArgumentError('لا يمكن ترحيل فاتورة بلا أصناف');
    var subtotal = 0;
    var discount = 0;
    var tax = 0;
    for (final line in lines) {
      subtotal += line.grossMinor;
      discount += line.discountMinor;
      tax += line.taxMinor;
    }
    return InvoiceTotals(
      subtotalMinor: subtotal,
      discountMinor: discount,
      taxMinor: tax,
      totalMinor: subtotal - discount + tax,
    );
  }
}

class PostedDocument {
  const PostedDocument(this.id, this.number, this.totalMinor);
  final String id;
  final String number;
  final int totalMinor;
}

class SalePostingInput {
  const SalePostingInput({
    required this.branchId,
    required this.warehouseId,
    required this.cashboxId,
    this.customerId,
    required this.invoiceDate,
    required this.currencyCode,
    this.ratePpm = 1000000,
    required this.paidMinor,
    required this.lines,
    this.notes,
  });

  final String branchId;
  final String warehouseId;
  final String cashboxId;
  final String? customerId;
  final DateTime invoiceDate;
  final String currencyCode;
  final int ratePpm;
  final int paidMinor;
  final List<InvoiceLineInput> lines;
  final String? notes;
}

class PurchasePostingInput {
  const PurchasePostingInput({
    required this.branchId,
    required this.warehouseId,
    required this.cashboxId,
    this.supplierId,
    required this.invoiceDate,
    required this.currencyCode,
    this.ratePpm = 1000000,
    required this.paidMinor,
    this.extraCostMinor = 0,
    required this.lines,
    this.notes,
  });

  final String branchId;
  final String warehouseId;
  final String cashboxId;
  final String? supplierId;
  final DateTime invoiceDate;
  final String currencyCode;
  final int ratePpm;
  final int paidMinor;
  final int extraCostMinor;
  final List<InvoiceLineInput> lines;
  final String? notes;
}

class InvoicePostingService {
  InvoicePostingService(this._database, {LicenseService? licenseService})
    : _licenseService = licenseService ?? LicenseService(_database);

  final ErpDatabase _database;
  final LicenseService _licenseService;

  Future<PostedDocument> postSale({
    required AuthUser actor,
    required SalePostingInput input,
  }) async {
    final license = await _licenseService.currentStatus();
    if (!license.permitsNewTransactions) {
      throw StateError(license.message);
    }
    requirePermission(actor.permissions, Permissions.salesCreate);
    requirePermission(actor.permissions, Permissions.salesPost);
    final totals = InvoiceTotals.fromLines(input.lines);
    if (input.paidMinor < 0 ||
        input.paidMinor > totals.totalMinor ||
        input.ratePpm <= 0) {
      throw ArgumentError('قيمة الدفع أو سعر الصرف غير صالح');
    }
    final due = totals.totalMinor - input.paidMinor;
    if (due > 0 && input.customerId == null) {
      throw StateError('يلزم تحديد عميل عند وجود مبلغ آجل');
    }
    final invoiceId = await _database.newId();
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.transaction((txn) async {
      await _ensureOpenPeriod(txn, input.invoiceDate);
      if (due > 0 && input.customerId != null) {
        await _ensureCustomerCredit(txn, input.customerId!, due);
      }
      final invoiceNo = await _database.nextDocumentNumber(
        txn,
        documentType: 'sale',
        branchId: input.branchId,
        prefix: 'SAL',
      );
      var costTotal = 0;
      final prepared = <_PreparedSaleLine>[];
      final preventNegative = await _readSetting(
        txn,
        'prevent_negative_stock',
        fallback: '1',
      );
      for (final line in input.lines) {
        final productRows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [line.productId],
          limit: 1,
        );
        if (productRows.isEmpty || (productRows.first['active'] as int) != 1) {
          throw StateError('الصنف غير موجود أو موقوف');
        }
        final product = productRows.first;
        final productType = product['product_type'] as String;
        var unitCost = 0;
        var newQuantity = 0;
        var batchAllocations = const <_BatchAllocation>[];
        if (productType == 'stock') {
          final balanceRows = await txn.query(
            'inventory_balances',
            where: 'product_id = ? AND warehouse_id = ?',
            whereArgs: [line.productId, input.warehouseId],
            limit: 1,
          );
          final currentQty = balanceRows.isEmpty
              ? 0
              : balanceRows.first['quantity_minor'] as int;
          final averageCost = balanceRows.isEmpty
              ? 0
              : balanceRows.first['average_cost_minor'] as int;
          final allocation = await _allocateSaleBatches(
            txn,
            productId: line.productId,
            warehouseId: input.warehouseId,
            quantityMinor: line.stockQuantityMinor,
            averageCostMinor: averageCost,
            preventNegative: preventNegative == '1',
          );
          batchAllocations = allocation.allocations;
          unitCost = allocation.unitCostMinor;
          newQuantity = currentQty - line.stockQuantityMinor;
          if (newQuantity < 0 && preventNegative == '1') {
            throw StateError('المخزون غير كافٍ للصنف ${product['name_ar']}');
          }
          costTotal += allocation.costMinor;
          prepared.add(
            _PreparedSaleLine(
              line,
              currentQty,
              newQuantity,
              unitCost,
              productType,
              batchAllocations,
            ),
          );
        } else {
          prepared.add(_PreparedSaleLine(line, 0, 0, 0, productType, const []));
        }
      }
      await txn.insert('sales_invoices', {
        'id': invoiceId,
        'invoice_no': invoiceNo,
        'branch_id': input.branchId,
        'warehouse_id': input.warehouseId,
        'customer_id': input.customerId,
        'cashbox_id': input.cashboxId,
        'status': 'posted',
        'sale_type': due == 0
            ? 'cash'
            : (input.paidMinor == 0 ? 'credit' : 'partial'),
        'invoice_date': _date(input.invoiceDate),
        'currency_code': input.currencyCode,
        'rate_ppm': input.ratePpm,
        'subtotal_minor': totals.subtotalMinor,
        'discount_minor': totals.discountMinor,
        'tax_minor': totals.taxMinor,
        'total_minor': totals.totalMinor,
        'paid_minor': input.paidMinor,
        'due_minor': due,
        'cost_minor': costTotal,
        'created_by': actor.id,
        'posted_at': now,
        'notes': input.notes,
      });
      for (final item in prepared) {
        final lineId = await _database.newId();
        await txn.insert('sales_lines', {
          'id': lineId,
          'invoice_id': invoiceId,
          'product_id': item.input.productId,
          'unit_id': item.input.unitId,
          'quantity_minor': item.input.quantityMinor,
          'conversion_factor': item.input.conversionFactor,
          'unit_price_minor': item.input.unitAmountMinor,
          'discount_minor': item.input.discountMinor,
          'tax_rate_basis_points': item.input.taxRateBasisPoints,
          'tax_minor': item.input.taxMinor,
          'line_total_minor': item.input.totalMinor,
          'unit_cost_minor': item.unitCostMinor,
        });
        if (item.productType == 'stock') {
          final balanceRows = await txn.query(
            'inventory_balances',
            where: 'product_id = ? AND warehouse_id = ?',
            whereArgs: [item.input.productId, input.warehouseId],
            limit: 1,
          );
          if (balanceRows.isEmpty) {
            await txn.insert('inventory_balances', {
              'id': await _database.newId(),
              'product_id': item.input.productId,
              'warehouse_id': input.warehouseId,
              'quantity_minor': item.newQuantityMinor,
              'average_cost_minor': item.unitCostMinor,
              'updated_at': now,
            });
          } else {
            await txn.update(
              'inventory_balances',
              {'quantity_minor': item.newQuantityMinor, 'updated_at': now},
              where: 'id = ?',
              whereArgs: [balanceRows.first['id']],
            );
          }
          for (final allocation in item.batchAllocations) {
            if (allocation.batchId != null) {
              final batchRows = await txn.query(
                'stock_batches',
                where: 'id = ? AND active = 1 AND quantity_minor >= ?',
                whereArgs: [allocation.batchId, allocation.quantityMinor],
                limit: 1,
              );
              if (batchRows.isEmpty)
                throw StateError('تغيرت كمية الدفعة أثناء الترحيل');
              final remainingBatch =
                  (batchRows.first['quantity_minor'] as int) -
                  allocation.quantityMinor;
              await txn.update(
                'stock_batches',
                {
                  'quantity_minor': remainingBatch,
                  'active': remainingBatch > 0 ? 1 : 0,
                },
                where: 'id = ?',
                whereArgs: [allocation.batchId],
              );
            }
            await txn.insert('inventory_movements', {
              'id': await _database.newId(),
              'product_id': item.input.productId,
              'warehouse_id': input.warehouseId,
              'batch_id': allocation.batchId,
              'movement_type': 'sale',
              'quantity_minor': -allocation.quantityMinor,
              'unit_cost_minor': allocation.unitCostMinor,
              'balance_after_minor': item.newQuantityMinor,
              'source_type': 'sale',
              'source_id': invoiceId,
              'occurred_at': now,
              'user_id': actor.id,
            });
          }
        }
      }
      if (input.paidMinor > 0) {
        await txn.insert('cash_movements', {
          'id': await _database.newId(),
          'cashbox_id': input.cashboxId,
          'movement_type': 'sale_receipt',
          'amount_minor': input.paidMinor,
          'currency_code': input.currencyCode,
          'rate_ppm': input.ratePpm,
          'source_type': 'sale',
          'source_id': invoiceId,
          'occurred_at': now,
          'description': 'تحصيل فاتورة $invoiceNo',
          'user_id': actor.id,
        });
      }
      await _postSaleJournal(
        txn,
        actor: actor,
        invoiceId: invoiceId,
        invoiceNo: invoiceNo,
        date: input.invoiceDate,
        paidMinor: input.paidMinor,
        dueMinor: due,
        netSalesMinor: totals.subtotalMinor - totals.discountMinor,
        taxMinor: totals.taxMinor,
        costMinor: costTotal,
        customerId: input.customerId,
        cashboxId: input.cashboxId,
        currencyCode: input.currencyCode,
        ratePpm: input.ratePpm,
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'sale.posted',
        entityType: 'sales_invoice',
        entityId: invoiceId,
        afterJson:
            '{"invoice_no":"$invoiceNo","total_minor":${totals.totalMinor}}',
      );
      return PostedDocument(invoiceId, invoiceNo, totals.totalMinor);
    });
  }

  Future<PostedDocument> postPurchase({
    required AuthUser actor,
    required PurchasePostingInput input,
  }) async {
    final license = await _licenseService.currentStatus();
    if (!license.permitsNewTransactions) {
      throw StateError(license.message);
    }
    requirePermission(actor.permissions, Permissions.purchasesCreate);
    requirePermission(actor.permissions, Permissions.purchasesPost);
    final totals = InvoiceTotals.fromLines(input.lines);
    if (input.extraCostMinor < 0 || input.paidMinor < 0 || input.ratePpm <= 0) {
      throw ArgumentError('قيم فاتورة الشراء غير صالحة');
    }
    final invoiceTotal = totals.totalMinor + input.extraCostMinor;
    if (input.paidMinor > invoiceTotal)
      throw ArgumentError('الدفعة أكبر من إجمالي الفاتورة');
    final due = invoiceTotal - input.paidMinor;
    if (due > 0 && input.supplierId == null)
      throw StateError('يلزم تحديد مورد للمبلغ الآجل');
    final invoiceId = await _database.newId();
    final now = DateTime.now().toUtc().toIso8601String();
    return _database.transaction((txn) async {
      await _ensureOpenPeriod(txn, input.invoiceDate);
      final invoiceNo = await _database.nextDocumentNumber(
        txn,
        documentType: 'purchase',
        branchId: input.branchId,
        prefix: 'PUR',
      );
      final allocations = _allocateExtraCost(input.lines, input.extraCostMinor);
      await txn.insert('purchase_invoices', {
        'id': invoiceId,
        'invoice_no': invoiceNo,
        'branch_id': input.branchId,
        'warehouse_id': input.warehouseId,
        'supplier_id': input.supplierId,
        'cashbox_id': input.cashboxId,
        'status': 'posted',
        'purchase_type': due == 0
            ? 'cash'
            : (input.paidMinor == 0 ? 'credit' : 'partial'),
        'invoice_date': _date(input.invoiceDate),
        'currency_code': input.currencyCode,
        'rate_ppm': input.ratePpm,
        'subtotal_minor': totals.subtotalMinor,
        'discount_minor': totals.discountMinor,
        'tax_minor': totals.taxMinor,
        'extra_cost_minor': input.extraCostMinor,
        'total_minor': invoiceTotal,
        'paid_minor': input.paidMinor,
        'due_minor': due,
        'created_by': actor.id,
        'posted_at': now,
        'notes': input.notes,
      });
      for (var index = 0; index < input.lines.length; index++) {
        final line = input.lines[index];
        final productRows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [line.productId],
          limit: 1,
        );
        if (productRows.isEmpty || (productRows.first['active'] as int) != 1)
          throw StateError('الصنف غير موجود أو موقوف');
        final productType = productRows.first['product_type'] as String;
        final allocated = allocations[index];
        await txn.insert('purchase_lines', {
          'id': await _database.newId(),
          'invoice_id': invoiceId,
          'product_id': line.productId,
          'unit_id': line.unitId,
          'quantity_minor': line.quantityMinor,
          'conversion_factor': line.conversionFactor,
          'unit_cost_minor': line.unitAmountMinor,
          'discount_minor': line.discountMinor,
          'allocated_extra_cost_minor': allocated,
          'tax_rate_basis_points': line.taxRateBasisPoints,
          'tax_minor': line.taxMinor,
          'line_total_minor': line.totalMinor,
        });
        if (productType != 'stock') continue;
        final incomingValue = line.totalMinor + allocated;
        final incomingUnitCost = Money.fromRatio(
          incomingValue,
          line.stockQuantityMinor,
        ).minor;
        final balanceRows = await txn.query(
          'inventory_balances',
          where: 'product_id = ? AND warehouse_id = ?',
          whereArgs: [line.productId, input.warehouseId],
          limit: 1,
        );
        final existingQty = balanceRows.isEmpty
            ? 0
            : balanceRows.first['quantity_minor'] as int;
        final existingCost = balanceRows.isEmpty
            ? 0
            : balanceRows.first['average_cost_minor'] as int;
        final newQty = existingQty + line.stockQuantityMinor;
        final newCost = FinancialRounding.weightedAverage(
          existingQuantity: existingQty,
          existingUnitCostMinor: existingCost,
          receivedQuantity: line.stockQuantityMinor,
          receivedUnitCostMinor: incomingUnitCost,
        );
        if (balanceRows.isEmpty) {
          await txn.insert('inventory_balances', {
            'id': await _database.newId(),
            'product_id': line.productId,
            'warehouse_id': input.warehouseId,
            'quantity_minor': newQty,
            'average_cost_minor': newCost,
            'updated_at': now,
          });
        } else {
          await txn.update(
            'inventory_balances',
            {
              'quantity_minor': newQty,
              'average_cost_minor': newCost,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [balanceRows.first['id']],
          );
        }
        final requestedBatchNo = line.batchNo?.trim();
        final batchNo = requestedBatchNo == null || requestedBatchNo.isEmpty
            ? '$invoiceNo-${index + 1}'
            : requestedBatchNo;
        final existingBatchRows = await txn.query(
          'stock_batches',
          where: 'product_id = ? AND warehouse_id = ? AND batch_no = ?',
          whereArgs: [line.productId, input.warehouseId, batchNo],
          limit: 1,
        );
        late String batchId;
        if (existingBatchRows.isEmpty) {
          batchId = await _database.newId();
          await txn.insert('stock_batches', {
            'id': batchId,
            'product_id': line.productId,
            'warehouse_id': input.warehouseId,
            'batch_no': batchNo,
            'quantity_minor': line.stockQuantityMinor,
            'unit_cost_minor': incomingUnitCost,
            'production_date': line.productionDate,
            'expiry_date': line.expiryDate,
            'active': 1,
          });
        } else {
          final existingBatch = existingBatchRows.first;
          batchId = existingBatch['id'] as String;
          final oldQty = (existingBatch['quantity_minor'] as num).toInt();
          final oldCost = (existingBatch['unit_cost_minor'] as num).toInt();
          final batchCost = FinancialRounding.weightedAverage(
            existingQuantity: oldQty,
            existingUnitCostMinor: oldCost,
            receivedQuantity: line.stockQuantityMinor,
            receivedUnitCostMinor: incomingUnitCost,
          );
          await txn.update(
            'stock_batches',
            {
              'quantity_minor': oldQty + line.stockQuantityMinor,
              'unit_cost_minor': batchCost,
              'active': 1,
              if (line.productionDate != null)
                'production_date': line.productionDate,
              if (line.expiryDate != null) 'expiry_date': line.expiryDate,
            },
            where: 'id = ?',
            whereArgs: [batchId],
          );
        }
        await txn.insert('inventory_movements', {
          'id': await _database.newId(),
          'product_id': line.productId,
          'warehouse_id': input.warehouseId,
          'batch_id': batchId,
          'movement_type': 'purchase',
          'quantity_minor': line.stockQuantityMinor,
          'unit_cost_minor': incomingUnitCost,
          'balance_after_minor': newQty,
          'source_type': 'purchase',
          'source_id': invoiceId,
          'occurred_at': now,
          'user_id': actor.id,
        });
      }
      if (input.paidMinor > 0) {
        await txn.insert('cash_movements', {
          'id': await _database.newId(),
          'cashbox_id': input.cashboxId,
          'movement_type': 'purchase_payment',
          'amount_minor': -input.paidMinor,
          'currency_code': input.currencyCode,
          'rate_ppm': input.ratePpm,
          'source_type': 'purchase',
          'source_id': invoiceId,
          'occurred_at': now,
          'description': 'سداد فاتورة $invoiceNo',
          'user_id': actor.id,
        });
      }
      await _postPurchaseJournal(
        txn,
        actor: actor,
        invoiceId: invoiceId,
        invoiceNo: invoiceNo,
        date: input.invoiceDate,
        inventoryMinor: invoiceTotal,
        paidMinor: input.paidMinor,
        dueMinor: due,
        supplierId: input.supplierId,
        cashboxId: input.cashboxId,
        currencyCode: input.currencyCode,
        ratePpm: input.ratePpm,
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'purchase.posted',
        entityType: 'purchase_invoice',
        entityId: invoiceId,
        afterJson: '{"invoice_no":"$invoiceNo","total_minor":$invoiceTotal}',
      );
      return PostedDocument(invoiceId, invoiceNo, invoiceTotal);
    });
  }

  Future<void> _ensureCustomerCredit(
    dynamic txn,
    String customerId,
    int dueMinor,
  ) async {
    final customerRows = await txn.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (customerRows.isEmpty || (customerRows.first['active'] as int) != 1)
      throw StateError('العميل غير موجود أو موقوف');
    final creditLimit = customerRows.first['credit_limit_minor'] as int?;
    if (creditLimit == null) return;
    final existingRows = await txn.rawQuery(
      "SELECT COALESCE(SUM(due_minor), 0) AS total FROM sales_invoices WHERE customer_id = ? AND status = 'posted'",
      [customerId],
    );
    final existing = existingRows.first['total'] as int;
    if (existing + dueMinor > creditLimit)
      throw StateError('تجاوزت الفاتورة الحد الائتماني للعميل');
  }

  Future<void> _ensureOpenPeriod(dynamic txn, DateTime date) async {
    final day = _date(date);
    final rows = await txn.query(
      'fiscal_periods',
      where: 'start_date <= ? AND end_date >= ?',
      whereArgs: [day, day],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('لا توجد فترة مالية تغطي تاريخ المستند');
    if ((rows.first['closed'] as int) == 1)
      throw StateError('الفترة المالية مغلقة');
  }

  Future<String> _readSetting(
    dynamic txn,
    String key, {
    required String fallback,
  }) async {
    final rows = await txn.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  Future<_BatchAllocationResult> _allocateSaleBatches(
    dynamic txn, {
    required String productId,
    required String warehouseId,
    required int quantityMinor,
    required int averageCostMinor,
    required bool preventNegative,
  }) async {
    if (quantityMinor <= 0) throw ArgumentError('كمية البيع غير صالحة');
    final today = _date(DateTime.now());
    final rows = await txn.rawQuery(
      '''SELECT id, quantity_minor, unit_cost_minor FROM stock_batches
         WHERE product_id = ? AND warehouse_id = ? AND active = 1 AND quantity_minor > 0
           AND (expiry_date IS NULL OR expiry_date >= ?)
         ORDER BY CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END,
                  expiry_date ASC, production_date ASC, id ASC''',
      [productId, warehouseId, today],
    );
    var remaining = quantityMinor;
    var cost = 0;
    final allocations = <_BatchAllocation>[];
    for (final row in rows) {
      if (remaining == 0) break;
      final available = (row['quantity_minor'] as num).toInt();
      final take = available < remaining ? available : remaining;
      final unitCost = (row['unit_cost_minor'] as num).toInt();
      allocations.add(_BatchAllocation(row['id'] as String, take, unitCost));
      remaining -= take;
      cost += take * unitCost;
    }
    if (remaining > 0) {
      if (preventNegative) throw StateError('لا توجد دفعات صالحة كافية للبيع');
      allocations.add(_BatchAllocation(null, remaining, averageCostMinor));
      cost += remaining * averageCostMinor;
    }
    return _BatchAllocationResult(
      allocations: allocations,
      costMinor: cost,
      unitCostMinor: Money.fromRatio(cost, quantityMinor).minor,
    );
  }

  List<int> _allocateExtraCost(List<InvoiceLineInput> lines, int total) {
    if (total == 0) return List<int>.filled(lines.length, 0);
    final base = lines.fold<int>(0, (sum, line) => sum + line.totalMinor);
    if (base <= 0)
      throw StateError('لا يمكن توزيع تكلفة إضافية على إجمالي صفر');
    final values = <int>[];
    var allocated = 0;
    for (var i = 0; i < lines.length; i++) {
      final value = i == lines.length - 1
          ? total - allocated
          : Money.fromRatio(total * lines[i].totalMinor, base).minor;
      values.add(value);
      allocated += value;
    }
    return values;
  }

  Future<void> _postSaleJournal(
    dynamic txn, {
    required AuthUser actor,
    required String invoiceId,
    required String invoiceNo,
    required DateTime date,
    required int paidMinor,
    required int dueMinor,
    required int netSalesMinor,
    required int taxMinor,
    required int costMinor,
    required String? customerId,
    required String cashboxId,
    required String currencyCode,
    required int ratePpm,
  }) async {
    final lines = <_JournalLine>[];
    if (paidMinor > 0)
      lines.add(
        _JournalLine('acc-cash', debit: paidMinor, cashboxId: cashboxId),
      );
    if (dueMinor > 0)
      lines.add(
        _JournalLine('acc-ar', debit: dueMinor, customerId: customerId),
      );
    if (netSalesMinor > 0)
      lines.add(_JournalLine('acc-sales', credit: netSalesMinor));
    if (taxMinor > 0) lines.add(_JournalLine('acc-tax', credit: taxMinor));
    if (costMinor > 0) {
      lines.add(_JournalLine('acc-cogs', debit: costMinor));
      lines.add(_JournalLine('acc-inventory', credit: costMinor));
    }
    await _createPostedJournal(
      txn,
      sourceType: 'sale',
      sourceId: invoiceId,
      date: date,
      description: 'فاتورة مبيعات $invoiceNo',
      actor: actor,
      currencyCode: currencyCode,
      ratePpm: ratePpm,
      lines: lines,
    );
  }

  Future<void> _postPurchaseJournal(
    dynamic txn, {
    required AuthUser actor,
    required String invoiceId,
    required String invoiceNo,
    required DateTime date,
    required int inventoryMinor,
    required int paidMinor,
    required int dueMinor,
    required String? supplierId,
    required String cashboxId,
    required String currencyCode,
    required int ratePpm,
  }) async {
    final lines = <_JournalLine>[
      _JournalLine('acc-inventory', debit: inventoryMinor),
      if (paidMinor > 0)
        _JournalLine('acc-cash', credit: paidMinor, cashboxId: cashboxId),
      if (dueMinor > 0)
        _JournalLine('acc-ap', credit: dueMinor, supplierId: supplierId),
    ];
    await _createPostedJournal(
      txn,
      sourceType: 'purchase',
      sourceId: invoiceId,
      date: date,
      description: 'فاتورة مشتريات $invoiceNo',
      actor: actor,
      currencyCode: currencyCode,
      ratePpm: ratePpm,
      lines: lines,
    );
  }

  Future<void> _createPostedJournal(
    dynamic txn, {
    required String sourceType,
    required String sourceId,
    required DateTime date,
    required String description,
    required AuthUser actor,
    required String currencyCode,
    required int ratePpm,
    required List<_JournalLine> lines,
  }) async {
    final debit = lines.fold<int>(0, (sum, line) => sum + line.debit);
    final credit = lines.fold<int>(0, (sum, line) => sum + line.credit);
    if (debit != credit || debit <= 0)
      throw StateError('تم منع ترحيل قيد غير متوازن');
    final entryId = await _database.newId();
    final entryNo = await _database.nextDocumentNumber(
      txn,
      documentType: 'journal',
      branchId: null,
      prefix: 'JRN',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.insert('journal_entries', {
      'id': entryId,
      'entry_no': entryNo,
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
        'journal_entry_id': entryId,
        'account_id': line.accountId,
        'debit_minor': line.debit,
        'credit_minor': line.credit,
        'currency_code': currencyCode,
        'rate_ppm': ratePpm,
        'customer_id': line.customerId,
        'supplier_id': line.supplierId,
        'cashbox_id': line.cashboxId,
      });
    }
  }

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);
}

class _BatchAllocation {
  const _BatchAllocation(this.batchId, this.quantityMinor, this.unitCostMinor);
  final String? batchId;
  final int quantityMinor;
  final int unitCostMinor;
}

class _BatchAllocationResult {
  const _BatchAllocationResult({
    required this.allocations,
    required this.costMinor,
    required this.unitCostMinor,
  });
  final List<_BatchAllocation> allocations;
  final int costMinor;
  final int unitCostMinor;
}

class _PreparedSaleLine {
  const _PreparedSaleLine(
    this.input,
    this.previousQuantityMinor,
    this.newQuantityMinor,
    this.unitCostMinor,
    this.productType,
    this.batchAllocations,
  );
  final InvoiceLineInput input;
  final int previousQuantityMinor;
  final int newQuantityMinor;
  final int unitCostMinor;
  final String productType;
  final List<_BatchAllocation> batchAllocations;
}

class _JournalLine {
  const _JournalLine(
    this.accountId, {
    this.debit = 0,
    this.credit = 0,
    this.customerId,
    this.supplierId,
    this.cashboxId,
  });
  final String accountId;
  final int debit;
  final int credit;
  final String? customerId;
  final String? supplierId;
  final String? cashboxId;
}
