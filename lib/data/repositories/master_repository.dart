import '../../core/auth/security.dart';
import '../../core/db/erp_database.dart';
import 'auth_repository.dart';

class ProductInput {
  const ProductInput({
    this.id,
    required this.sku,
    this.barcode,
    required this.nameAr,
    this.nameEn,
    this.categoryId,
    this.productType = 'stock',
    this.stockUnitId = 'unit-piece',
    this.purchaseUnitId,
    this.salesUnitId,
    this.defaultTaxId,
    this.reorderPointMinor = 0,
    this.minStockMinor = 0,
    this.maxStockMinor,
    this.allowNegativeStock = false,
    this.batchEnabled = false,
    this.expiryEnabled = false,
    this.retailPriceMinor,
    this.purchasePriceMinor,
    this.purchaseCurrencyCode = 'YER',
    this.purchaseRatePpm = 1000000,
  });

  final String? id;
  final String sku;
  final String? barcode;
  final String nameAr;
  final String? nameEn;
  final String? categoryId;
  final String productType;
  final String stockUnitId;
  final String? purchaseUnitId;
  final String? salesUnitId;
  final String? defaultTaxId;
  final int reorderPointMinor;
  final int minStockMinor;
  final int? maxStockMinor;
  final bool allowNegativeStock;
  final bool batchEnabled;
  final bool expiryEnabled;
  final int? retailPriceMinor;
  final int? purchasePriceMinor;
  final String purchaseCurrencyCode;
  final int purchaseRatePpm;
}

class PartyInput {
  const PartyInput({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.email,
    this.taxNumber,
    this.region,
    this.notes,
    this.creditLimitMinor,
  });

  final String? id;
  final String name;
  final String? phone;
  final String? address;
  final String? email;
  final String? taxNumber;
  final String? region;
  final String? notes;
  final int? creditLimitMinor;
}

class MasterRepository {
  MasterRepository(this._database);
  final ErpDatabase _database;

  Future<List<Map<String, Object?>>> products({
    String search = '',
    int limit = 50,
    int offset = 0,
  }) {
    final pattern = '%${search.trim()}%';
    return _database.raw.rawQuery(
      '''SELECT p.*, c.name_ar AS category_name, u.name_ar AS unit_name,
          COALESCE(SUM(ib.quantity_minor), 0) AS stock_quantity_minor,
          MAX(pu.retail_price_minor) AS retail_price_minor,
          MAX(pu.purchase_price_minor) AS purchase_price_minor,
          p.purchase_currency_code, p.purchase_rate_ppm
       FROM products p
       LEFT JOIN categories c ON c.id = p.category_id
       LEFT JOIN units u ON u.id = p.stock_unit_id
       LEFT JOIN product_units pu ON pu.product_id = p.id AND pu.unit_id = p.stock_unit_id
       LEFT JOIN inventory_balances ib ON ib.product_id = p.id
       WHERE p.active = 1 AND (p.name_ar LIKE ? OR p.name_en LIKE ? OR p.sku LIKE ? OR p.barcode LIKE ?)
       GROUP BY p.id ORDER BY p.name_ar LIMIT ? OFFSET ?''',
      [pattern, pattern, pattern, pattern, limit, offset],
    );
  }

  Future<Map<String, Object?>?> productByBarcode(String barcode) async {
    final value = barcode.trim();
    if (value.isEmpty) return null;
    final rows = await _database.raw.rawQuery(
      '''SELECT p.*, u.name_ar AS unit_name,
          COALESCE(SUM(ib.quantity_minor), 0) AS stock_quantity_minor,
          MAX(pu.retail_price_minor) AS retail_price_minor,
          MAX(pu.purchase_price_minor) AS purchase_price_minor,
          p.purchase_currency_code, p.purchase_rate_ppm
       FROM products p
       LEFT JOIN units u ON u.id = p.stock_unit_id
       LEFT JOIN product_units pu ON pu.product_id = p.id AND pu.unit_id = p.stock_unit_id
       LEFT JOIN inventory_balances ib ON ib.product_id = p.id
       WHERE p.active = 1 AND (p.barcode = ? OR pu.barcode = ?)
       GROUP BY p.id LIMIT 1''',
      [value, value],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> customers({String search = ''}) =>
      _parties('customers', search);
  Future<List<Map<String, Object?>>> suppliers({String search = ''}) =>
      _parties('suppliers', search);

  Future<List<Map<String, Object?>>> _parties(String table, String search) {
    final pattern = '%${search.trim()}%';
    return _database.raw.query(
      table,
      where: 'active = 1 AND (name LIKE ? OR code LIKE ? OR phone LIKE ?)',
      whereArgs: [pattern, pattern, pattern],
      orderBy: 'name ASC',
    );
  }

  Future<String> saveProduct(AuthUser actor, ProductInput input) async {
    requirePermission(actor.permissions, Permissions.productsManage);
    final sku = input.sku.trim().toUpperCase();
    if (sku.isEmpty || input.nameAr.trim().isEmpty)
      throw ArgumentError('اسم الصنف والرمز مطلوبان');
    if (!const {'stock', 'service', 'non_stock'}.contains(input.productType)) {
      throw ArgumentError('نوع الصنف غير صالح');
    }
    if (input.purchaseRatePpm <= 0) {
      throw ArgumentError('سعر صرف عملة الشراء يجب أن يكون أكبر من صفر');
    }
    if (input.reorderPointMinor < 0 ||
        input.minStockMinor < 0 ||
        (input.maxStockMinor != null &&
            input.maxStockMinor! < input.minStockMinor)) {
      throw ArgumentError('حدود المخزون غير صالحة');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final id = input.id ?? await _database.newId();
    await _database.transaction((txn) async {
      final old = input.id == null
          ? null
          : await txn.query(
              'products',
              where: 'id = ?',
              whereArgs: [id],
              limit: 1,
            );
      final payload = <String, Object?>{
        'id': id,
        'sku': sku,
        'barcode': input.barcode?.trim().isEmpty == true
            ? null
            : input.barcode?.trim(),
        'name_ar': input.nameAr.trim(),
        'name_en': input.nameEn?.trim(),
        'category_id': input.categoryId,
        'product_type': input.productType,
        'stock_unit_id': input.stockUnitId,
        'purchase_unit_id': input.purchaseUnitId ?? input.stockUnitId,
        'sales_unit_id': input.salesUnitId ?? input.stockUnitId,
        'default_tax_id': input.defaultTaxId,
        'reorder_point_minor': input.reorderPointMinor,
        'min_stock_minor': input.minStockMinor,
        'max_stock_minor': input.maxStockMinor,
        'allow_negative_stock': input.allowNegativeStock ? 1 : 0,
        'batch_enabled': input.batchEnabled ? 1 : 0,
        'expiry_enabled': input.expiryEnabled ? 1 : 0,
        'purchase_currency_code': input.purchaseCurrencyCode
            .trim()
            .toUpperCase(),
        'purchase_rate_ppm': input.purchaseRatePpm,
        'active': 1,
        'updated_at': now,
      };
      if (input.id == null) {
        payload['created_at'] = now;
        await txn.insert('products', payload);
        await txn.insert('product_units', {
          'id': await _database.newId(),
          'product_id': id,
          'unit_id': input.stockUnitId,
          'factor_to_stock': 1,
          'purchase_price_minor': input.purchasePriceMinor,
          'retail_price_minor': input.retailPriceMinor,
        });
      } else {
        payload.remove('id');
        await txn.update('products', payload, where: 'id = ?', whereArgs: [id]);
        await txn.update(
          'product_units',
          {
            'purchase_price_minor': input.purchasePriceMinor,
            'retail_price_minor': input.retailPriceMinor,
          },
          where: 'product_id = ? AND unit_id = ?',
          whereArgs: [id, input.stockUnitId],
        );
      }
      await _database.audit(
        txn,
        userId: actor.id,
        action: input.id == null ? 'product.created' : 'product.updated',
        entityType: 'product',
        entityId: id,
        beforeJson: old == null || old.isEmpty ? null : old.first.toString(),
        afterJson: payload.toString(),
      );
    });
    return id;
  }

  Future<String> saveCustomer(AuthUser actor, PartyInput input) => _saveParty(
    actor,
    input,
    'customers',
    'customer',
    Permissions.customersManage,
  );
  Future<String> saveSupplier(AuthUser actor, PartyInput input) => _saveParty(
    actor,
    input,
    'suppliers',
    'supplier',
    Permissions.suppliersManage,
  );

  Future<String> _saveParty(
    AuthUser actor,
    PartyInput input,
    String table,
    String type,
    String permission,
  ) async {
    requirePermission(actor.permissions, permission);
    if (input.name.trim().isEmpty) throw ArgumentError('اسم $type مطلوب');
    if (input.creditLimitMinor != null && input.creditLimitMinor! < 0)
      throw ArgumentError('الحد الائتماني غير صالح');
    final id = input.id ?? await _database.newId();
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction((txn) async {
      final old = input.id == null
          ? null
          : await txn.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
      final payload = <String, Object?>{
        'name': input.name.trim(),
        'phone': input.phone?.trim(),
        'address': input.address?.trim(),
        'email': input.email?.trim(),
        'tax_number': input.taxNumber?.trim(),
        'notes': input.notes?.trim(),
        'credit_limit_minor': input.creditLimitMinor,
        'active': 1,
        'updated_at': now,
      };
      if (table == 'customers') payload['region'] = input.region?.trim();
      if (input.id == null) {
        payload.addAll({
          'id': id,
          'code':
              '${type.substring(0, 1).toUpperCase()}-${DateTime.now().microsecondsSinceEpoch}',
          'created_at': now,
        });
        await txn.insert(table, payload);
      } else {
        await txn.update(table, payload, where: 'id = ?', whereArgs: [id]);
      }
      await _database.audit(
        txn,
        userId: actor.id,
        action: input.id == null ? '$type.created' : '$type.updated',
        entityType: type,
        entityId: id,
        beforeJson: old == null || old.isEmpty ? null : old.first.toString(),
        afterJson: payload.toString(),
      );
    });
    return id;
  }

  Future<void> archive(
    AuthUser actor,
    String table,
    String entityType,
    String id,
    String permission,
  ) async {
    requirePermission(actor.permissions, permission);
    const allowed = {'products', 'customers', 'suppliers'};
    if (!allowed.contains(table)) throw ArgumentError('كيان أرشفة غير مسموح');
    await _database.transaction((txn) async {
      final affected = await txn.update(
        table,
        {'active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (affected != 1) throw StateError('لم يتم العثور على السجل');
      await _database.audit(
        txn,
        userId: actor.id,
        action: '$entityType.archived',
        entityType: entityType,
        entityId: id,
      );
    });
  }

  Future<List<Map<String, Object?>>> productUnits(String productId) =>
      _database.raw.rawQuery(
        '''SELECT pu.*, u.name_ar AS unit_name FROM product_units pu
           JOIN units u ON u.id = pu.unit_id WHERE pu.product_id = ? ORDER BY pu.factor_to_stock''',
        [productId],
      );

  Future<List<Map<String, Object?>>> warehouses() => _database.raw.query(
    'warehouses',
    where: 'active = 1',
    orderBy: 'name_ar',
  );
  Future<List<Map<String, Object?>>> cashboxes() =>
      _database.raw.query('cashboxes', where: 'active = 1', orderBy: 'name_ar');
  Future<List<Map<String, Object?>>> units() =>
      _database.raw.query('units', where: 'active = 1', orderBy: 'name_ar');
}
