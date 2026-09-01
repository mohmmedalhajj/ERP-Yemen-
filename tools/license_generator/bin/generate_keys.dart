import 'dart:convert';

import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateData = await keyPair.extract();
  final publicKey = await keyPair.extractPublicKey();
  print('ERP_LICENSE_PRIVATE_KEY_BASE64=${base64Encode(privateData.bytes)}');
  print('ERP_LICENSE_PUBLIC_KEY_BASE64=${base64Encode(publicKey.bytes)}');
  print('احفظ المفتاح الخاص في مدير أسرار أو متغير بيئة آمن فقط.');
  print('ضع المفتاح العام فقط في إعداد بناء تطبيق العميل.');
  keyPair.destroy();
}
