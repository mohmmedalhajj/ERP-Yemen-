import '../db/erp_database.dart';

class InventoryAlertService {
  InventoryAlertService(this._database);
  final ErpDatabase _database;

  Future<int> refresh({int expiryWindowDays = 30}) async {
    final now = DateTime.now().toUtc();
    final today = _date(now);
    final until = _date(now.add(Duration(days: expiryWindowDays)));
    final lowStock = await _database.raw.rawQuery('''
      SELECT p.id, p.name_ar, w.name_ar AS warehouse_name, ib.quantity_minor, p.reorder_point_minor
      FROM inventory_balances ib
      JOIN products p ON p.id = ib.product_id
      JOIN warehouses w ON w.id = ib.warehouse_id
      WHERE p.active = 1 AND ib.quantity_minor <= p.reorder_point_minor
    ''');
    final expiring = await _database.raw.rawQuery('''
      SELECT sb.id, sb.batch_no, sb.expiry_date, p.name_ar, w.name_ar AS warehouse_name, sb.quantity_minor
      FROM stock_batches sb
      JOIN products p ON p.id = sb.product_id
      JOIN warehouses w ON w.id = sb.warehouse_id
      WHERE sb.active = 1 AND sb.quantity_minor > 0 AND sb.expiry_date IS NOT NULL
        AND sb.expiry_date BETWEEN ? AND ?
      ORDER BY sb.expiry_date ASC
    ''', [today, until]);
    var inserted = 0;
    await _database.transaction((txn) async {
      for (final row in lowStock) {
        final entityId = '${row['id']}:$today';
        final exists = await txn.query('local_notifications', where: 'id = ?', whereArgs: ['low-stock:$entityId'], limit: 1);
        if (exists.isNotEmpty) continue;
        await txn.insert('local_notifications', {
          'id': 'low-stock:$entityId',
          'notification_type': 'low_stock',
          'title': 'مخزون منخفض',
          'body': '${row['name_ar']} في ${row['warehouse_name']} — المتاح ${row['quantity_minor']}، الحد ${row['reorder_point_minor']}',
          'scheduled_at': now.toIso8601String(),
          'entity_type': 'product',
          'entity_id': row['id'],
          'created_at': now.toIso8601String(),
        });
        inserted++;
      }
      for (final row in expiring) {
        final entityId = '${row['id']}:$today';
        final exists = await txn.query('local_notifications', where: 'id = ?', whereArgs: ['expiry:$entityId'], limit: 1);
        if (exists.isNotEmpty) continue;
        await txn.insert('local_notifications', {
          'id': 'expiry:$entityId',
          'notification_type': 'expiry',
          'title': 'دفعة تقترب صلاحيتها',
          'body': '${row['name_ar']} — الدفعة ${row['batch_no']} — الصلاحية ${row['expiry_date']} — الكمية ${row['quantity_minor']}',
          'scheduled_at': now.toIso8601String(),
          'entity_type': 'stock_batch',
          'entity_id': row['id'],
          'created_at': now.toIso8601String(),
        });
        inserted++;
      }
    });
    return inserted;
  }

  Future<List<Map<String, Object?>>> unread({int limit = 100}) => _database.raw.rawQuery(
    'SELECT * FROM local_notifications WHERE read_at IS NULL ORDER BY scheduled_at DESC LIMIT ?',
    [limit],
  );

  Future<void> markRead(String id) async {
    await _database.raw.update('local_notifications', {'read_at': DateTime.now().toUtc().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }

  static String _date(DateTime value) => value.toIso8601String().substring(0, 10);
}
