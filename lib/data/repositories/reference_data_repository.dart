import 'package:sqflite/sqflite.dart';

import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';
import 'auth_repository.dart';

class ReferenceDataRepository {
  ReferenceDataRepository(this._database);
  final ErpDatabase _database;

  static const tables = <String>{
    'branches',
    'warehouses',
    'cashboxes',
    'currencies',
    'taxes',
    'categories',
    'units',
    'fiscal_periods',
  };

  Future<List<Map<String, Object?>>> list(String table, {String search = ''}) {
    _assertTable(table);
    final pattern = '%${search.trim()}%';
    return switch (table) {
      'branches' => _database.raw.rawQuery(
        '''SELECT b.*, o.name_ar AS organization_name
          FROM branches b JOIN organizations o ON o.id = b.organization_id
          WHERE b.name_ar LIKE ? OR b.code LIKE ? ORDER BY b.active DESC, b.name_ar''',
        [pattern, pattern],
      ),
      'warehouses' => _database.raw.rawQuery(
        '''SELECT w.*, b.name_ar AS branch_name
          FROM warehouses w JOIN branches b ON b.id = w.branch_id
          WHERE w.name_ar LIKE ? OR w.code LIKE ? ORDER BY w.active DESC, w.name_ar''',
        [pattern, pattern],
      ),
      'cashboxes' => _database.raw.rawQuery(
        '''SELECT c.*, b.name_ar AS branch_name
          FROM cashboxes c JOIN branches b ON b.id = c.branch_id
          WHERE c.name_ar LIKE ? OR c.code LIKE ? ORDER BY c.active DESC, c.name_ar''',
        [pattern, pattern],
      ),
      'currencies' => _database.raw.rawQuery(
        '''SELECT c.*, r.rate_ppm, r.effective_date
          FROM currencies c LEFT JOIN exchange_rates r ON r.id = (
            SELECT id FROM exchange_rates WHERE currency_code = c.code ORDER BY effective_date DESC LIMIT 1)
          WHERE c.name_ar LIKE ? OR c.code LIKE ? ORDER BY c.active DESC, c.code''',
        [pattern, pattern],
      ),
      'taxes' => _database.raw.rawQuery(
        '''SELECT * FROM taxes
          WHERE name_ar LIKE ? ORDER BY active DESC, name_ar''',
        [pattern],
      ),
      'categories' => _database.raw.rawQuery(
        '''SELECT c.*, p.name_ar AS parent_name FROM categories c
          LEFT JOIN categories p ON p.id = c.parent_id
          WHERE c.name_ar LIKE ? ORDER BY c.active DESC, c.name_ar''',
        [pattern],
      ),
      'units' => _database.raw.rawQuery(
        '''SELECT * FROM units WHERE name_ar LIKE ? OR code LIKE ?
          ORDER BY active DESC, name_ar''',
        [pattern, pattern],
      ),
      'fiscal_periods' => _database.raw.rawQuery(
        '''SELECT * FROM fiscal_periods
          WHERE name LIKE ? ORDER BY start_date DESC''',
        [pattern],
      ),
      _ => throw UnsupportedError('مرجع غير مدعوم'),
    };
  }

  Future<String> save(
    AuthUser actor,
    String table,
    Map<String, Object?> fields,
  ) async {
    requirePermission(actor.permissions, Permissions.settingsManage);
    _assertTable(table);
    final id =
        fields['id'] as String? ??
        (table == 'currencies'
            ? (fields['code'] as String).trim().toUpperCase()
            : await _database.newId());
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      final existing = await txn.query(
        table,
        where: table == 'currencies' ? 'code = ?' : 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final payload = await _payload(table, fields, now, txn);
      if (existing.isEmpty) {
        payload[table == 'currencies' ? 'code' : 'id'] = id;
        await txn.insert(table, payload);
      } else {
        await txn.update(
          table,
          payload,
          where: table == 'currencies' ? 'code = ?' : 'id = ?',
          whereArgs: [id],
        );
      }
      if (table == 'currencies' &&
          fields['rate_ppm'] != null &&
          (fields['rate_ppm'] as int) > 0) {
        final date = fields['rate_date'] as String? ?? now.substring(0, 10);
        await txn.insert('exchange_rates', {
          'id': await _database.newId(),
          'currency_code': id,
          'rate_ppm': fields['rate_ppm'],
          'effective_date': date,
          'source': 'manual',
          'created_by': actor.id,
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _database.audit(
        txn,
        userId: actor.id,
        action: existing.isEmpty ? '$table.created' : '$table.updated',
        entityType: table,
        entityId: id,
        beforeJson: existing.isEmpty ? null : existing.first.toString(),
        afterJson: payload.toString(),
      );
    });
    return id;
  }

  Future<void> archive(
    AuthUser actor,
    String table,
    Map<String, Object?> row,
  ) async {
    requirePermission(actor.permissions, Permissions.settingsManage);
    _assertTable(table);
    if (table == 'fiscal_periods')
      throw StateError(
        'لا يمكن حذف فترة مالية. استخدم الإقفال بعد التحقق من القيود.',
      );
    final key = table == 'currencies' ? 'code' : 'id';
    await _database.transaction((txn) async {
      final dependents = await _dependentCount(txn, table, row[key] as String);
      if (dependents > 0) {
        await txn.update(
          table,
          {'active': 0},
          where: '$key = ?',
          whereArgs: [row[key]],
        );
      } else {
        await txn.delete(table, where: '$key = ?', whereArgs: [row[key]]);
      }
      await _database.audit(
        txn,
        userId: actor.id,
        action: '$table.archived',
        entityType: table,
        entityId: row[key] as String,
        beforeJson: row.toString(),
        afterJson: 'dependent_count=$dependents',
      );
    });
  }

  Future<void> closePeriod(AuthUser actor, String id) async {
    requirePermission(actor.permissions, Permissions.settingsManage);
    await _database.transaction((txn) async {
      final rows = await txn.query(
        'fiscal_periods',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('الفترة المالية غير موجودة');
      final count = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM journal_entries WHERE fiscal_period_id = ? AND status = ?',
        [id, 'draft'],
      );
      if ((count.first['count'] as int) > 0)
        throw StateError('لا يمكن إقفال الفترة وبها قيود مسودة');
      await txn.update(
        'fiscal_periods',
        {'closed': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'fiscal_period.closed',
        entityType: 'fiscal_period',
        entityId: id,
      );
    });
  }

  Future<Map<String, Object?>> _payload(
    String table,
    Map<String, Object?> fields,
    String now,
    dynamic txn,
  ) async {
    String requiredText(String key, String label) {
      final value = (fields[key] as String? ?? '').trim();
      if (value.isEmpty) throw ArgumentError('$label مطلوب');
      return value;
    }

    final active = fields['active'] == false ? 0 : 1;
    return switch (table) {
      'branches' => {
        'organization_id': await _organizationId(txn),
        'code': requiredText('code', 'كود الفرع'),
        'name_ar': requiredText('name_ar', 'اسم الفرع'),
        'name_en': (fields['name_en'] as String?)?.trim(),
        'address': (fields['address'] as String?)?.trim(),
        'phone': (fields['phone'] as String?)?.trim(),
        'active': active,
        'created_at': now,
      },
      'warehouses' => {
        'branch_id': requiredText('branch_id', 'الفرع'),
        'code': requiredText('code', 'كود المخزن'),
        'name_ar': requiredText('name_ar', 'اسم المخزن'),
        'name_en': (fields['name_en'] as String?)?.trim(),
        'active': active,
        'created_at': now,
      },
      'cashboxes' => {
        'branch_id': requiredText('branch_id', 'الفرع'),
        'code': requiredText('code', 'كود الصندوق أو البنك'),
        'name_ar': requiredText('name_ar', 'اسم الصندوق أو البنك'),
        'type': fields['type'] == 'bank' ? 'bank' : 'cash',
        'active': active,
        'created_at': now,
      },
      'currencies' => {
        'name_ar': requiredText('name_ar', 'اسم العملة'),
        'name_en': (fields['name_en'] as String?)?.trim(),
        'symbol': (fields['symbol'] as String?)?.trim(),
        'decimals': _nonNegativeInt(fields['decimals'], 'المنازل العشرية'),
        'active': active,
      },
      'taxes' => {
        'name_ar': requiredText('name_ar', 'اسم الضريبة'),
        'name_en': (fields['name_en'] as String?)?.trim(),
        'rate_basis_points': _nonNegativeInt(
          fields['rate_basis_points'],
          'نسبة الضريبة',
        ),
        'inclusive': fields['inclusive'] == true ? 1 : 0,
        'active': active,
      },
      'categories' => {
        'parent_id': fields['parent_id'] as String?,
        'name_ar': requiredText('name_ar', 'اسم التصنيف'),
        'name_en': (fields['name_en'] as String?)?.trim(),
        'active': active,
      },
      'units' => {
        'code': requiredText('code', 'كود الوحدة'),
        'name_ar': requiredText('name_ar', 'اسم الوحدة'),
        'name_en': (fields['name_en'] as String?)?.trim(),
        'precision_digits': _nonNegativeInt(
          fields['precision_digits'],
          'دقة الوحدة',
        ),
        'active': active,
      },
      'fiscal_periods' => {
        'organization_id': await _organizationId(txn),
        'name': requiredText('name', 'اسم الفترة'),
        'start_date': requiredText('start_date', 'بداية الفترة'),
        'end_date': requiredText('end_date', 'نهاية الفترة'),
      },
      _ => throw UnsupportedError('مرجع غير مدعوم'),
    };
  }

  int _nonNegativeInt(Object? value, String label) {
    final parsed = value is int ? value : int.tryParse('$value');
    if (parsed == null || parsed < 0) throw ArgumentError('$label غير صالح');
    return parsed;
  }

  Future<String> _organizationId(dynamic txn) async {
    final rows = await txn.query('organizations', limit: 1);
    if (rows.isEmpty) throw StateError('لم تُهيأ المؤسسة بعد');
    return rows.first['id'] as String;
  }

  Future<int> _dependentCount(dynamic txn, String table, String id) async {
    final query = switch (table) {
      'branches' =>
        'SELECT COUNT(*) AS count FROM warehouses WHERE branch_id = ?',
      'warehouses' => 'SELECT COUNT(*) AS count FROM inventory_balances WHERE warehouse_id = ?',
      'cashboxes' =>
        'SELECT COUNT(*) AS count FROM cash_movements WHERE cashbox_id = ?',
      'currencies' =>
        'SELECT COUNT(*) AS count FROM exchange_rates WHERE currency_code = ?',
      'categories' =>
        'SELECT COUNT(*) AS count FROM products WHERE category_id = ?',
      'units' =>
        'SELECT COUNT(*) AS count FROM products WHERE stock_unit_id = ?',
      'taxes' =>
        'SELECT COUNT(*) AS count FROM products WHERE default_tax_id = ?',
      _ => 'SELECT 0 AS count',
    };
    final rows = await txn.rawQuery(query, [id]);
    return rows.first['count'] as int;
  }

  void _assertTable(String table) {
    if (!tables.contains(table)) throw ArgumentError('نوع البيانات غير مدعوم');
  }
}
