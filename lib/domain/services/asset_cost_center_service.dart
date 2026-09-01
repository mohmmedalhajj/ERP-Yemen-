import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class AssetCostCenterService {
  AssetCostCenterService(this.db);

  final Database db;
  static const _uuid = Uuid();

  Future<void> createCostCenter({
    required String code,
    required String nameAr,
    String? parentId,
  }) async {
    if (code.trim().isEmpty || nameAr.trim().isEmpty) {
      throw ArgumentError('بيانات مركز التكلفة مطلوبة');
    }
    await db.insert('cost_centers', {
      'id': _uuid.v4(),
      'code': code.trim(),
      'name_ar': nameAr.trim(),
      'parent_id': parentId,
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  int monthlyDepreciation({
    required int acquisitionCostMinor,
    required int residualValueMinor,
    required int usefulLifeMonths,
  }) {
    if (usefulLifeMonths <= 0 || acquisitionCostMinor < residualValueMinor) {
      throw ArgumentError('بيانات الإهلاك غير صالحة');
    }
    return ((acquisitionCostMinor - residualValueMinor) / usefulLifeMonths)
        .round();
  }

  Future<void> registerAsset({
    required String assetNo,
    required String nameAr,
    required String category,
    required String purchaseDate,
    required int acquisitionCostMinor,
    required int residualValueMinor,
    required int usefulLifeMonths,
    String currencyCode = 'YER',
    int ratePpm = 1000000,
    String? costCenterId,
    String? accountId,
  }) async {
    if (assetNo.trim().isEmpty ||
        nameAr.trim().isEmpty ||
        acquisitionCostMinor < residualValueMinor ||
        usefulLifeMonths <= 0 ||
        ratePpm <= 0) {
      throw ArgumentError('بيانات الأصل غير صالحة');
    }
    await db.insert('fixed_assets', {
      'id': _uuid.v4(),
      'asset_no': assetNo.trim(),
      'name_ar': nameAr.trim(),
      'category': category.trim(),
      'purchase_date': purchaseDate,
      'acquisition_cost_minor': acquisitionCostMinor,
      'residual_value_minor': residualValueMinor,
      'useful_life_months': usefulLifeMonths,
      'accumulated_depreciation_minor': 0,
      'currency_code': currencyCode,
      'rate_ppm': ratePpm,
      'status': 'active',
      'cost_center_id': costCenterId,
      'account_id': accountId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> postMonthlyDepreciation({
    required String assetId,
    required String periodStart,
    required String periodEnd,
  }) async {
    final rows = await db.query(
      'fixed_assets',
      where: 'id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['status'] != 'active')
      throw StateError('الأصل غير متاح للإهلاك');
    final asset = rows.first;
    final amount = monthlyDepreciation(
      acquisitionCostMinor: asset['acquisition_cost_minor'] as int,
      residualValueMinor: asset['residual_value_minor'] as int,
      usefulLifeMonths: asset['useful_life_months'] as int,
    );
    final id = _uuid.v4();
    await db.transaction((txn) async {
      await txn.insert('asset_depreciation', {
        'id': id,
        'asset_id': assetId,
        'period_start': periodStart,
        'period_end': periodEnd,
        'amount_minor': amount,
        'status': 'posted',
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.rawUpdate(
        'UPDATE fixed_assets SET accumulated_depreciation_minor = accumulated_depreciation_minor + ? WHERE id = ?',
        [amount, assetId],
      );
    });
    return amount;
  }

  Future<void> createCheque({
    required String chequeNo,
    required String partyType,
    required int amountMinor,
    required String dueDate,
    String? bankName,
    String currencyCode = 'YER',
    int ratePpm = 1000000,
    String? customerId,
    String? supplierId,
  }) async {
    if (chequeNo.trim().isEmpty || amountMinor <= 0 || ratePpm <= 0)
      throw ArgumentError('بيانات الشيك غير صالحة');
    await db.insert('cheques', {
      'id': _uuid.v4(),
      'cheque_no': chequeNo.trim(),
      'bank_name': bankName,
      'party_type': partyType,
      'customer_id': customerId,
      'supplier_id': supplierId,
      'amount_minor': amountMinor,
      'currency_code': currencyCode,
      'rate_ppm': ratePpm,
      'due_date': dueDate,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> reverseCheque({
    required String chequeId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw ArgumentError('سبب العكس مطلوب');
    final updated = await db.update(
      'cheques',
      {'status': 'reversed', 'notes': reason.trim()},
      where: 'id = ? AND status = ?',
      whereArgs: [chequeId, 'pending'],
    );
    if (updated != 1) throw StateError('الشيك غير موجود أو سبق تسويته');
  }
}
