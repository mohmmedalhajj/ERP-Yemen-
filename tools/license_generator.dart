import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    stdout.writeln(_Options.helpText);
    return;
  }
  final seedBase64 = Platform.environment['ERP_LICENSE_SEED_BASE64'];
  if (seedBase64 == null || seedBase64.isEmpty) {
    stderr.writeln(
      'ERP_LICENSE_SEED_BASE64 مطلوب، ويجب أن يحتوي بذرة Ed25519 بطول 32 بايت بصيغة Base64.',
    );
    exitCode = 64;
    return;
  }
  final seed = base64Decode(seedBase64);
  if (seed.length != 32) {
    stderr.writeln(
      'بذرة Ed25519 يجب أن تكون 32 بايت. لا تضعها داخل المشروع أو ملف APK.',
    );
    exitCode = 64;
    return;
  }
  if (options.customer.isEmpty || options.installationId.isEmpty) {
    stderr.writeln('يلزم تحديد --customer و--installation-id.');
    exitCode = 64;
    return;
  }
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final payload = <String, Object?>{
    'format': 'mohammedalhajsoft.erp.license.v1',
    'license_id': options.licenseId,
    'customer_name': options.customer,
    'customer_number': options.customerNumber,
    'installation_id': options.installationId,
    'package': options.packageName,
    'plan': options.plan,
    'issued_at': DateTime.now().toUtc().toIso8601String(),
    'not_before': options.notBefore,
    'expires_at': options.expiresAt,
    'max_branches': options.maxBranches,
    'features': options.features,
  };
  final payloadBytes = utf8.encode(jsonEncode(payload));
  final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);
  final envelope = <String, Object>{
    'payload_base64': base64Encode(payloadBytes),
    'signature_base64': base64Encode(signature.bytes),
    'public_key_base64': base64Encode(publicKey.bytes),
  };
  final output = File(options.outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert(envelope),
    flush: true,
  );
  stdout.writeln('تم إنشاء ملف الترخيص: ${output.path}');
  stdout.writeln(
    'المفتاح العام للتضمين في التطبيق: ${base64Encode(publicKey.bytes)}',
  );
}

class _Options {
  _Options({
    required this.licenseId,
    required this.customer,
    required this.customerNumber,
    required this.installationId,
    required this.packageName,
    required this.plan,
    required this.notBefore,
    required this.expiresAt,
    required this.maxBranches,
    required this.features,
    required this.outputPath,
    required this.help,
  });

  final String licenseId;
  final String customer;
  final String customerNumber;
  final String installationId;
  final String packageName;
  final String plan;
  final String? notBefore;
  final String? expiresAt;
  final int maxBranches;
  final List<String> features;
  final String outputPath;
  final bool help;

  static _Options parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (arg == '--help' || arg == '-h') return _Options.empty(help: true);
      if (!arg.startsWith('--') || index + 1 >= args.length) continue;
      values[arg.substring(2)] = args[++index];
    }
    final expires = values['expires-at'];
    if (expires != null) DateTime.parse(expires);
    final notBefore = values['not-before'];
    if (notBefore != null) DateTime.parse(notBefore);
    return _Options(
      licenseId: values['license-id'] ?? const Uuid().v4(),
      customer: values['customer'] ?? '',
      customerNumber: values['customer-number'] ?? '',
      installationId: values['installation-id'] ?? '',
      packageName: values['package'] ?? 'com.mohammedalhajsoft.integratederp',
      plan: values['plan'] ?? 'standard',
      notBefore: notBefore,
      expiresAt: expires,
      maxBranches: int.tryParse(values['max-branches'] ?? '') ?? 1,
      features:
          (values['features'] ??
                  'sales,purchases,inventory,accounting,reports,backup')
              .split(',')
              .where((value) => value.isNotEmpty)
              .toList(),
      outputPath: values['output'] ?? 'license.merp',
      help: false,
    );
  }

  factory _Options.empty({required bool help}) => _Options(
    licenseId: '',
    customer: '',
    customerNumber: '',
    installationId: '',
    packageName: '',
    plan: '',
    notBefore: null,
    expiresAt: null,
    maxBranches: 1,
    features: const [],
    outputPath: '',
    help: help,
  );

  static const helpText = '''
مولد تراخيص محمد الحاج سوفت — Offline Ed25519

الاستخدام:
ERP_LICENSE_SEED_BASE64="<base64-32-byte-seed>" dart run tools/license_generator.dart \\
  --customer "اسم العميل" --customer-number "رقم العميل" \\
  --installation-id "بصمة التثبيت" --plan standard --max-branches 1 \\
  --features sales,purchases,inventory,accounting,reports,backup \\
  --expires-at 2027-12-31T23:59:59Z --output client.merp

عدم تحديد --expires-at ينتج ترخيصاً دائماً. لا تضع ERP_LICENSE_SEED_BASE64 في Git أو APK أو التخزين السحابي غير المشفر.
''';
}
