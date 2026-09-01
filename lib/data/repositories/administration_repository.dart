import 'package:sqflite/sqflite.dart';

import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';
import 'auth_repository.dart';

class ManagedUserInput {
  const ManagedUserInput({
    this.id,
    required this.username,
    required this.displayName,
    required this.roleId,
    this.password,
    this.branchId,
    this.warehouseId,
    this.cashboxId,
  });

  final String? id;
  final String username;
  final String displayName;
  final String roleId;
  final String? password;
  final String? branchId;
  final String? warehouseId;
  final String? cashboxId;
}

class AdministrationRepository {
  AdministrationRepository(this._database, {PasswordHasher? passwordHasher})
    : _passwordHasher = passwordHasher ?? PasswordHasher();

  final ErpDatabase _database;
  final PasswordHasher _passwordHasher;

  Future<List<Map<String, Object?>>> users({String search = ''}) {
    final pattern = '%${search.trim()}%';
    return _database.raw.rawQuery(
      '''SELECT u.*, r.name_ar AS role_name, b.name_ar AS branch_name,
          w.name_ar AS warehouse_name, c.name_ar AS cashbox_name
         FROM users u
         JOIN roles r ON r.id = u.role_id
         LEFT JOIN branches b ON b.id = u.branch_id
         LEFT JOIN warehouses w ON w.id = u.warehouse_id
         LEFT JOIN cashboxes c ON c.id = u.cashbox_id
         WHERE u.display_name LIKE ? OR u.username LIKE ?
         ORDER BY u.active DESC, u.display_name''',
      [pattern, pattern],
    );
  }

  Future<List<Map<String, Object?>>> roles() => _database.raw.rawQuery(
    '''SELECT r.*, COUNT(rp.permission_code) AS permissions_count
       FROM roles r LEFT JOIN role_permissions rp ON rp.role_id = r.id
       WHERE r.active = 1 GROUP BY r.id ORDER BY r.system_role DESC, r.name_ar''',
  );

  Future<Set<String>> rolePermissions(String roleId) async {
    final rows = await _database.raw.query(
      'role_permissions',
      where: 'role_id = ?',
      whereArgs: [roleId],
    );
    return rows.map((row) => row['permission_code'] as String).toSet();
  }

  Future<String> saveUser(AuthUser actor, ManagedUserInput input) async {
    requirePermission(actor.permissions, Permissions.usersManage);
    final username = input.username.trim().toLowerCase();
    if (!RegExp(r'^[a-zA-Z0-9._-]{3,40}$').hasMatch(username)) {
      throw ArgumentError(
        'اسم المستخدم يجب أن يتكون من 3 إلى 40 حرفاً أو رقماً دون مسافات',
      );
    }
    if (input.displayName.trim().isEmpty)
      throw ArgumentError('اسم العرض مطلوب');
    if (input.id == null &&
        (input.password == null || input.password!.isEmpty)) {
      throw ArgumentError('كلمة المرور مطلوبة للمستخدم الجديد');
    }
    final id = input.id ?? await _database.newId();
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      final existing = input.id == null
          ? const <Map<String, Object?>>[]
          : await txn.query(
              'users',
              where: 'id = ?',
              whereArgs: [id],
              limit: 1,
            );
      if (input.id != null && existing.isEmpty)
        throw StateError('المستخدم غير موجود');
      final duplicate = await txn.query(
        'users',
        where: 'username = ? AND id <> ?',
        whereArgs: [username, id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) throw StateError('اسم المستخدم مستخدم بالفعل');
      final payload = <String, Object?>{
        'username': username,
        'display_name': input.displayName.trim(),
        'role_id': input.roleId,
        'branch_id': input.branchId,
        'warehouse_id': input.warehouseId,
        'cashbox_id': input.cashboxId,
        'updated_at': now,
      };
      if (input.password != null && input.password!.isNotEmpty) {
        final hash = await _passwordHasher.hash(input.password!);
        payload['password_hash'] = hash.hashBase64;
        payload['password_salt'] = hash.saltBase64;
        payload['must_change_password'] = 1;
      }
      if (input.id == null) {
        final hash = await _passwordHasher.hash(input.password!);
        payload.addAll({
          'id': id,
          'password_hash': hash.hashBase64,
          'password_salt': hash.saltBase64,
          'active': 1,
          'must_change_password': 1,
          'created_at': now,
        });
        await txn.insert('users', payload);
      } else {
        await txn.update('users', payload, where: 'id = ?', whereArgs: [id]);
      }
      await _database.audit(
        txn,
        userId: actor.id,
        action: input.id == null ? 'user.created' : 'user.updated',
        entityType: 'user',
        entityId: id,
        beforeJson: existing.isEmpty ? null : existing.first.toString(),
        afterJson: payload.toString(),
      );
    });
    return id;
  }

  Future<void> archiveUser(AuthUser actor, String userId) async {
    requirePermission(actor.permissions, Permissions.usersManage);
    if (actor.id == userId) throw StateError('لا يمكن تعطيل المستخدم الحالي');
    await _database.transaction((txn) async {
      final affected = await txn.update(
        'users',
        {'active': 0, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [userId],
      );
      if (affected != 1) throw StateError('المستخدم غير موجود');
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'user.archived',
        entityType: 'user',
        entityId: userId,
      );
    });
  }

  Future<void> updateRolePermissions(
    AuthUser actor,
    String roleId,
    Set<String> permissions,
  ) async {
    requirePermission(actor.permissions, Permissions.usersManage);
    for (final permission in permissions) {
      if (!Permissions.all.contains(permission))
        throw ArgumentError('صلاحية غير معروفة');
    }
    await _database.transaction((txn) async {
      final role = await txn.query(
        'roles',
        where: 'id = ?',
        whereArgs: [roleId],
        limit: 1,
      );
      if (role.isEmpty) throw StateError('الدور غير موجود');
      if ((role.first['system_role'] as int) == 1 &&
          actor.roleCode != 'system_admin') {
        throw AuthorizationException(
          'تعديل صلاحيات الأدوار النظامية محصور بمدير النظام',
        );
      }
      await txn.delete(
        'role_permissions',
        where: 'role_id = ?',
        whereArgs: [roleId],
      );
      for (final permission in permissions) {
        await txn.insert('role_permissions', {
          'role_id': roleId,
          'permission_code': permission,
        });
      }
      await _database.audit(
        txn,
        userId: actor.id,
        action: 'role.permissions_updated',
        entityType: 'role',
        entityId: roleId,
        afterJson: permissions.join(','),
      );
    });
  }

  Future<List<Map<String, Object?>>> branches() =>
      _database.raw.query('branches', where: 'active = 1', orderBy: 'name_ar');
  Future<List<Map<String, Object?>>> warehouses() => _database.raw.query(
    'warehouses',
    where: 'active = 1',
    orderBy: 'name_ar',
  );
  Future<List<Map<String, Object?>>> cashboxes() =>
      _database.raw.query('cashboxes', where: 'active = 1', orderBy: 'name_ar');
  Future<List<Map<String, Object?>>> currencies() =>
      _database.raw.query('currencies', where: 'active = 1', orderBy: 'code');
  Future<List<Map<String, Object?>>> fiscalPeriods() =>
      _database.raw.query('fiscal_periods', orderBy: 'start_date DESC');

  Future<Map<String, String>> settings() async {
    final rows = await _database.raw.query('app_settings');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  Future<void> saveSetting(AuthUser actor, String key, String value) async {
    requirePermission(actor.permissions, Permissions.settingsManage);
    if (key.trim().isEmpty) throw ArgumentError('مفتاح الإعداد مطلوب');
    await _database.raw.insert('app_settings', {
      'key': key.trim(),
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _database.audit(
      _database.raw,
      userId: actor.id,
      action: 'settings.updated',
      entityType: 'app_setting',
      entityId: key.trim(),
      afterJson: value,
    );
  }

  Future<List<Map<String, Object?>>> auditLog({
    String search = '',
    int limit = 100,
  }) {
    final pattern = '%${search.trim()}%';
    return _database.raw.rawQuery(
      '''SELECT a.*, u.display_name FROM audit_logs a
         LEFT JOIN users u ON u.id = a.user_id
         WHERE a.action LIKE ? OR a.entity_type LIKE ? OR u.display_name LIKE ?
         ORDER BY a.created_at DESC LIMIT ?''',
      [pattern, pattern, pattern, limit],
    );
  }
}
