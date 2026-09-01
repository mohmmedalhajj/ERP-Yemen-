import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';

class PasswordHash {
  const PasswordHash({required this.saltBase64, required this.hashBase64});

  final String saltBase64;
  final String hashBase64;

  Map<String, String> toMap() => {'salt': saltBase64, 'hash': hashBase64};
}

class PasswordHasher {
  PasswordHasher({Pbkdf2? algorithm})
    : _algorithm =
          algorithm ??
          Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 180000, bits: 256);

  final Pbkdf2 _algorithm;

  Future<PasswordHash> hash(String password) async {
    if (password.length < 8) {
      throw ArgumentError('كلمة المرور يجب ألا تقل عن 8 أحرف');
    }
    final salt = randomBytes(16);
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final bytes = await key.extractBytes();
    return PasswordHash(
      saltBase64: base64Encode(salt),
      hashBase64: base64Encode(bytes),
    );
  }

  Future<bool> verify({
    required String password,
    required String saltBase64,
    required String expectedHashBase64,
  }) async {
    final salt = base64Decode(saltBase64);
    final expected = base64Decode(expectedHashBase64);
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final actual = await key.extractBytes();
    return _constantTimeEquals(actual, expected);
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

class Permissions {
  const Permissions._();

  static const usersManage = 'users.manage';
  static const settingsManage = 'settings.manage';
  static const productsView = 'products.view';
  static const productsManage = 'products.manage';
  static const customersManage = 'customers.manage';
  static const suppliersManage = 'suppliers.manage';
  static const salesCreate = 'sales.create';
  static const salesPost = 'sales.post';
  static const purchasesCreate = 'purchases.create';
  static const purchasesPost = 'purchases.post';
  static const inventoryManage = 'inventory.manage';
  static const cashManage = 'cash.manage';
  static const accountingPost = 'accounting.post';
  static const reportsView = 'reports.view';
  static const costView = 'cost.view';
  static const profitView = 'profit.view';
  static const backupsManage = 'backups.manage';
  static const licensesManage = 'licenses.manage';

  static const all = <String>{
    usersManage,
    settingsManage,
    productsView,
    productsManage,
    customersManage,
    suppliersManage,
    salesCreate,
    salesPost,
    purchasesCreate,
    purchasesPost,
    inventoryManage,
    cashManage,
    accountingPost,
    reportsView,
    costView,
    profitView,
    backupsManage,
    licensesManage,
  };

  static const rolePermissions = <String, Set<String>>{
    'system_admin': all,
    'general_manager': all,
    'accountant': {
      reportsView,
      accountingPost,
      cashManage,
      costView,
      profitView,
    },
    'cashier': {salesCreate, cashManage, reportsView},
    'sales_officer': {salesCreate, salesPost, customersManage, productsView},
    'purchase_officer': {
      purchasesCreate,
      purchasesPost,
      suppliersManage,
      productsView,
    },
    'warehouse_keeper': {inventoryManage, productsManage, productsView},
    'read_only': {reportsView, productsView},
  };
}

class AuthorizationException implements Exception {
  AuthorizationException(this.message);
  final String message;
  @override
  String toString() => message;
}

void requirePermission(Set<String> permissions, String permission) {
  if (!permissions.contains(permission)) {
    throw AuthorizationException('ليس لديك صلاحية لتنفيذ هذه العملية');
  }
}
