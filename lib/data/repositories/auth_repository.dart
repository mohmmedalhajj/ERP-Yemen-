import 'dart:convert';

import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.roleCode,
    required this.permissions,
    this.branchId,
    this.warehouseId,
    this.cashboxId,
    required this.mustChangePassword,
  });

  final String id;
  final String username;
  final String displayName;
  final String roleCode;
  final Set<String> permissions;
  final String? branchId;
  final String? warehouseId;
  final String? cashboxId;
  final bool mustChangePassword;
}

class SetupInput {
  const SetupInput({
    required this.organizationName,
    required this.branchName,
    required this.warehouseName,
    required this.cashboxName,
    required this.adminName,
    required this.adminUsername,
    required this.adminPassword,
    this.baseCurrency = 'YER',
    this.languageCode = 'ar',
    required this.fiscalYearStart,
    required this.fiscalYearEnd,
  });

  final String organizationName;
  final String branchName;
  final String warehouseName;
  final String cashboxName;
  final String adminName;
  final String adminUsername;
  final String adminPassword;
  final String baseCurrency;
  final String languageCode;
  final DateTime fiscalYearStart;
  final DateTime fiscalYearEnd;
}

class AuthRepository {
  AuthRepository(this._database, {PasswordHasher? passwordHasher})
    : _passwordHasher = passwordHasher ?? PasswordHasher();

  final ErpDatabase _database;
  final PasswordHasher _passwordHasher;

  Future<void> initialize(SetupInput input) async {
    if (await _database.isConfigured) {
      throw StateError('تم إعداد المؤسسة مسبقاً');
    }
    final hash = await _passwordHasher.hash(input.adminPassword);
    final now = DateTime.now().toUtc().toIso8601String();
    final organizationId = await _database.newId();
    final branchId = await _database.newId();
    final warehouseId = await _database.newId();
    final cashboxId = await _database.newId();
    final userId = await _database.newId();
    final periodId = await _database.newId();

    await _database.transaction((txn) async {
      await txn.insert('organizations', {
        'id': organizationId,
        'name_ar': input.organizationName,
        'base_currency': input.baseCurrency,
        'language_code': input.languageCode,
        'fiscal_year_start': _date(input.fiscalYearStart),
        'fiscal_year_end': _date(input.fiscalYearEnd),
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('branches', {
        'id': branchId,
        'organization_id': organizationId,
        'code': 'MAIN',
        'name_ar': input.branchName,
        'created_at': now,
      });
      await txn.insert('warehouses', {
        'id': warehouseId,
        'branch_id': branchId,
        'code': 'MAIN',
        'name_ar': input.warehouseName,
        'created_at': now,
      });
      await txn.insert('cashboxes', {
        'id': cashboxId,
        'branch_id': branchId,
        'code': 'MAIN',
        'name_ar': input.cashboxName,
        'created_at': now,
      });
      await txn.insert('fiscal_periods', {
        'id': periodId,
        'organization_id': organizationId,
        'name': '${input.fiscalYearStart.year}',
        'start_date': _date(input.fiscalYearStart),
        'end_date': _date(input.fiscalYearEnd),
      });
      await txn.insert('users', {
        'id': userId,
        'username': input.adminUsername.trim().toLowerCase(),
        'display_name': input.adminName,
        'password_hash': hash.hashBase64,
        'password_salt': hash.saltBase64,
        'role_id': 'role-system-admin',
        'branch_id': branchId,
        'warehouse_id': warehouseId,
        'cashbox_id': cashboxId,
        'must_change_password': 0,
        'created_at': now,
        'updated_at': now,
      });
      for (final entry in <String, String>{
        'organization_id': organizationId,
        'default_branch_id': branchId,
        'default_warehouse_id': warehouseId,
        'default_cashbox_id': cashboxId,
        'prevent_negative_stock': '1',
        'session_timeout_minutes': '15',
        'language_code': input.languageCode,
        'currency_decimals': '0',
        'trial_started_at': now,
      }.entries) {
        await txn.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
          'updated_at': now,
        });
      }
      await _database.audit(
        txn,
        userId: userId,
        action: 'setup.initialize',
        entityType: 'organization',
        entityId: organizationId,
        afterJson: jsonEncode({'name': input.organizationName}),
      );
    });
  }

  Future<AuthUser> login(String username, String password) async {
    final normalized = username.trim().toLowerCase();
    final rows = await _database.raw.query(
      'users',
      where: 'username = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('بيانات الدخول غير صحيحة');
    final row = rows.first;
    if ((row['active'] as int) != 1) throw StateError('تم تعطيل هذا المستخدم');
    final lockedUntil = row['locked_until'] as String?;
    if (lockedUntil != null &&
        DateTime.parse(lockedUntil).isAfter(DateTime.now().toUtc())) {
      throw StateError('تم قفل الحساب مؤقتاً بسبب محاولات فاشلة');
    }
    final valid = await _passwordHasher.verify(
      password: password,
      saltBase64: row['password_salt'] as String,
      expectedHashBase64: row['password_hash'] as String,
    );
    if (!valid) {
      final failed = (row['failed_attempts'] as int) + 1;
      final changes = <String, Object?>{'failed_attempts': failed};
      if (failed >= 5) {
        changes['locked_until'] = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 15))
            .toIso8601String();
      }
      await _database.raw.update(
        'users',
        changes,
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      await _database.audit(
        _database.raw,
        userId: row['id'] as String,
        action: 'auth.login_failed',
        entityType: 'user',
        entityId: row['id'] as String,
      );
      throw StateError('بيانات الدخول غير صحيحة');
    }
    final roleRows = await _database.raw.query(
      'roles',
      where: 'id = ?',
      whereArgs: [row['role_id']],
      limit: 1,
    );
    final permissionRows = await _database.raw.rawQuery(
      '''SELECT rp.permission_code FROM role_permissions rp WHERE rp.role_id = ?''',
      [row['role_id']],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.raw.update(
      'users',
      {'failed_attempts': 0, 'locked_until': null, 'last_login_at': now},
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    await _database.audit(
      _database.raw,
      userId: row['id'] as String,
      action: 'auth.login',
      entityType: 'user',
      entityId: row['id'] as String,
    );
    return AuthUser(
      id: row['id'] as String,
      username: row['username'] as String,
      displayName: row['display_name'] as String,
      roleCode: roleRows.first['code'] as String,
      permissions: permissionRows
          .map((item) => item['permission_code'] as String)
          .toSet(),
      branchId: row['branch_id'] as String?,
      warehouseId: row['warehouse_id'] as String?,
      cashboxId: row['cashbox_id'] as String?,
      mustChangePassword: (row['must_change_password'] as int) == 1,
    );
  }

  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final rows = await _database.raw.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('المستخدم غير موجود');
    final row = rows.first;
    final valid = await _passwordHasher.verify(
      password: currentPassword,
      saltBase64: row['password_salt'] as String,
      expectedHashBase64: row['password_hash'] as String,
    );
    if (!valid) throw StateError('كلمة المرور الحالية غير صحيحة');
    final next = await _passwordHasher.hash(newPassword);
    await _database.raw.update(
      'users',
      {
        'password_hash': next.hashBase64,
        'password_salt': next.saltBase64,
        'must_change_password': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    await _database.audit(
      _database.raw,
      userId: userId,
      action: 'auth.password_changed',
      entityType: 'user',
      entityId: userId,
    );
  }

  Future<void> logout(String userId) => _database.audit(
    _database.raw,
    userId: userId,
    action: 'auth.logout',
    entityType: 'user',
    entityId: userId,
  );

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);
}
