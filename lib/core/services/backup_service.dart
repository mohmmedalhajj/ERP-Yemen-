import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../db/erp_database.dart';

class BackupManifest {
  const BackupManifest({
    required this.applicationVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.databaseChecksum,
    required this.databaseBytes,
  });

  final String applicationVersion;
  final int schemaVersion;
  final String createdAt;
  final String databaseChecksum;
  final int databaseBytes;

  Map<String, Object> toJson() => {
    'application_version': applicationVersion,
    'schema_version': schemaVersion,
    'created_at': createdAt,
    'database_sha256': databaseChecksum,
    'database_bytes': databaseBytes,
  };

  factory BackupManifest.fromJson(Map<String, dynamic> json) => BackupManifest(
    applicationVersion: json['application_version'] as String,
    schemaVersion: json['schema_version'] as int,
    createdAt: json['created_at'] as String,
    databaseChecksum: json['database_sha256'] as String,
    databaseBytes: json['database_bytes'] as int,
  );
}

class BackupService {
  BackupService(this._database);
  final ErpDatabase _database;
  final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 200000,
    bits: 256,
  );
  final _cipher = AesGcm.with256bits();

  Future<File> createEncryptedBackup({
    required String password,
    Directory? directory,
  }) async {
    _checkPassword(password);
    final targetDirectory = directory ?? await _backupDirectory();
    await targetDirectory.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final snapshot = File(p.join(targetDirectory.path, '.snapshot-$stamp.db'));
    try {
      // VACUUM INTO produces a consistent point-in-time SQLite copy without closing the running database.
      final escaped = snapshot.path.replaceAll("'", "''");
      await _database.raw.execute("VACUUM INTO '$escaped'");
      final databaseBytes = await snapshot.readAsBytes();
      final packageInfo = await PackageInfo.fromPlatform();
      final manifest = BackupManifest(
        applicationVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
        schemaVersion: ErpDatabase.schemaVersion,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        databaseChecksum: crypto.sha256.convert(databaseBytes).toString(),
        databaseBytes: databaseBytes.length,
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'manifest.json',
            utf8.encode(jsonEncode(manifest.toJson())).length,
            utf8.encode(jsonEncode(manifest.toJson())),
          ),
        )
        ..addFile(
          ArchiveFile('database.db', databaseBytes.length, databaseBytes),
        );
      final zipped = ZipEncoder().encode(archive);
      if (zipped == null) throw StateError('تعذر ضغط النسخة الاحتياطية');
      final salt = randomBytes(16);
      final nonce = randomBytes(12);
      final key = await _deriveKey(password, salt);
      final sealed = await _cipher.encrypt(
        zipped,
        secretKey: key,
        nonce: nonce,
      );
      final envelope = <String, Object>{
        'format': 'mohammedalhajsoft.erp.backup.v1',
        'kdf': 'PBKDF2-HMAC-SHA256-200000',
        'cipher': 'AES-256-GCM',
        'salt': base64Encode(salt),
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(sealed.cipherText),
        'mac': base64Encode(sealed.mac.bytes),
      };
      final output = File(
        p.join(targetDirectory.path, 'integrated-erp-$stamp.merp'),
      );
      await output.writeAsString(jsonEncode(envelope), flush: true);
      await _database.raw.insert('backup_records', {
        'id': await _database.newId(),
        'local_path': output.path,
        'checksum': crypto.sha256
            .convert(await output.readAsBytes())
            .toString(),
        'schema_version': ErpDatabase.schemaVersion,
        'encrypted': 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'size_bytes': await output.length(),
      });
      return output;
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  Future<int> pruneOldBackups({int keep = 7}) async {
    if (keep < 1)
      throw ArgumentError('عدد النسخ المحتفظ بها يجب أن يكون موجباً');
    final rows = await _database.raw.query(
      'backup_records',
      orderBy: 'created_at DESC',
    );
    var removed = 0;
    for (final row in rows.skip(keep)) {
      final path = row['local_path'] as String;
      final file = File(path);
      if (await file.exists()) await file.delete();
      await _database.raw.delete(
        'backup_records',
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      removed++;
    }
    return removed;
  }

  Future<BackupManifest> inspectEncryptedBackup(
    File backup,
    String password,
  ) async {
    final restored = await _decrypt(backup, password);
    return restored.manifest;
  }

  /// تُغلق القاعدة وتستبدلها بعد التحقق الكامل. يجب إعادة تشغيل التطبيق بعدها.
  Future<BackupManifest> restoreEncryptedBackup(
    File backup,
    String password,
  ) async {
    final restored = await _decrypt(backup, password);
    if (restored.manifest.schemaVersion > ErpDatabase.schemaVersion) {
      throw StateError('النسخة من إصدار مخطط أحدث ولا يمكن استعادتها بأمان');
    }
    final livePath = _database.raw.path;
    final live = File(livePath);
    final safety = File(
      '$livePath.pre-restore-${DateTime.now().millisecondsSinceEpoch}',
    );
    final temporary = File('$livePath.restore-tmp');
    await temporary.writeAsBytes(restored.databaseBytes, flush: true);
    try {
      await _database.close();
      if (await live.exists()) await live.copy(safety.path);
      await temporary.rename(live.path);
      return restored.manifest;
    } catch (_) {
      if (await safety.exists() && !await live.exists())
        await safety.copy(live.path);
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<_DecryptedBackup> _decrypt(File backup, String password) async {
    _checkPassword(password);
    if (!await backup.exists()) throw StateError('ملف النسخة غير موجود');
    final decoded = jsonDecode(await backup.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'mohammedalhajsoft.erp.backup.v1') {
      throw StateError('تنسيق النسخة الاحتياطية غير صالح');
    }
    try {
      final salt = base64Decode(decoded['salt'] as String);
      final nonce = base64Decode(decoded['nonce'] as String);
      final box = SecretBox(
        base64Decode(decoded['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(base64Decode(decoded['mac'] as String)),
      );
      final bytes = await _cipher.decrypt(
        box,
        secretKey: await _deriveKey(password, salt),
      );
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final manifestFile = archive.findFile('manifest.json');
      final databaseFile = archive.findFile('database.db');
      if (manifestFile == null || databaseFile == null)
        throw StateError('محتويات النسخة غير مكتملة');
      final manifest = BackupManifest.fromJson(
        jsonDecode(utf8.decode(manifestFile.content as List<int>))
            as Map<String, dynamic>,
      );
      final databaseBytes = Uint8List.fromList(
        databaseFile.content as List<int>,
      );
      if (databaseBytes.length != manifest.databaseBytes ||
          crypto.sha256.convert(databaseBytes).toString() !=
              manifest.databaseChecksum) {
        throw StateError('فشل التحقق من سلامة قاعدة البيانات داخل النسخة');
      }
      return _DecryptedBackup(manifest, databaseBytes);
    } on SecretBoxAuthenticationError {
      throw StateError('كلمة المرور غير صحيحة أو الملف تم العبث به');
    } on FormatException {
      throw StateError('ملف النسخة الاحتياطية تالف');
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) =>
      _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  Future<Directory> _backupDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'backups'));
  }

  void _checkPassword(String password) {
    if (password.length < 8)
      throw ArgumentError('كلمة مرور النسخة يجب ألا تقل عن 8 أحرف');
  }
}

class _DecryptedBackup {
  const _DecryptedBackup(this.manifest, this.databaseBytes);
  final BackupManifest manifest;
  final Uint8List databaseBytes;
}
