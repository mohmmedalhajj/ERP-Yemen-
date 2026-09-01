import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

const _format = 'mohammedalhajsoft.erp.license.v1';
const _packageId = 'com.mohammedalhajsoft.integratederp';

Future<void> main(List<String> args) async {
  final options = _parseArguments(args);
  if (options.containsKey('help') || args.isEmpty) {
    _printUsage();
    exit(args.isEmpty ? 64 : 0);
  }
  final privateKeyBase64 =
      Platform.environment['ERP_LICENSE_PRIVATE_KEY_BASE64'];
  final publicKeyBase64 = Platform.environment['ERP_LICENSE_PUBLIC_KEY_BASE64'];
  if (privateKeyBase64 == null || publicKeyBase64 == null) {
    stderr.writeln(
      'يجب تعريف ERP_LICENSE_PRIVATE_KEY_BASE64 و ERP_LICENSE_PUBLIC_KEY_BASE64 في بيئة تشغيل أداة الترخيص.',
    );
    exit(64);
  }
  final customer = _require(options, 'customer');
  final installationId = _require(options, 'installation');
  final packageName = _require(options, 'package-name');
  final features = (options['features'] ?? 'transactions,reports,exports')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  if (features.isEmpty) {
    stderr.writeln('يجب تحديد ميزة واحدة على الأقل.');
    exit(64);
  }
  final now = DateTime.now().toUtc();
  final startsAt = _parseDate(options['starts'], fallback: now);
  final permanent = options['permanent'] == 'true';
  final expiresAt = permanent
      ? null
      : _parseDate(
          options['expires'],
          fallback: now.add(const Duration(days: 365)),
        );
  if (expiresAt != null && !expiresAt.isAfter(startsAt)) {
    stderr.writeln('يجب أن يكون تاريخ الانتهاء بعد تاريخ البداية.');
    exit(64);
  }
  final privateBytes = base64Decode(privateKeyBase64);
  final publicBytes = base64Decode(publicKeyBase64);
  if (privateBytes.length != 32 || publicBytes.length != 32) {
    stderr.writeln(
      'مفتاح Ed25519 يجب أن يكون 32 بايتاً لكل من المفتاحين العام والخاص.',
    );
    exit(64);
  }
  final keyPair = SimpleKeyPairData(
    privateBytes,
    publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
    type: KeyPairType.ed25519,
  );
  final licenseId = const Uuid().v4();
  final payload = <String, dynamic>{
    'format': _format,
    'license_id': licenseId,
    'package': _packageId,
    'customer_name': customer,
    'installation_id': installationId,
    'package_name': packageName,
    'features': features,
    'starts_at': startsAt.toIso8601String(),
    'expires_at': expiresAt?.toIso8601String(),
    'issued_at': now.toIso8601String(),
  };
  final payloadBytes = utf8.encode(jsonEncode(payload));
  final signature = await Ed25519().sign(payloadBytes, keyPair: keyPair);
  final envelope = <String, String>{
    'payload_base64': base64Encode(payloadBytes),
    'signature_base64': base64Encode(signature.bytes),
  };
  final envelopeJson = const JsonEncoder.withIndent('  ').convert(envelope);
  final output = options['out'] ?? 'license-$licenseId.merp';
  await File(output).writeAsString(envelopeJson, flush: true);
  stdout.writeln('تم إنشاء ملف الترخيص: ${File(output).absolute.path}');
  stdout.writeln('رقم الترخيص: $licenseId');
  stdout.writeln('كود التفعيل (ينسخ كاملاً إلى التطبيق):');
  stdout.writeln(base64Encode(utf8.encode(envelopeJson)));
  keyPair.destroy();
}

Map<String, String> _parseArguments(List<String> args) {
  final result = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final item = args[index];
    if (!item.startsWith('--')) continue;
    final key = item.substring(2);
    if (key == 'help') {
      result[key] = 'true';
      continue;
    }
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      result[key] = 'true';
      continue;
    }
    result[key] = args[++index];
  }
  return result;
}

String _require(Map<String, String> options, String key) {
  final value = options[key]?.trim();
  if (value == null || value.isEmpty) {
    stderr.writeln('الخيار --$key مطلوب.');
    _printUsage();
    exit(64);
  }
  return value;
}

DateTime _parseDate(String? raw, {required DateTime fallback}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    stderr.writeln(
      'صيغة التاريخ غير صالحة: $raw. استخدم 2026-12-31 أو ISO-8601.',
    );
    exit(64);
  }
  if (raw.length == 10) {
    return DateTime.utc(parsed.year, parsed.month, parsed.day, 23, 59, 59);
  }
  return parsed.toUtc();
}

void _printUsage() {
  stdout.writeln('''
أداة توليد تراخيص ERP دون اتصال

المفاتيح السرية لا توضع في المصدر أو APK. عرّفها في بيئة آمنة قبل التشغيل:
  ERP_LICENSE_PRIVATE_KEY_BASE64=<private-key>
  ERP_LICENSE_PUBLIC_KEY_BASE64=<public-key>

مثال:
  dart run bin/generate_license.dart \\
    --customer "اسم العميل" \\
    --installation "بصمة التثبيت من التطبيق" \\
    --package-name "Professional" \\
    --features "transactions,reports,exports" \\
    --starts 2026-08-19 --expires 2027-08-18 \\
    --out customer-license.merp

استخدم --permanent true بدلاً من --expires للترخيص الدائم.
''');
}
