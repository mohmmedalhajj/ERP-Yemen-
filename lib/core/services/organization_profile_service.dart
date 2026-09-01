import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/erp_database.dart';

class OrganizationProfile {
  const OrganizationProfile({
    required this.id,
    required this.nameAr,
    this.nameEn,
    this.address,
    this.phones,
    this.email,
    this.taxNumber,
    this.commercialRegister,
    this.notes,
    this.logoPath,
  });

  final String id;
  final String nameAr;
  final String? nameEn;
  final String? address;
  final String? phones;
  final String? email;
  final String? taxNumber;
  final String? commercialRegister;
  final String? notes;
  final String? logoPath;

  factory OrganizationProfile.fromRow(Map<String, Object?> row) =>
      OrganizationProfile(
        id: row['id'] as String,
        nameAr: row['name_ar'] as String,
        nameEn: row['name_en'] as String?,
        address: row['address'] as String?,
        phones: row['phones'] as String?,
        email: row['email'] as String?,
        taxNumber: row['tax_number'] as String?,
        commercialRegister: row['commercial_register'] as String?,
        notes: row['notes'] as String?,
        logoPath: row['logo_path'] as String?,
      );

  Map<String, Object?> toDatabaseValues() => {
    'name_ar': nameAr.trim(),
    'name_en': _nullable(nameEn),
    'address': _nullable(address),
    'phones': _nullable(phones),
    'email': _nullable(email),
    'tax_number': _nullable(taxNumber),
    'commercial_register': _nullable(commercialRegister),
    'notes': _nullable(notes),
    'logo_path': _nullable(logoPath),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  static String? _nullable(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}

class OrganizationProfileService {
  OrganizationProfileService(this._database);

  static const defaultLogoAsset = 'assets/images/default_company_logo.png';
  static const _maxLogoBytes = 5 * 1024 * 1024;
  static const _allowedExtensions = {'.png', '.jpg', '.jpeg', '.webp'};

  final ErpDatabase _database;

  Future<OrganizationProfile?> current() async {
    final rows = await _database.raw.query('organizations', limit: 1);
    return rows.isEmpty ? null : OrganizationProfile.fromRow(rows.first);
  }

  Future<void> save(OrganizationProfile profile, {String? actorUserId}) async {
    if (profile.nameAr.trim().isEmpty) {
      throw StateError('اسم المؤسسة مطلوب');
    }
    String? previousLogoPath;
    await _database.transaction((txn) async {
      final before = await txn.query(
        'organizations',
        where: 'id = ?',
        whereArgs: [profile.id],
        limit: 1,
      );
      if (before.isEmpty) throw StateError('المؤسسة غير موجودة');
      previousLogoPath = before.first['logo_path'] as String?;
      await txn.update(
        'organizations',
        profile.toDatabaseValues(),
        where: 'id = ?',
        whereArgs: [profile.id],
      );
      await _database.audit(
        txn,
        userId: actorUserId,
        action: 'organization.updated',
        entityType: 'organization',
        entityId: profile.id,
        beforeJson: before.first.toString(),
        afterJson: profile.toDatabaseValues().toString(),
      );
    });
    if (previousLogoPath != null && previousLogoPath != profile.logoPath) {
      final oldFile = File(previousLogoPath!);
      if (await oldFile.exists()) await oldFile.delete();
    }
  }

  Future<String> persistLogo(File source) async {
    if (!await source.exists()) throw StateError('ملف الشعار غير موجود');
    final extension = p.extension(source.path).toLowerCase();
    if (!_allowedExtensions.contains(extension)) {
      throw StateError('صيغة الشعار غير مدعومة. استخدم PNG أو JPG أو WEBP.');
    }
    final length = await source.length();
    if (length <= 0 || length > _maxLogoBytes) {
      throw StateError('يجب ألا يتجاوز حجم الشعار 5 ميغابايت.');
    }
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'branding'));
    if (!await directory.exists()) await directory.create(recursive: true);
    final target = File(p.join(directory.path, 'organization_logo$extension'));
    await source.copy(target.path);
    return target.path;
  }

  Future<void> removeLogo(
    OrganizationProfile profile, {
    String? actorUserId,
  }) async {
    final oldPath = profile.logoPath;
    await save(
      OrganizationProfile(
        id: profile.id,
        nameAr: profile.nameAr,
        nameEn: profile.nameEn,
        address: profile.address,
        phones: profile.phones,
        email: profile.email,
        taxNumber: profile.taxNumber,
        commercialRegister: profile.commercialRegister,
        notes: profile.notes,
      ),
      actorUserId: actorUserId,
    );
    if (oldPath != null) {
      final file = File(oldPath);
      if (await file.exists()) await file.delete();
    }
  }

  Future<Uint8List> logoBytes(OrganizationProfile? profile) async {
    final path = profile?.logoPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) return file.readAsBytes();
    }
    final asset = await rootBundle.load(defaultLogoAsset);
    return asset.buffer.asUint8List();
  }
}
