import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';
import '../../data/repositories/auth_repository.dart';

class StockTransferLineInput {
  const StockTransferLineInput({
    required this.productId,
    required this.quantityMinor,
    this.unitCostMinor = 0,
  });

  final String productId;
  final int quantityMinor;
  final int unitCostMinor;
}

class StockTransferService {
  StockTransferService(this._database);
  final ErpDatabase _database;

  Future<String> createDraft(
    AuthUser actor, {
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<StockTransferLineInput> lines,
  }) async {
    requirePermission(actor.permissions, Permissions.inventoryManage);
    if (fromWarehouseId == toWarehouseId)
      throw ArgumentError(
        'يجب أن يكون المخزن المستلم مختلفاً عن المخزن المرسل',
      );
    if (lines.isEmpty)
      throw ArgumentError('أضف صنفاً واحداً على الأقل للتحويل');
    final grouped = <String, StockTransferLineInput>{};
    for (final line in lines) {
      if (line.quantityMinor <= 0)
        throw ArgumentError('كمية التحويل يجب أن تكون أكبر من صفر');
      if (grouped.containsKey(line.productId))
        throw ArgumentError('لا يمكن تكرار الصنف في التحويل');
      grouped[line.productId] = line;
    }
    final id = await _database.newId();
    await _database.transaction((txn) async {
      final documentNo = await _database.nextDocumentNumber(
        txn,
        documentType: 'STK-TRF',
        branchId: actor.branchId,
        prefix: 'TRF',
      );
      await txn.insert('stock_transfers', {
        'id': id,
        'document_no': documentNo,
        'from_warehouse_id': fromWarehouseId,
        'to_warehouse_id': toWarehouseId,
        'status': 'draft',
        'created_by': actor.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      for (final line in lines) {
        await txn.insert('stock_transfer_lines', {
          'id': await _database.newId(),
          'transfer_id': id,
          'product_id': line.productId,
          'quantity_minor': line.quantityMinor,
          'unit_cost_minor': line.unitCostMinor,
        });
      }
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'stock_transfer.created',
        entityType: 'stock_transfer',
        entityId: id,
        afterJson: 'lines=${lines.length}',
      );
    });
    return id;
  }

  Future<List<Map<String, Object?>>> list({
    String search = '',
    int limit = 50,
  }) {
    final pattern = '%${search.trim()}%';
    return _database.raw.rawQuery(
      '''SELECT st.*, fw.name_ar AS from_warehouse_name, tw.name_ar AS to_warehouse_name,
          COUNT(stl.id) AS lines_count
         FROM stock_transfers st
         JOIN warehouses fw ON fw.id = st.from_warehouse_id
         JOIN warehouses tw ON tw.id = st.to_warehouse_id
         LEFT JOIN stock_transfer_lines stl ON stl.transfer_id = st.id
         WHERE st.document_no LIKE ? OR fw.name_ar LIKE ? OR tw.name_ar LIKE ?
         GROUP BY st.id ORDER BY st.created_at DESC LIMIT ?''',
      [pattern, pattern, pattern, limit],
    );
  }

  Future<List<Map<String, Object?>>> lines(String transferId) =>
      _database.raw.rawQuery(
        '''SELECT stl.*, p.sku, p.name_ar, u.name_ar AS unit_name
       FROM stock_transfer_lines stl
       JOIN products p ON p.id = stl.product_id
       JOIN units u ON u.id = p.stock_unit_id
       WHERE stl.transfer_id = ? ORDER BY p.name_ar''',
        [transferId],
      );

  Future<void> dispatch(AuthUser actor, String transferId) async {
    requirePermission(actor.permissions, Permissions.inventoryManage);
    await _database.transaction((txn) async {
      final transfer = await _load(txn, transferId);
      if (transfer['status'] != 'draft')
        throw StateError('لا يمكن إرسال تحويل ليس في حالة مسودة');
      final transferLines = await txn.query(
        'stock_transfer_lines',
        where: 'transfer_id = ?',
        whereArgs: [transferId],
      );
      if (transferLines.isEmpty) throw StateError('لا توجد أصناف في التحويل');
      for (final line in transferLines) {
        final balance = await txn.query(
          'inventory_balances',
          where: 'product_id = ? AND warehouse_id = ?',
          whereArgs: [line['product_id'], transfer['from_warehouse_id']],
          limit: 1,
        );
        final available = balance.isEmpty
            ? 0
            : balance.first['quantity_minor'] as int;
        final requested = line['quantity_minor'] as int;
        if (available < requested) {
          throw StateError('رصيد الصنف غير كافٍ لإرسال التحويل');
        }
        final newBalance = available - requested;
        final cost = line['unit_cost_minor'] as int;
        await txn.update(
          'inventory_balances',
          {
            'quantity_minor': newBalance,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [balance.first['id']],
        );
        await txn.insert('inventory_movements', {
          'id': await _database.newId(),
          'product_id': line['product_id'],
          'warehouse_id': transfer['from_warehouse_id'],
          'movement_type': 'transfer_out',
          'quantity_minor': -requested,
          'unit_cost_minor': cost,
          'balance_after_minor': newBalance,
          'source_type': 'stock_transfer',
          'source_id': transferId,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'user_id': actor.id,
        });
      }
      await txn.update(
        'stock_transfers',
        {'status': 'sent', 'sent_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [transferId],
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'stock_transfer.sent',
        entityType: 'stock_transfer',
        entityId: transferId,
      );
    });
  }

  Future<void> receive(AuthUser actor, String transferId) async {
    requirePermission(actor.permissions, Permissions.inventoryManage);
    await _database.transaction((txn) async {
      final transfer = await _load(txn, transferId);
      if (transfer['status'] != 'sent')
        throw StateError('لا يمكن استلام تحويل لم يتم إرساله');
      final transferLines = await txn.query(
        'stock_transfer_lines',
        where: 'transfer_id = ?',
        whereArgs: [transferId],
      );
      for (final line in transferLines) {
        final balance = await txn.query(
          'inventory_balances',
          where: 'product_id = ? AND warehouse_id = ?',
          whereArgs: [line['product_id'], transfer['to_warehouse_id']],
          limit: 1,
        );
        final oldQuantity = balance.isEmpty
            ? 0
            : balance.first['quantity_minor'] as int;
        final quantity = line['quantity_minor'] as int;
        final cost = line['unit_cost_minor'] as int;
        final nextQuantity = oldQuantity + quantity;
        if (balance.isEmpty) {
          await txn.insert('inventory_balances', {
            'id': await _database.newId(),
            'product_id': line['product_id'],
            'warehouse_id': transfer['to_warehouse_id'],
            'quantity_minor': nextQuantity,
            'average_cost_minor': cost,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        } else {
          final oldCost = balance.first['average_cost_minor'] as int;
          final weightedCost = nextQuantity == 0
              ? 0
              : ((oldQuantity * oldCost) + (quantity * cost)) ~/ nextQuantity;
          await txn.update(
            'inventory_balances',
            {
              'quantity_minor': nextQuantity,
              'average_cost_minor': weightedCost,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [balance.first['id']],
          );
        }
        await txn.insert('inventory_movements', {
          'id': await _database.newId(),
          'product_id': line['product_id'],
          'warehouse_id': transfer['to_warehouse_id'],
          'movement_type': 'transfer_in',
          'quantity_minor': quantity,
          'unit_cost_minor': cost,
          'balance_after_minor': nextQuantity,
          'source_type': 'stock_transfer',
          'source_id': transferId,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'user_id': actor.id,
        });
      }
      await txn.update(
        'stock_transfers',
        {
          'status': 'received',
          'received_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [transferId],
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'stock_transfer.received',
        entityType: 'stock_transfer',
        entityId: transferId,
      );
    });
  }

  Future<void> cancelDraft(AuthUser actor, String transferId) async {
    requirePermission(actor.permissions, Permissions.inventoryManage);
    await _database.transaction((txn) async {
      final transfer = await _load(txn, transferId);
      if (transfer['status'] != 'draft')
        throw StateError(
          'لا يمكن إلغاء تحويل مرسل أو مستلم؛ أنشئ تسوية عكسية بدلاً من ذلك',
        );
      await txn.update(
        'stock_transfers',
        {'status': 'cancelled'},
        where: 'id = ?',
        whereArgs: [transferId],
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'stock_transfer.cancelled',
        entityType: 'stock_transfer',
        entityId: transferId,
      );
    });
  }

  Future<Map<String, Object?>> _load(dynamic txn, String transferId) async {
    final rows = await txn.query(
      'stock_transfers',
      where: 'id = ?',
      whereArgs: [transferId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('تحويل المخزون غير موجود');
    return rows.first;
  }
}
