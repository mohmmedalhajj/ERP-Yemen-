import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../db/erp_database.dart';

class LicenseStatus {
  const LicenseStatus({
    required this.state,
    required this.message,
    this.payload,
  });

  final String state;
  final String message;
  final Map<String, dynamic>? payload;

  Set<String> get features {
    final source = payload?['features'];
    if (source is! List) return const {};
    return source.whereType<String>().toSet();
  }

  bool permits(String feature) =>
      state == 'active' &&
      (features.contains('*') || features.contains(feature));

  bool get permitsNewTransactions => permits('transactions');
}

class LicenseService {
  LicenseService(this._database, {FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // المفتاح العام وحده مسموح داخل نسخة العميل؛ المفتاح الخاص لا يوجد هنا.
  static const _compiledPublicKey = String.fromEnvironment(
    'ERP_LICENSE_PUBLIC_KEY',
    defaultValue: '8mw4Bm9iVF5qtwcNHUi6MYW4mrDKYSfGMqiBcc1TBXc=',
  );
  static const _installIdKey = 'erp_installation_id_v1';

  final ErpDatabase _database;
  final FlutterSecureStorage _secureStorage;

  Future<String> installationId() async {
    final existing = await _secureStorage.read(key: _installIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _secureStorage.write(key: _installIdKey, value: created);
    return created;
  }

  Future<LicenseStatus> currentStatus() async {
    final rows = await _database.raw.query(
      'licenses',
      orderBy: 'installed_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return const LicenseStatus(
        state: 'activation_required',
        message:
            'التفعيل مطلوب للعمليات المدفوعة. تبقى البيانات والنسخ الاحتياطي والتقارير متاحة للقراءة.',
      );
    }
    final row = rows.first;
    if (row['status'] != 'active') {
      return LicenseStatus(
        state: row['status'] as String,
        message:
            'الترخيص غير نشط. تتوفر القراءة والنسخ الاحتياطي والتواصل مع الدعم.',
      );
    }
    final payload =
        jsonDecode(row['license_json'] as String) as Map<String, dynamic>;
    final now = DateTime.now().toUtc();
    final startsRaw = payload['starts_at'] as String?;
    if (startsRaw != null && DateTime.parse(startsRaw).isAfter(now)) {
      return const LicenseStatus(
        state: 'not_started',
        message: 'لم تبدأ صلاحية الترخيص بعد.',
      );
    }
    final expiresRaw = payload['expires_at'] as String?;
    if (expiresRaw != null && DateTime.parse(expiresRaw).isBefore(now)) {
      await _database.raw.update(
        'licenses',
        {'status': 'expired'},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      return const LicenseStatus(
        state: 'expired',
        message:
            'انتهت صلاحية الترخيص. تتوفر القراءة والتقارير والنسخ الاحتياطي فقط.',
      );
    }
    final trustedRaw = row['last_trusted_at'] as String?;
    if (trustedRaw != null &&
        now.isBefore(
          DateTime.parse(trustedRaw).subtract(const Duration(hours: 24)),
        )) {
      return const LicenseStatus(
        state: 'time_warning',
        message:
            'تم اكتشاف رجوع غير معتاد في وقت الجهاز. العمليات الجديدة معلقة حتى تصحيح الوقت أو التواصل مع الدعم.',
      );
    }
    await _database.raw.update(
      'licenses',
      {'last_trusted_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    return LicenseStatus(
      state: 'active',
      message:
          'الترخيص نشط: ${payload['package_name'] ?? payload['package'] ?? 'الباقة المرخصة'}',
      payload: payload,
    );
  }

  Future<String> createLicenseCode({
    required String privateKeyBase64,
    required String customerName,
    String? phone,
    String? customerId,
    required int durationDays,
    DateTime? startsAt,
    String licenseType = 'standard',
    int? maxDevices,
    List<String> features = const ['*'],
    String? notes,
  }) async {
    if (customerName.trim().isEmpty) throw ArgumentError('اسم العميل مطلوب');
    if (durationDays < 1)
      throw ArgumentError('مدة الترخيص يجب أن تكون يومًا واحدًا على الأقل');
    if (features.isEmpty) throw ArgumentError('يجب تحديد ميزة واحدة على الأقل');
    final seed = base64Decode(privateKeyBase64.trim());
    if (seed.length != 32)
      throw ArgumentError(
        'مفتاح Ed25519 الخاص يجب أن يكون Seed بطول 32 بايت بصيغة Base64',
      );
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    if (base64Encode(publicKey.bytes) != _compiledPublicKey) {
      throw StateError(
        'المفتاح الخاص لا يطابق المفتاح العام المضمّن في التطبيق',
      );
    }
    final resolvedCustomer = await _database.raw.query(
      'customers',
      columns: ['id', 'name', 'phone'],
      where: 'active = 1 AND name = ?',
      whereArgs: [customerName.trim()],
      limit: 1,
    );
    final resolvedId = customerId?.trim().isNotEmpty == true
        ? customerId!.trim()
        : (resolvedCustomer.isEmpty
              ? null
              : resolvedCustomer.first['id'] as String);
    final resolvedPhone = phone?.trim().isNotEmpty == true
        ? phone!.trim()
        : (resolvedCustomer.isEmpty
              ? null
              : resolvedCustomer.first['phone'] as String?);
    final start = (startsAt ?? DateTime.now().toUtc()).toUtc();
    final expiry = start.add(Duration(days: durationDays));
    final payload = <String, dynamic>{
      'format': 'mohammedalhajsoft.erp.license.v1',
      'package': 'com.mohammedalhajsoft.integratederp',
      'package_name': 'Integrated ERP Yemen',
      'license_id': const Uuid().v4(),
      'customer_name': customerName.trim(),
      if (resolvedPhone != null && resolvedPhone.trim().isNotEmpty)
        'phone': resolvedPhone.trim(),
      if (resolvedId != null && resolvedId.isNotEmpty)
        'customer_id': resolvedId,
      'license_type': licenseType,
      'features': features,
      'starts_at': start.toIso8601String(),
      'expires_at': expiry.toIso8601String(),
      'max_devices': maxDevices,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
    final payloadBytes = utf8.encode(jsonEncode(payload));
    final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);
    final envelope = <String, dynamic>{
      'format': 'mohammedalhajsoft.erp.license.envelope.v1',
      'payload_base64': base64Encode(payloadBytes),
      'signature_base64': base64Encode(signature.bytes),
    };
    await _database.audit(
      _database.raw,
      action: 'license.created',
      entityType: 'license',
      entityId: payload['license_id'] as String,
      afterJson: jsonEncode({
        'customer_name': customerName.trim(),
        'expires_at': payload['expires_at'],
        'license_type': licenseType,
      }),
    );
    return base64Encode(utf8.encode(jsonEncode(envelope)));
  }

  Future<LicenseStatus> install(File file) async =>
      installCode(await file.readAsString());

  Future<LicenseStatus> installCode(String code) async {
    try {
      final envelope = _decodeEnvelope(code);
      final payloadBytes = base64Decode(envelope['payload_base64'] as String);
      final signatureBase64 = envelope['signature_base64'] as String;
      final signatureBytes = base64Decode(signatureBase64);
      final publicKeyBytes = base64Decode(_compiledPublicKey);
      if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
        throw StateError('مفتاح أو توقيع الترخيص غير صالح');
      }
      final verified = await Ed25519().verify(
        payloadBytes,
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
      if (!verified) throw StateError('فشل التحقق من توقيع الترخيص');
      final payload =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      _validatePayload(payload);
      final targetInstallation = payload['installation_id'];
      if (targetInstallation is String && targetInstallation.isNotEmpty) {
        final localInstallation = await installationId();
        if (targetInstallation != localInstallation) {
          throw StateError('الترخيص صادر لجهاز أو تثبيت آخر');
        }
      }
      final id = payload['license_id'] as String;
      final now = DateTime.now().toUtc().toIso8601String();
      await _database.raw.insert('licenses', {
        'id': id,
        'license_json': jsonEncode(payload),
        'signature_base64': signatureBase64,
        'status': 'active',
        'installed_at': now,
        'last_trusted_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _database.audit(
        _database.raw,
        action: 'license.installed',
        entityType: 'license',
        entityId: id,
        afterJson: jsonEncode({
          'customer': payload['customer_name'],
          'package': payload['package_name'],
          'expires_at': payload['expires_at'],
        }),
      );
      return LicenseStatus(
        state: 'active',
        message: 'تم تفعيل الترخيص بنجاح',
        payload: payload,
      );
    } catch (error) {
      await _auditFailedActivation(error);
      rethrow;
    }
  }

  Future<void> deactivateCurrent({String reason = 'developer_action'}) async {
    final rows = await _database.raw.query(
      'licenses',
      orderBy: 'installed_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('لا يوجد ترخيص مثبت لإيقافه');
    final id = rows.first['id'] as String;
    await _database.raw.update(
      'licenses',
      {'status': 'revoked'},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _database.audit(
      _database.raw,
      action: 'license.deactivated',
      entityType: 'license',
      entityId: id,
      afterJson: jsonEncode({'reason': reason}),
    );
  }

  Map<String, dynamic> _decodeEnvelope(String raw) {
    final value = raw.trim();
    if (value.isEmpty) throw StateError('أدخل كود التفعيل أو اختر ملف الترخيص');
    final decoded = value.startsWith('{')
        ? value
        : utf8.decode(base64Decode(value));
    final envelope = jsonDecode(decoded);
    if (envelope is! Map<String, dynamic>)
      throw StateError('كود الترخيص غير صالح');
    return envelope;
  }

  void _validatePayload(Map<String, dynamic> payload) {
    if (payload['format'] != 'mohammedalhajsoft.erp.license.v1') {
      throw StateError('إصدار الترخيص غير مدعوم');
    }
    if (payload['package'] != 'com.mohammedalhajsoft.integratederp') {
      throw StateError('الترخيص ليس لهذه الحزمة');
    }
    if (payload['license_id'] is! String ||
        payload['customer_name'] is! String) {
      throw StateError('بيانات العميل في الترخيص غير مكتملة');
    }
    final features = payload['features'];
    if (features is! List || features.whereType<String>().isEmpty) {
      throw StateError('لا يحتوي الترخيص على ميزات مفعلة');
    }
    final expiresRaw = payload['expires_at'] as String?;
    if (expiresRaw != null &&
        DateTime.parse(expiresRaw).isBefore(DateTime.now().toUtc())) {
      throw StateError('ملف الترخيص منتهٍ');
    }
  }

  Future<void> _auditFailedActivation(Object error) async {
    try {
      final installId = await installationId();
      await _database.audit(
        _database.raw,
        action: 'license.install_failed',
        entityType: 'license',
        entityId: installId,
        afterJson: jsonEncode({
          'reason': error.toString().replaceFirst('Bad state: ', ''),
        }),
      );
    } catch (_) {
      // لا تمنع الكتابة في سجل التدقيق رسالة الخطأ الأصلية أو التحقق المحلي.
    }
  }
}
