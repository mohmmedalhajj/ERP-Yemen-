import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'backup_service.dart';
import 'developer_access_service.dart';
import 'license_service.dart';
import 'organization_profile_service.dart';
import 'pdf_export_service.dart';
import 'invoice_document_service.dart';
import 'inventory_alert_service.dart';
import 'report_export_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/administration_repository.dart';
import '../../data/repositories/master_repository.dart';
import '../../data/repositories/report_repository.dart';
import '../../data/repositories/reference_data_repository.dart';
import '../../domain/services/cash_accounting_service.dart';
import '../../domain/services/invoice_posting_service.dart';
import '../../domain/services/other_income_expense_service.dart';
import '../../domain/services/inventory_count_service.dart';
import '../../domain/services/stock_transfer_service.dart';
import '../../domain/services/return_posting_service.dart';
import '../db/erp_database.dart';

final databaseProvider = Provider<ErpDatabase>(
  (ref) => throw UnimplementedError('لم تتم تهيئة قاعدة البيانات'),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(databaseProvider)),
);
final administrationRepositoryProvider = Provider<AdministrationRepository>(
  (ref) => AdministrationRepository(ref.watch(databaseProvider)),
);
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);
final licenseServiceProvider = Provider<LicenseService>(
  (ref) => LicenseService(ref.watch(databaseProvider)),
);
final developerAccessServiceProvider = Provider<DeveloperAccessService>(
  (ref) => DeveloperAccessService(ref.watch(databaseProvider)),
);
final organizationProfileServiceProvider = Provider<OrganizationProfileService>(
  (ref) => OrganizationProfileService(ref.watch(databaseProvider)),
);
final organizationProfileProvider = FutureProvider<OrganizationProfile?>(
  (ref) => ref.watch(organizationProfileServiceProvider).current(),
);
final pdfExportServiceProvider = Provider<PdfExportService>(
  (ref) => PdfExportService(ref.watch(databaseProvider)),
);
final invoiceDocumentServiceProvider = Provider<InvoiceDocumentService>(
  (ref) => InvoiceDocumentService(ref.watch(databaseProvider)),
);
final reportExportServiceProvider = Provider<ReportExportService>(
  (ref) => ReportExportService(ref.watch(databaseProvider)),
);
final inventoryAlertServiceProvider = Provider<InventoryAlertService>(
  (ref) => InventoryAlertService(ref.watch(databaseProvider)),
);
final masterRepositoryProvider = Provider<MasterRepository>(
  (ref) => MasterRepository(ref.watch(databaseProvider)),
);
final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(databaseProvider)),
);
final referenceDataRepositoryProvider = Provider<ReferenceDataRepository>(
  (ref) => ReferenceDataRepository(ref.watch(databaseProvider)),
);
final invoicePostingProvider = Provider<InvoicePostingService>(
  (ref) => InvoicePostingService(
    ref.watch(databaseProvider),
    licenseService: ref.watch(licenseServiceProvider),
  ),
);
final cashAccountingProvider = Provider<CashAccountingService>(
  (ref) => CashAccountingService(
    ref.watch(databaseProvider),
    licenseService: ref.watch(licenseServiceProvider),
  ),
);
final inventoryCountProvider = Provider<InventoryCountService>(
  (ref) => InventoryCountService(ref.watch(databaseProvider)),
);
final stockTransferProvider = Provider<StockTransferService>(
  (ref) => StockTransferService(ref.watch(databaseProvider)),
);
final otherIncomeExpenseProvider = Provider<OtherIncomeExpenseService>(
  (ref) => OtherIncomeExpenseService(
    ref.watch(databaseProvider),
    licenseService: ref.watch(licenseServiceProvider),
  ),
);
final returnPostingProvider = Provider<ReturnPostingService>(
  (ref) => ReturnPostingService(
    ref.watch(databaseProvider),
    licenseService: ref.watch(licenseServiceProvider),
  ),
);

final sessionProvider = StateProvider<AuthUser?>((ref) => null);
final localeProvider = StateProvider<Locale>((ref) => const Locale('ar'));
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
