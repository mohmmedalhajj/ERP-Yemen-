import 'package:sqflite/sqflite.dart';

import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';
import '../../data/repositories/auth_repository.dart';

class StockCountInput {
  const StockCountInput({
    required this.warehouseId,
    required this.countType,
    this.periodStart,
    this.periodEnd,
    this.categoryId,
    this.notes,
  });

  final String warehouseId;
  final String countType;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final String? categoryId;
  final String? notes;
}

class InventoryCountService {
  InventoryCountService(this._database);
  final ErpDatabase _database;

  Future<String> createCount(AuthUser actor, StockCountInput input) async {
    requirePermission(actor.permissions, Permissions.inventoryManage);
    if (!const {
      'monthly',
      'quarterly',
      'yearly',
      'custom',
    }.contains(input.countType)) {
      throw ArgumentError('نوع الجرد غير صالح');
    }
    if (input.warehouseId.trim().isEmpty)
      throw ArgumentError('اختر المخزن قبل إنشاء الجرد');
    if (input.periodStart != null &&
        input.periodEnd != null &&
        input.periodEnd!.isBefore(input.periodStart!)) {
      throw ArgumentError('نهاية فترة الجرد يجب أن تكون بعد بدايتها');
    }
    final id = await _database.newId();
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      final documentNo = await _database.nextDocumentNumber(
        txn,
        documentType: 'STK-COUNT',
        branchId: actor.branchId,
        prefix: 'JRD',
      );
      await txn.insert('stock_counts', {
        'id': id,
        'document_no': documentNo,
        'warehouse_id': input.warehouseId,
        'status': 'draft',
        'count_type': input.countType,
        'period_start': input.periodStart?.toUtc().toIso8601String(),
        'period_end': input.periodEnd?.toUtc().toIso8601String(),
        'category_id': input.categoryId,
        'notes': input.notes?.trim(),
        'created_by': actor.id,
        'created_at': now,
      });
      final parameters = <Object?>[input.warehouseId];
      var categoryCondition = '';
      if (input.categoryId != null && input.categoryId!.isNotEmpty) {
        categoryCondition = ' AND p.category_id = ?';
        parameters.add(input.categoryId);
      }
      final rows = await txn.rawQuery(
        '''SELECT p.id AS product_id, COALESCE(ib.quantity_minor, 0) AS system_qty_minor
           FROM products p
           LEFT JOIN inventory_balances ib ON ib.product_id = p.id AND ib.warehouse_id = ?
           WHERE p.active = 1 AND p.product_type = 'stock'$categoryCondition
           ORDER BY p.name_ar''',
        parameters,
      );
      for (final row in rows) {
        final systemQuantity = row['system_qty_minor'] as int;
        await txn.insert('stock_count_lines', {
          'id': await _database.newId(),
          'stock_count_id': id,
          'product_id': row['product_id'],
          'system_qty_minor': systemQuantity,
          'counted_qty_minor': systemQuantity,
        });
      }
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'stock_count.created',
        entityType: 'stock_count',
        entityId: id,
        afterJson:
            'type=${input.countType}; warehouse=${input.warehouseId}; lines=${rows.length}',
      );
    });
    return id;
  }

  Future<List<Map<String, Object?>>> counts({
    String search = '',
    String? warehouseId,
    String? status,
    int limit = 30,
    int offset = 0,
  }) {
    final clauses = <String>['1 = 1'];
    final args = <Object?>[];
    if (search.trim().isNotEmpty) {
      clauses.add('(sc.document_no LIKE ? OR sc.notes LIKE ?)');
      args.addAll(['%${search.trim()}%', '%${search.trim()}%']);
    }
    if (warehouseId != null && warehouseId.isNotEmpty) {
      clauses.add('sc.warehouse_id = ?');
      args.add(warehouseId);
    }
    if (status != null && status.isNotEmpty) {
      clauses.add('sc.status = ?');
      args.add(status);
    }
    args.addAll([limit, offset]);
    return _database.raw.rawQuery('''SELECT sc.*, w.name_ar AS warehouse_name,
          COUNT(scl.id) AS lines_count,
          COALESCE(SUM(scl.counted_qty_minor - scl.system_qty_minor), 0) AS variance_qty_minor
         FROM stock_counts sc
         JOIN warehouses w ON w.id = sc.warehouse_id
         LEFT JOIN stock_count_lines scl ON scl.stock_count_id = sc.id
         WHERE ${clauses.join(' AND ')}
         GROUP BY sc.id
         ORDER BY sc.created_at DESC
         LIMIT ? OFFSET ?''', args);
  }

  Future<List<Map<String, Object?>>> countLines(
    String countId, {
    String search = '',
  }) {
    final pattern = '%${search.trim()}%';
    return _database.raw.rawQuery(
      '''SELECT scl.*, p.sku, p.name_ar, p.barcode, u.name_ar AS unit_name,
          (scl.counted_qty_minor - scl.system_qty_minor) AS variance_qty_minor,
          COALESCE(ib.average_cost_minor, 0) AS average_cost_minor
         FROM stock_count_lines scl
         JOIN products p ON p.id = scl.product_id
         JOIN units u ON u.id = p.stock_unit_id
         JOIN stock_counts sc ON sc.id = scl.stock_count_id
         LEFT JOIN inventory_balances ib ON ib.product_id = scl.product_id AND ib.warehouse_id = sc.warehouse_id
         WHERE scl.stock_count_id = ? AND (p.name_ar LIKE ? OR p.sku LIKE ? OR p.barcode LIKE ?)
         ORDER BY p.name_ar''',
      [countId, pattern, pattern, pattern],
    );
  }

  Future<void> updateCountedQuantity(
    AuthUser actor, {
    required String countId,
    required String lineId,
    required int quantityMinor,
  }) async {
    requirePermission(actor.permissions, Permissions.inventoryManage);
    if (quantityMinor < 0)
      throw ArgumentError('الكمية الفعلية لا يمكن أن تكون سالبة');
    await _database.transaction((txn) async {
      final count = await _loadCount(txn, countId);
      _requireDraft(count);
      final changed = await txn.update(
        'stock_count_lines',
        {'counted_qty_minor': quantityMinor},
        where: 'id = ? AND stock_count_id = ?',
        whereArgs: [lineId, countId],
      );
      if (changed != 1) throw StateError('لم يتم العثور على سطر الجرد');
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'stock_count.line_updated',
        entityType: 'stock_count',
        entityId: countId,
        afterJson: 'line=$lineId; counted=$quantityMinor',
      );
    });
  }

  Future<void> approve(AuthUser actor, String countId) async {
    requirePermission(actor.permissions, Permissions.inventoryManage);
    requirePermission(actor.permissions, Permissions.accountingPost);
    await _database.transaction((txn) async {
      final count = await _loadCount(txn, countId);
      _requireDraft(count);
      final lines = await txn.rawQuery(
        '''SELECT scl.*, COALESCE(ib.average_cost_minor, 0) AS average_cost_minor
           FROM stock_count_lines scl
           LEFT JOIN inventory_balances ib ON ib.product_id = scl.product_id AND ib.warehouse_id = ?
           WHERE scl.stock_count_id = ?''',
        [count['warehouse_id'], countId],
      );
      if (lines.isEmpty)
        throw StateError('لا توجد أصناف في جلسة الجرد لاعتمادها');
      var inventoryValueDelta = 0;
      for (final line in lines) {
        final systemQty = line['system_qty_minor'] as int;
        final countedQty = line['counted_qty_minor'] as int;
        final variance = countedQty - systemQty;
        if (variance == 0) continue;
        final cost = line['average_cost_minor'] as int;
        inventoryValueDelta += variance * cost;
        final balance = await txn.query(
          'inventory_balances',
          where: 'product_id = ? AND warehouse_id = ?',
          whereArgs: [line['product_id'], count['warehouse_id']],
          limit: 1,
        );
        if (balance.isEmpty) {
          await txn.insert('inventory_balances', {
            'id': await _database.newId(),
            'product_id': line['product_id'],
            'warehouse_id': count['warehouse_id'],
            'quantity_minor': countedQty,
            'average_cost_minor': cost,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        } else {
          await txn.update(
            'inventory_balances',
            {
              'quantity_minor': countedQty,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [balance.first['id']],
          );
        }
        await txn.insert('inventory_movements', {
          'id': await _database.newId(),
          'product_id': line['product_id'],
          'warehouse_id': count['warehouse_id'],
          'movement_type': 'stock_count_adjustment',
          'quantity_minor': variance,
          'unit_cost_minor': cost,
          'balance_after_minor': countedQty,
          'source_type': 'stock_count',
          'source_id': countId,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'user_id': actor.id,
        });
      }
      String? journalId;
      if (inventoryValueDelta != 0) {
        journalId = await _createAdjustmentJournal(
          txn,
          actor: actor,
          countId: countId,
          valueDelta: inventoryValueDelta,
          date: DateTime.now().toUtc(),
        );
      }
      await txn.update(
        'stock_counts',
        {
          'status': 'approved',
          'approved_by': actor.id,
          'posted_at': DateTime.now().toUtc().toIso8601String(),
          'adjustment_journal_id': journalId,
        },
        where: 'id = ?',
        whereArgs: [countId],
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'stock_count.approved',
        entityType: 'stock_count',
        entityId: countId,
        afterJson: 'inventory_value_delta=$inventoryValueDelta',
      );
    });
  }

  Future<void> cancelDraft(AuthUser actor, String countId) async {
    requirePermission(actor.permissions, Permissions.inventoryManage);
    await _database.transaction((txn) async {
      final count = await _loadCount(txn, countId);
      _requireDraft(count);
      await txn.update(
        'stock_counts',
        {
          'status': 'cancelled',
          'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          'cancelled_by': actor.id,
        },
        where: 'id = ?',
        whereArgs: [countId],
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'stock_count.cancelled',
        entityType: 'stock_count',
        entityId: countId,
      );
    });
  }

  Future<Map<String, Object?>> _loadCount(
    Transaction txn,
    String countId,
  ) async {
    final rows = await txn.query(
      'stock_counts',
      where: 'id = ?',
      whereArgs: [countId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('جلسة الجرد غير موجودة');
    return rows.first;
  }

  void _requireDraft(Map<String, Object?> count) {
    if (count['status'] != 'draft') {
      throw StateError('لا يمكن تعديل أو اعتماد جلسة جرد ليست في حالة مسودة');
    }
  }

  Future<String> _createAdjustmentJournal(
    Transaction txn, {
    required AuthUser actor,
    required String countId,
    required int valueDelta,
    required DateTime date,
  }) async {
    final journalId = await _database.newId();
    final entryNo = await _database.nextDocumentNumber(
      txn,
      documentType: 'JRN',
      branchId: actor.branchId,
      prefix: 'JRD-QYD',
    );
    await txn.insert('journal_entries', {
      'id': journalId,
      'entry_no': entryNo,
      'entry_date': date.toIso8601String(),
      'status': 'posted',
      'source_type': 'stock_count',
      'source_id': countId,
      'description': 'قيد تسوية جرد مخزني',
      'created_by': actor.id,
      'posted_by': actor.id,
      'posted_at': date.toIso8601String(),
      'created_at': date.toIso8601String(),
    });
    final amount = valueDelta.abs();
    final debitAccount = valueDelta > 0
        ? 'acc-inventory'
        : 'acc-inventory-loss';
    final creditAccount = valueDelta > 0
        ? 'acc-inventory-gain'
        : 'acc-inventory';
    await txn.insert('journal_lines', {
      'id': await _database.newId(),
      'journal_entry_id': journalId,
      'account_id': debitAccount,
      'debit_minor': amount,
      'credit_minor': 0,
      'description': 'تسوية جرد مخزني',
    });
    await txn.insert('journal_lines', {
      'id': await _database.newId(),
      'journal_entry_id': journalId,
      'account_id': creditAccount,
      'debit_minor': 0,
      'credit_minor': amount,
      'description': 'تسوية جرد مخزني',
    });
    return journalId;
  }
}
