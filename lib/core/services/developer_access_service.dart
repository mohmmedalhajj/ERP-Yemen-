import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/security.dart';
import '../db/erp_database.dart';

class DeveloperAccessService {
  DeveloperAccessService(this._database, {FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // هاتان القيمتان مشتقتان من كلمة المرور الأولية؛ لا توجد كلمة المرور كنص في العميل.
  static const _defaultSalt = 'qth0RWFZ7sVpkldtF+zCyA==';
  static const _defaultHash = 'wokJSmSbqGMG2553r1z/Eln7hAo3vOnfdBYzJU41PQU=';
  static const _hashKey = 'erp_developer_password_hash_v1';
  static const _saltKey = 'erp_developer_password_salt_v1';

  final ErpDatabase _database;
  final FlutterSecureStorage _secureStorage;
  final PasswordHasher _hasher = PasswordHasher();

  Future<bool> verify(String password) async {
    final hash = await _secureStorage.read(key: _hashKey) ?? _defaultHash;
    final salt = await _secureStorage.read(key: _saltKey) ?? _defaultSalt;
    final granted = await _hasher.verify(
      password: password,
      saltBase64: salt,
      expectedHashBase64: hash,
    );
    await _database.audit(
      _database.raw,
      action: granted ? 'developer.access_granted' : 'developer.access_denied',
      entityType: 'developer_access',
      entityId: 'local',
      afterJson: jsonEncode({'at': DateTime.now().toUtc().toIso8601String()}),
    );
    return granted;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final valid = await verify(currentPassword);
    if (!valid) throw StateError('كلمة مرور المطور الحالية غير صحيحة');
    final next = await _hasher.hash(newPassword);
    await _secureStorage.write(key: _hashKey, value: next.hashBase64);
    await _secureStorage.write(key: _saltKey, value: next.saltBase64);
    await _database.audit(
      _database.raw,
      action: 'developer.password_changed',
      entityType: 'developer_access',
      entityId: 'local',
    );
  }
}
