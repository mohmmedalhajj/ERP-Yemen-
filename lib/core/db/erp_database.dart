import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../auth/security.dart';

class ErpDatabase {
  ErpDatabase._(this._db);

  final Database _db;
  static const schemaVersion = 6;
  static const _uuid = Uuid();

  Database get raw => _db;

  static Future<ErpDatabase> open({String? databasePath}) async {
    final path = databasePath ?? await _defaultPath();
    final database = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seedReferenceData(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrate(db, oldVersion, newVersion);
      },
    );
    return ErpDatabase._(database);
  }

  static Future<String> _defaultPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'integrated_erp.db');
  }

  static Future<void> _migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // الهجرة الإضافية لا تحذف أي بيانات؛ الجداول والفهارس الجديدة فقط.
    await _createSchema(db);
    if (oldVersion < 2) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id)',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_journal_source ON journal_entries(source_type, source_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_inventory_product_warehouse ON inventory_balances(product_id, warehouse_id)',
      );
    }
    if (oldVersion < 4) {
      // تُضاف الحقول فقط ولا تحذف أو تعيد بناء أي سجلات قائمة.
      await db.execute(
        "ALTER TABLE stock_counts ADD COLUMN count_type TEXT NOT NULL DEFAULT 'custom'",
      );
      await db.execute('ALTER TABLE stock_counts ADD COLUMN period_start TEXT');
      await db.execute('ALTER TABLE stock_counts ADD COLUMN period_end TEXT');
      await db.execute('ALTER TABLE stock_counts ADD COLUMN category_id TEXT');
      await db.execute('ALTER TABLE stock_counts ADD COLUMN notes TEXT');
      await db.execute('ALTER TABLE stock_counts ADD COLUMN cancelled_at TEXT');
      await db.execute('ALTER TABLE stock_counts ADD COLUMN cancelled_by TEXT');
      await db.execute(
        'ALTER TABLE stock_counts ADD COLUMN adjustment_journal_id TEXT',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_count_status ON stock_counts(warehouse_id, status, created_at)',
      );
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE organizations ADD COLUMN notes TEXT');
    }
    if (oldVersion < 6) {
      await _createFinancialOperationsSchema(db);
    }
    await _seedReferenceData(db);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    final schema = <String>[
      '''CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS organizations (
        id TEXT PRIMARY KEY, name_ar TEXT NOT NULL, name_en TEXT, address TEXT,
        phones TEXT, email TEXT, commercial_register TEXT, tax_number TEXT,
        base_currency TEXT NOT NULL DEFAULT 'YER', currency_decimals INTEGER NOT NULL DEFAULT 0,
        quantity_decimals INTEGER NOT NULL DEFAULT 3, language_code TEXT NOT NULL DEFAULT 'ar',
        theme_mode TEXT NOT NULL DEFAULT 'system', fiscal_year_start TEXT, fiscal_year_end TEXT,
        logo_path TEXT, notes TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS branches (
        id TEXT PRIMARY KEY, organization_id TEXT NOT NULL, code TEXT NOT NULL,
        name_ar TEXT NOT NULL, name_en TEXT, address TEXT, phone TEXT, active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL, UNIQUE(organization_id, code),
        FOREIGN KEY(organization_id) REFERENCES organizations(id) ON DELETE RESTRICT
      )''',
      '''CREATE TABLE IF NOT EXISTS warehouses (
        id TEXT PRIMARY KEY, branch_id TEXT NOT NULL, code TEXT NOT NULL,
        name_ar TEXT NOT NULL, name_en TEXT, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL,
        UNIQUE(branch_id, code), FOREIGN KEY(branch_id) REFERENCES branches(id) ON DELETE RESTRICT
      )''',
      '''CREATE TABLE IF NOT EXISTS cashboxes (
        id TEXT PRIMARY KEY, branch_id TEXT NOT NULL, code TEXT NOT NULL,
        name_ar TEXT NOT NULL, type TEXT NOT NULL DEFAULT 'cash', active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL, UNIQUE(branch_id, code),
        FOREIGN KEY(branch_id) REFERENCES branches(id) ON DELETE RESTRICT
      )''',
      '''CREATE TABLE IF NOT EXISTS currencies (
        code TEXT PRIMARY KEY, name_ar TEXT NOT NULL, name_en TEXT,
        symbol TEXT, decimals INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1
      )''',
      '''CREATE TABLE IF NOT EXISTS exchange_rates (
        id TEXT PRIMARY KEY, currency_code TEXT NOT NULL, rate_ppm INTEGER NOT NULL CHECK(rate_ppm > 0),
        effective_date TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'manual', created_by TEXT, created_at TEXT NOT NULL,
        UNIQUE(currency_code, effective_date), FOREIGN KEY(currency_code) REFERENCES currencies(code)
      )''',
      '''CREATE TABLE IF NOT EXISTS taxes (
        id TEXT PRIMARY KEY, name_ar TEXT NOT NULL, name_en TEXT, rate_basis_points INTEGER NOT NULL DEFAULT 0,
        inclusive INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, account_id TEXT
      )''',
      '''CREATE TABLE IF NOT EXISTS roles (
        id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name_ar TEXT NOT NULL, name_en TEXT,
        system_role INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1
      )''',
      '''CREATE TABLE IF NOT EXISTS permissions (
        code TEXT PRIMARY KEY, name_ar TEXT NOT NULL, module TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS role_permissions (
        role_id TEXT NOT NULL, permission_code TEXT NOT NULL,
        PRIMARY KEY(role_id, permission_code),
        FOREIGN KEY(role_id) REFERENCES roles(id) ON DELETE CASCADE,
        FOREIGN KEY(permission_code) REFERENCES permissions(code) ON DELETE CASCADE
      )''',
      '''CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
        password_hash TEXT NOT NULL, password_salt TEXT NOT NULL, role_id TEXT NOT NULL,
        branch_id TEXT, warehouse_id TEXT, cashbox_id TEXT, active INTEGER NOT NULL DEFAULT 1,
        must_change_password INTEGER NOT NULL DEFAULT 1, failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT, last_login_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        FOREIGN KEY(role_id) REFERENCES roles(id), FOREIGN KEY(branch_id) REFERENCES branches(id),
        FOREIGN KEY(warehouse_id) REFERENCES warehouses(id), FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY, user_id TEXT, action TEXT NOT NULL, entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL, before_json TEXT, after_json TEXT, created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY, parent_id TEXT, name_ar TEXT NOT NULL, name_en TEXT, active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(parent_id) REFERENCES categories(id) ON DELETE RESTRICT
      )''',
      '''CREATE TABLE IF NOT EXISTS units (
        id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name_ar TEXT NOT NULL, name_en TEXT,
        precision_digits INTEGER NOT NULL DEFAULT 3, active INTEGER NOT NULL DEFAULT 1
      )''',
      '''CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY, sku TEXT NOT NULL UNIQUE, barcode TEXT UNIQUE, name_ar TEXT NOT NULL, name_en TEXT,
        category_id TEXT, product_type TEXT NOT NULL DEFAULT 'stock', description TEXT, image_path TEXT,
        stock_unit_id TEXT NOT NULL, purchase_unit_id TEXT, sales_unit_id TEXT,
        default_tax_id TEXT, reorder_point_minor INTEGER NOT NULL DEFAULT 0,
        min_stock_minor INTEGER NOT NULL DEFAULT 0, max_stock_minor INTEGER,
        allow_negative_stock INTEGER NOT NULL DEFAULT 0, batch_enabled INTEGER NOT NULL DEFAULT 0,
        expiry_enabled INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        FOREIGN KEY(category_id) REFERENCES categories(id), FOREIGN KEY(stock_unit_id) REFERENCES units(id),
        FOREIGN KEY(purchase_unit_id) REFERENCES units(id), FOREIGN KEY(sales_unit_id) REFERENCES units(id),
        FOREIGN KEY(default_tax_id) REFERENCES taxes(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS product_units (
        id TEXT PRIMARY KEY, product_id TEXT NOT NULL, unit_id TEXT NOT NULL,
        factor_to_stock INTEGER NOT NULL CHECK(factor_to_stock > 0), barcode TEXT,
        purchase_price_minor INTEGER, retail_price_minor INTEGER, wholesale_price_minor INTEGER,
        half_wholesale_price_minor INTEGER, min_sale_price_minor INTEGER,
        UNIQUE(product_id, unit_id), FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE,
        FOREIGN KEY(unit_id) REFERENCES units(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS price_lists (
        id TEXT PRIMARY KEY, name_ar TEXT NOT NULL, currency_code TEXT NOT NULL DEFAULT 'YER', active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(currency_code) REFERENCES currencies(code)
      )''',
      '''CREATE TABLE IF NOT EXISTS price_list_items (
        id TEXT PRIMARY KEY, price_list_id TEXT NOT NULL, product_id TEXT NOT NULL, unit_id TEXT NOT NULL,
        price_minor INTEGER NOT NULL CHECK(price_minor >= 0), UNIQUE(price_list_id, product_id, unit_id),
        FOREIGN KEY(price_list_id) REFERENCES price_lists(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id), FOREIGN KEY(unit_id) REFERENCES units(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, phone TEXT, address TEXT, email TEXT,
        tax_number TEXT, region TEXT, notes TEXT, credit_limit_minor INTEGER, active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, phone TEXT, address TEXT, email TEXT,
        tax_number TEXT, notes TEXT, credit_limit_minor INTEGER, active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS inventory_balances (
        id TEXT PRIMARY KEY, product_id TEXT NOT NULL, warehouse_id TEXT NOT NULL,
        quantity_minor INTEGER NOT NULL DEFAULT 0, average_cost_minor INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL, UNIQUE(product_id, warehouse_id),
        FOREIGN KEY(product_id) REFERENCES products(id), FOREIGN KEY(warehouse_id) REFERENCES warehouses(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS stock_batches (
        id TEXT PRIMARY KEY, product_id TEXT NOT NULL, warehouse_id TEXT NOT NULL, batch_no TEXT NOT NULL,
        quantity_minor INTEGER NOT NULL DEFAULT 0, unit_cost_minor INTEGER NOT NULL DEFAULT 0,
        production_date TEXT, expiry_date TEXT, active INTEGER NOT NULL DEFAULT 1,
        UNIQUE(product_id, warehouse_id, batch_no), FOREIGN KEY(product_id) REFERENCES products(id),
        FOREIGN KEY(warehouse_id) REFERENCES warehouses(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS inventory_movements (
        id TEXT PRIMARY KEY, product_id TEXT NOT NULL, warehouse_id TEXT NOT NULL, batch_id TEXT,
        movement_type TEXT NOT NULL, quantity_minor INTEGER NOT NULL CHECK(quantity_minor <> 0),
        unit_cost_minor INTEGER NOT NULL DEFAULT 0, balance_after_minor INTEGER NOT NULL,
        source_type TEXT NOT NULL, source_id TEXT NOT NULL, occurred_at TEXT NOT NULL, user_id TEXT,
        FOREIGN KEY(product_id) REFERENCES products(id), FOREIGN KEY(warehouse_id) REFERENCES warehouses(id),
        FOREIGN KEY(batch_id) REFERENCES stock_batches(id), FOREIGN KEY(user_id) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS stock_transfers (
        id TEXT PRIMARY KEY, document_no TEXT NOT NULL UNIQUE, from_warehouse_id TEXT NOT NULL, to_warehouse_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft', sent_at TEXT, received_at TEXT, created_by TEXT, created_at TEXT NOT NULL,
        CHECK(from_warehouse_id <> to_warehouse_id), FOREIGN KEY(from_warehouse_id) REFERENCES warehouses(id),
        FOREIGN KEY(to_warehouse_id) REFERENCES warehouses(id), FOREIGN KEY(created_by) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS stock_transfer_lines (
        id TEXT PRIMARY KEY, transfer_id TEXT NOT NULL, product_id TEXT NOT NULL, quantity_minor INTEGER NOT NULL CHECK(quantity_minor > 0),
        unit_cost_minor INTEGER NOT NULL DEFAULT 0, FOREIGN KEY(transfer_id) REFERENCES stock_transfers(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS stock_counts (
        id TEXT PRIMARY KEY, document_no TEXT NOT NULL UNIQUE, warehouse_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft',
        count_type TEXT NOT NULL DEFAULT 'custom', period_start TEXT, period_end TEXT, category_id TEXT, notes TEXT,
        created_by TEXT, approved_by TEXT, created_at TEXT NOT NULL, posted_at TEXT, cancelled_at TEXT, cancelled_by TEXT,
        adjustment_journal_id TEXT,
        FOREIGN KEY(warehouse_id) REFERENCES warehouses(id), FOREIGN KEY(category_id) REFERENCES categories(id),
        FOREIGN KEY(created_by) REFERENCES users(id), FOREIGN KEY(approved_by) REFERENCES users(id),
        FOREIGN KEY(cancelled_by) REFERENCES users(id), FOREIGN KEY(adjustment_journal_id) REFERENCES journal_entries(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS stock_count_lines (
        id TEXT PRIMARY KEY, stock_count_id TEXT NOT NULL, product_id TEXT NOT NULL, system_qty_minor INTEGER NOT NULL,
        counted_qty_minor INTEGER NOT NULL, FOREIGN KEY(stock_count_id) REFERENCES stock_counts(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS fiscal_periods (
        id TEXT PRIMARY KEY, organization_id TEXT NOT NULL, name TEXT NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL,
        closed INTEGER NOT NULL DEFAULT 0, UNIQUE(organization_id, start_date, end_date),
        FOREIGN KEY(organization_id) REFERENCES organizations(id) ON DELETE RESTRICT
      )''',
      '''CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name_ar TEXT NOT NULL, name_en TEXT,
        account_type TEXT NOT NULL, parent_id TEXT, is_control INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(parent_id) REFERENCES accounts(id) ON DELETE RESTRICT
      )''',
      '''CREATE TABLE IF NOT EXISTS journal_entries (
        id TEXT PRIMARY KEY, entry_no TEXT NOT NULL UNIQUE, entry_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft',
        source_type TEXT, source_id TEXT, description TEXT, fiscal_period_id TEXT, created_by TEXT, posted_by TEXT,
        posted_at TEXT, reversed_entry_id TEXT, created_at TEXT NOT NULL,
        UNIQUE(source_type, source_id), FOREIGN KEY(fiscal_period_id) REFERENCES fiscal_periods(id),
        FOREIGN KEY(created_by) REFERENCES users(id), FOREIGN KEY(posted_by) REFERENCES users(id),
        FOREIGN KEY(reversed_entry_id) REFERENCES journal_entries(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS journal_lines (
        id TEXT PRIMARY KEY, journal_entry_id TEXT NOT NULL, account_id TEXT NOT NULL,
        debit_minor INTEGER NOT NULL DEFAULT 0 CHECK(debit_minor >= 0), credit_minor INTEGER NOT NULL DEFAULT 0 CHECK(credit_minor >= 0),
        currency_code TEXT NOT NULL DEFAULT 'YER', rate_ppm INTEGER NOT NULL DEFAULT 1000000,
        description TEXT, customer_id TEXT, supplier_id TEXT, cashbox_id TEXT,
        CHECK((debit_minor = 0) <> (credit_minor = 0)), FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE,
        FOREIGN KEY(account_id) REFERENCES accounts(id), FOREIGN KEY(customer_id) REFERENCES customers(id),
        FOREIGN KEY(supplier_id) REFERENCES suppliers(id), FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS sales_invoices (
        id TEXT PRIMARY KEY, invoice_no TEXT NOT NULL UNIQUE, branch_id TEXT NOT NULL, warehouse_id TEXT NOT NULL,
        customer_id TEXT, cashbox_id TEXT, status TEXT NOT NULL DEFAULT 'draft', sale_type TEXT NOT NULL DEFAULT 'cash',
        invoice_date TEXT NOT NULL, currency_code TEXT NOT NULL DEFAULT 'YER', rate_ppm INTEGER NOT NULL DEFAULT 1000000,
        subtotal_minor INTEGER NOT NULL DEFAULT 0, discount_minor INTEGER NOT NULL DEFAULT 0, tax_minor INTEGER NOT NULL DEFAULT 0,
        total_minor INTEGER NOT NULL DEFAULT 0, paid_minor INTEGER NOT NULL DEFAULT 0, due_minor INTEGER NOT NULL DEFAULT 0,
        cost_minor INTEGER NOT NULL DEFAULT 0, original_invoice_id TEXT, created_by TEXT, posted_at TEXT, cancelled_at TEXT,
        notes TEXT, FOREIGN KEY(branch_id) REFERENCES branches(id), FOREIGN KEY(warehouse_id) REFERENCES warehouses(id),
        FOREIGN KEY(customer_id) REFERENCES customers(id), FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id),
        FOREIGN KEY(original_invoice_id) REFERENCES sales_invoices(id), FOREIGN KEY(created_by) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS sales_lines (
        id TEXT PRIMARY KEY, invoice_id TEXT NOT NULL, product_id TEXT NOT NULL, unit_id TEXT NOT NULL,
        quantity_minor INTEGER NOT NULL CHECK(quantity_minor > 0), conversion_factor INTEGER NOT NULL DEFAULT 1,
        unit_price_minor INTEGER NOT NULL CHECK(unit_price_minor >= 0), discount_minor INTEGER NOT NULL DEFAULT 0 CHECK(discount_minor >= 0),
        tax_rate_basis_points INTEGER NOT NULL DEFAULT 0, tax_minor INTEGER NOT NULL DEFAULT 0, line_total_minor INTEGER NOT NULL,
        unit_cost_minor INTEGER NOT NULL DEFAULT 0, returned_qty_minor INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(invoice_id) REFERENCES sales_invoices(id) ON DELETE CASCADE, FOREIGN KEY(product_id) REFERENCES products(id),
        FOREIGN KEY(unit_id) REFERENCES units(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS purchase_invoices (
        id TEXT PRIMARY KEY, invoice_no TEXT NOT NULL UNIQUE, supplier_invoice_no TEXT, branch_id TEXT NOT NULL, warehouse_id TEXT NOT NULL,
        supplier_id TEXT, cashbox_id TEXT, status TEXT NOT NULL DEFAULT 'draft', purchase_type TEXT NOT NULL DEFAULT 'cash',
        invoice_date TEXT NOT NULL, currency_code TEXT NOT NULL DEFAULT 'YER', rate_ppm INTEGER NOT NULL DEFAULT 1000000,
        subtotal_minor INTEGER NOT NULL DEFAULT 0, discount_minor INTEGER NOT NULL DEFAULT 0, tax_minor INTEGER NOT NULL DEFAULT 0,
        extra_cost_minor INTEGER NOT NULL DEFAULT 0, total_minor INTEGER NOT NULL DEFAULT 0, paid_minor INTEGER NOT NULL DEFAULT 0,
        due_minor INTEGER NOT NULL DEFAULT 0, original_invoice_id TEXT, created_by TEXT, posted_at TEXT, notes TEXT,
        FOREIGN KEY(branch_id) REFERENCES branches(id), FOREIGN KEY(warehouse_id) REFERENCES warehouses(id),
        FOREIGN KEY(supplier_id) REFERENCES suppliers(id), FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id),
        FOREIGN KEY(original_invoice_id) REFERENCES purchase_invoices(id), FOREIGN KEY(created_by) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS purchase_lines (
        id TEXT PRIMARY KEY, invoice_id TEXT NOT NULL, product_id TEXT NOT NULL, unit_id TEXT NOT NULL,
        quantity_minor INTEGER NOT NULL CHECK(quantity_minor > 0), conversion_factor INTEGER NOT NULL DEFAULT 1,
        unit_cost_minor INTEGER NOT NULL CHECK(unit_cost_minor >= 0), discount_minor INTEGER NOT NULL DEFAULT 0,
        allocated_extra_cost_minor INTEGER NOT NULL DEFAULT 0, tax_rate_basis_points INTEGER NOT NULL DEFAULT 0,
        tax_minor INTEGER NOT NULL DEFAULT 0, line_total_minor INTEGER NOT NULL,
        FOREIGN KEY(invoice_id) REFERENCES purchase_invoices(id) ON DELETE CASCADE, FOREIGN KEY(product_id) REFERENCES products(id),
        FOREIGN KEY(unit_id) REFERENCES units(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS cash_movements (
        id TEXT PRIMARY KEY, cashbox_id TEXT NOT NULL, movement_type TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor <> 0),
        currency_code TEXT NOT NULL DEFAULT 'YER', rate_ppm INTEGER NOT NULL DEFAULT 1000000, source_type TEXT NOT NULL, source_id TEXT NOT NULL,
        occurred_at TEXT NOT NULL, description TEXT, user_id TEXT, FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id),
        FOREIGN KEY(user_id) REFERENCES users(id), UNIQUE(source_type, source_id, cashbox_id)
      )''',
      '''CREATE TABLE IF NOT EXISTS payments (
        id TEXT PRIMARY KEY, document_no TEXT NOT NULL UNIQUE, payment_type TEXT NOT NULL, party_type TEXT NOT NULL,
        customer_id TEXT, supplier_id TEXT, cashbox_id TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
        currency_code TEXT NOT NULL DEFAULT 'YER', rate_ppm INTEGER NOT NULL DEFAULT 1000000, payment_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'posted', notes TEXT, original_payment_id TEXT, created_by TEXT, created_at TEXT NOT NULL,
        FOREIGN KEY(customer_id) REFERENCES customers(id), FOREIGN KEY(supplier_id) REFERENCES suppliers(id),
        FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id), FOREIGN KEY(original_payment_id) REFERENCES payments(id),
        FOREIGN KEY(created_by) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS expenses (
        id TEXT PRIMARY KEY, document_no TEXT NOT NULL UNIQUE, category TEXT NOT NULL, expense_date TEXT NOT NULL,
        cashbox_id TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor > 0), currency_code TEXT NOT NULL DEFAULT 'YER',
        rate_ppm INTEGER NOT NULL DEFAULT 1000000, payee TEXT, description TEXT, status TEXT NOT NULL DEFAULT 'draft',
        attachment_path TEXT, created_by TEXT, posted_at TEXT, FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id), FOREIGN KEY(created_by) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS other_incomes (
        id TEXT PRIMARY KEY, document_no TEXT NOT NULL UNIQUE, category TEXT NOT NULL, income_date TEXT NOT NULL,
        cashbox_id TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor > 0), currency_code TEXT NOT NULL DEFAULT 'YER',
        rate_ppm INTEGER NOT NULL DEFAULT 1000000, payer TEXT, description TEXT, status TEXT NOT NULL DEFAULT 'draft',
        attachment_path TEXT, created_by TEXT, posted_at TEXT, FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id), FOREIGN KEY(created_by) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS shifts (
        id TEXT PRIMARY KEY, cashbox_id TEXT NOT NULL, user_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open',
        opened_at TEXT NOT NULL, closed_at TEXT, opening_balance_minor INTEGER NOT NULL DEFAULT 0,
        expected_balance_minor INTEGER, actual_balance_minor INTEGER, difference_minor INTEGER,
        FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id), FOREIGN KEY(user_id) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS attachments (
        id TEXT PRIMARY KEY, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, local_path TEXT NOT NULL,
        mime_type TEXT, created_at TEXT NOT NULL, created_by TEXT, FOREIGN KEY(created_by) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS document_sequences (
        id TEXT PRIMARY KEY, branch_id TEXT, document_type TEXT NOT NULL, prefix TEXT NOT NULL, next_value INTEGER NOT NULL DEFAULT 1,
        UNIQUE(branch_id, document_type), FOREIGN KEY(branch_id) REFERENCES branches(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS licenses (
        id TEXT PRIMARY KEY, license_json TEXT NOT NULL, signature_base64 TEXT NOT NULL, status TEXT NOT NULL,
        installed_at TEXT NOT NULL, last_trusted_at TEXT, trial_invoice_limit INTEGER, trial_days INTEGER
      )''',
      '''CREATE TABLE IF NOT EXISTS backup_records (
        id TEXT PRIMARY KEY, local_path TEXT NOT NULL, checksum TEXT NOT NULL, schema_version INTEGER NOT NULL,
        encrypted INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, created_by TEXT, size_bytes INTEGER NOT NULL,
        FOREIGN KEY(created_by) REFERENCES users(id)
      )''',
      'CREATE INDEX IF NOT EXISTS idx_products_search ON products(name_ar, sku, barcode)',
      'CREATE INDEX IF NOT EXISTS idx_sales_date_status ON sales_invoices(invoice_date, status, branch_id)',
      'CREATE INDEX IF NOT EXISTS idx_purchase_date_status ON purchase_invoices(invoice_date, status, branch_id)',
      'CREATE INDEX IF NOT EXISTS idx_inventory_product_warehouse ON inventory_balances(product_id, warehouse_id)',
      'CREATE INDEX IF NOT EXISTS idx_inventory_movement_source ON inventory_movements(source_type, source_id)',
      'CREATE INDEX IF NOT EXISTS idx_stock_count_status ON stock_counts(warehouse_id, status, created_at)',
      'CREATE INDEX IF NOT EXISTS idx_journal_source ON journal_entries(source_type, source_id)',
      'CREATE INDEX IF NOT EXISTS idx_journal_date_status ON journal_entries(entry_date, status)',
      'CREATE INDEX IF NOT EXISTS idx_cash_movement_date ON cash_movements(cashbox_id, occurred_at)',
      'CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id)',
      '''CREATE TABLE IF NOT EXISTS cost_centers (
        id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name_ar TEXT NOT NULL, name_en TEXT, parent_id TEXT,
        active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL,
        FOREIGN KEY(parent_id) REFERENCES cost_centers(id) ON DELETE RESTRICT
      )''',
      '''CREATE TABLE IF NOT EXISTS fixed_assets (
        id TEXT PRIMARY KEY, asset_no TEXT NOT NULL UNIQUE, name_ar TEXT NOT NULL, category TEXT NOT NULL,
        purchase_date TEXT NOT NULL, acquisition_cost_minor INTEGER NOT NULL CHECK(acquisition_cost_minor >= 0),
        residual_value_minor INTEGER NOT NULL DEFAULT 0, useful_life_months INTEGER NOT NULL CHECK(useful_life_months > 0),
        accumulated_depreciation_minor INTEGER NOT NULL DEFAULT 0, currency_code TEXT NOT NULL DEFAULT 'YER',
        rate_ppm INTEGER NOT NULL DEFAULT 1000000, status TEXT NOT NULL DEFAULT 'active', cost_center_id TEXT,
        account_id TEXT, created_at TEXT NOT NULL, FOREIGN KEY(cost_center_id) REFERENCES cost_centers(id),
        FOREIGN KEY(account_id) REFERENCES accounts(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS asset_depreciation (
        id TEXT PRIMARY KEY, asset_id TEXT NOT NULL, period_start TEXT NOT NULL, period_end TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK(amount_minor > 0), journal_entry_id TEXT, status TEXT NOT NULL DEFAULT 'posted',
        created_at TEXT NOT NULL, UNIQUE(asset_id, period_start, period_end), FOREIGN KEY(asset_id) REFERENCES fixed_assets(id) ON DELETE RESTRICT,
        FOREIGN KEY(journal_entry_id) REFERENCES journal_entries(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS cheques (
        id TEXT PRIMARY KEY, cheque_no TEXT NOT NULL, bank_name TEXT, party_type TEXT NOT NULL,
        customer_id TEXT, supplier_id TEXT, amount_minor INTEGER NOT NULL CHECK(amount_minor > 0), currency_code TEXT NOT NULL DEFAULT 'YER',
        rate_ppm INTEGER NOT NULL DEFAULT 1000000, due_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
        cashbox_id TEXT, source_id TEXT, notes TEXT, created_at TEXT NOT NULL, UNIQUE(cheque_no, bank_name),
        FOREIGN KEY(customer_id) REFERENCES customers(id), FOREIGN KEY(supplier_id) REFERENCES suppliers(id), FOREIGN KEY(cashbox_id) REFERENCES cashboxes(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS local_notifications (
        id TEXT PRIMARY KEY, notification_type TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL,
        scheduled_at TEXT NOT NULL, entity_type TEXT, entity_id TEXT, read_at TEXT, created_at TEXT NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS import_batches (
        id TEXT PRIMARY KEY, file_name TEXT NOT NULL, file_hash TEXT NOT NULL UNIQUE, entity_type TEXT NOT NULL,
        rows_total INTEGER NOT NULL, rows_valid INTEGER NOT NULL DEFAULT 0, rows_rejected INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'preview', created_by TEXT, created_at TEXT NOT NULL, FOREIGN KEY(created_by) REFERENCES users(id)
      )''',
      '''CREATE TABLE IF NOT EXISTS saved_filters (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, screen_key TEXT NOT NULL, name TEXT NOT NULL,
        filter_json TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(user_id, screen_key, name), FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )''',
    ];
    final batch = db.batch();
    for (final statement in schema) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _createFinancialOperationsSchema(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS cost_centers (id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name_ar TEXT NOT NULL, name_en TEXT, parent_id TEXT, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, FOREIGN KEY(parent_id) REFERENCES cost_centers(id) ON DELETE RESTRICT)');
    await db.execute('CREATE TABLE IF NOT EXISTS fixed_assets (id TEXT PRIMARY KEY, asset_no TEXT NOT NULL UNIQUE, name_ar TEXT NOT NULL, category TEXT NOT NULL, purchase_date TEXT NOT NULL, acquisition_cost_minor INTEGER NOT NULL CHECK(acquisition_cost_minor >= 0), residual_value_minor INTEGER NOT NULL DEFAULT 0, useful_life_months INTEGER NOT NULL CHECK(useful_life_months > 0), accumulated_depreciation_minor INTEGER NOT NULL DEFAULT 0, currency_code TEXT NOT NULL DEFAULT \'YER\', rate_ppm INTEGER NOT NULL DEFAULT 1000000, status TEXT NOT NULL DEFAULT \'active\', cost_center_id TEXT, account_id TEXT, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS asset_depreciation (id TEXT PRIMARY KEY, asset_id TEXT NOT NULL, period_start TEXT NOT NULL, period_end TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor > 0), journal_entry_id TEXT, status TEXT NOT NULL DEFAULT \'posted\', created_at TEXT NOT NULL, UNIQUE(asset_id, period_start, period_end))');
    await db.execute('CREATE TABLE IF NOT EXISTS cheques (id TEXT PRIMARY KEY, cheque_no TEXT NOT NULL, bank_name TEXT, party_type TEXT NOT NULL, customer_id TEXT, supplier_id TEXT, amount_minor INTEGER NOT NULL CHECK(amount_minor > 0), currency_code TEXT NOT NULL DEFAULT \'YER\', rate_ppm INTEGER NOT NULL DEFAULT 1000000, due_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'pending\', cashbox_id TEXT, source_id TEXT, notes TEXT, created_at TEXT NOT NULL, UNIQUE(cheque_no, bank_name))');
    await db.execute('CREATE TABLE IF NOT EXISTS local_notifications (id TEXT PRIMARY KEY, notification_type TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, scheduled_at TEXT NOT NULL, entity_type TEXT, entity_id TEXT, read_at TEXT, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS import_batches (id TEXT PRIMARY KEY, file_name TEXT NOT NULL, file_hash TEXT NOT NULL UNIQUE, entity_type TEXT NOT NULL, rows_total INTEGER NOT NULL, rows_valid INTEGER NOT NULL DEFAULT 0, rows_rejected INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT \'preview\', created_by TEXT, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS saved_filters (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, screen_key TEXT NOT NULL, name TEXT NOT NULL, filter_json TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(user_id, screen_key, name))');
  }

  static Future<void> _seedReferenceData(DatabaseExecutor db) async {
    const roles = <Map<String, Object>>[
      {
        'id': 'role-system-admin',
        'code': 'system_admin',
        'name_ar': 'مدير النظام',
        'name_en': 'System Administrator',
      },
      {
        'id': 'role-general-manager',
        'code': 'general_manager',
        'name_ar': 'المدير العام',
        'name_en': 'General Manager',
      },
      {
        'id': 'role-accountant',
        'code': 'accountant',
        'name_ar': 'المحاسب',
        'name_en': 'Accountant',
      },
      {
        'id': 'role-cashier',
        'code': 'cashier',
        'name_ar': 'أمين الصندوق',
        'name_en': 'Cashier',
      },
      {
        'id': 'role-sales',
        'code': 'sales_officer',
        'name_ar': 'مسؤول المبيعات',
        'name_en': 'Sales Officer',
      },
      {
        'id': 'role-purchases',
        'code': 'purchase_officer',
        'name_ar': 'مسؤول المشتريات',
        'name_en': 'Purchase Officer',
      },
      {
        'id': 'role-warehouse',
        'code': 'warehouse_keeper',
        'name_ar': 'أمين المخزن',
        'name_en': 'Warehouse Keeper',
      },
      {
        'id': 'role-readonly',
        'code': 'read_only',
        'name_ar': 'قراءة فقط',
        'name_en': 'Read Only',
      },
    ];
    const currencies = <Map<String, Object>>[
      {
        'code': 'YER',
        'name_ar': 'الريال اليمني',
        'name_en': 'Yemeni Rial',
        'symbol': 'ر.ي',
        'decimals': 0,
      },
      {
        'code': 'SAR',
        'name_ar': 'الريال السعودي',
        'name_en': 'Saudi Riyal',
        'symbol': 'ر.س',
        'decimals': 2,
      },
      {
        'code': 'USD',
        'name_ar': 'الدولار الأمريكي',
        'name_en': 'US Dollar',
        'symbol': r'$',
        'decimals': 2,
      },
    ];
    const units = <Map<String, Object>>[
      {
        'id': 'unit-piece',
        'code': 'PCS',
        'name_ar': 'حبة',
        'name_en': 'Piece',
        'precision_digits': 0,
      },
      {
        'id': 'unit-carton',
        'code': 'CTN',
        'name_ar': 'كرتون',
        'name_en': 'Carton',
        'precision_digits': 0,
      },
      {
        'id': 'unit-pack',
        'code': 'PKT',
        'name_ar': 'باكت',
        'name_en': 'Pack',
        'precision_digits': 0,
      },
      {
        'id': 'unit-kg',
        'code': 'KG',
        'name_ar': 'كيلو',
        'name_en': 'Kilogram',
        'precision_digits': 3,
      },
      {
        'id': 'unit-litre',
        'code': 'LTR',
        'name_ar': 'لتر',
        'name_en': 'Litre',
        'precision_digits': 3,
      },
    ];
    const accounts = <Map<String, Object>>[
      {
        'id': 'acc-cash',
        'code': '1101',
        'name_ar': 'الصناديق والنقدية',
        'account_type': 'asset',
        'is_control': 1,
      },
      {
        'id': 'acc-ar',
        'code': '1102',
        'name_ar': 'العملاء',
        'account_type': 'asset',
        'is_control': 1,
      },
      {
        'id': 'acc-inventory',
        'code': '1103',
        'name_ar': 'المخزون',
        'account_type': 'asset',
        'is_control': 1,
      },
      {
        'id': 'acc-ap',
        'code': '2101',
        'name_ar': 'الموردون',
        'account_type': 'liability',
        'is_control': 1,
      },
      {
        'id': 'acc-tax',
        'code': '2102',
        'name_ar': 'ضريبة مستحقة',
        'account_type': 'liability',
        'is_control': 0,
      },
      {
        'id': 'acc-sales',
        'code': '4101',
        'name_ar': 'إيرادات المبيعات',
        'account_type': 'revenue',
        'is_control': 0,
      },
      {
        'id': 'acc-other-income',
        'code': '4102',
        'name_ar': 'إيرادات أخرى',
        'account_type': 'revenue',
        'is_control': 0,
      },
      {
        'id': 'acc-cogs',
        'code': '5101',
        'name_ar': 'تكلفة البضاعة المباعة',
        'account_type': 'expense',
        'is_control': 0,
      },
      {
        'id': 'acc-inventory-loss',
        'code': '5103',
        'name_ar': 'عجز وتسويات المخزون',
        'account_type': 'expense',
        'is_control': 0,
      },
      {
        'id': 'acc-inventory-gain',
        'code': '4103',
        'name_ar': 'فائض وتسويات المخزون',
        'account_type': 'revenue',
        'is_control': 0,
      },
      {
        'id': 'acc-expense',
        'code': '5102',
        'name_ar': 'مصروفات تشغيلية',
        'account_type': 'expense',
        'is_control': 0,
      },
    ];
    final batch = db.batch();
    for (final role in roles) {
      batch.insert('roles', {
        ...role,
        'system_role': 1,
        'active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final permission in Permissions.all) {
      batch.insert('permissions', {
        'code': permission,
        'name_ar': permission,
        'module': permission.split('.').first,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final role in roles) {
      final codes =
          Permissions.rolePermissions[role['code']] ?? const <String>{};
      for (final permission in codes) {
        batch.insert('role_permissions', {
          'role_id': role['id'],
          'permission_code': permission,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    for (final currency in currencies) {
      batch.insert('currencies', {
        ...currency,
        'active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final unit in units) {
      batch.insert('units', {
        ...unit,
        'active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final account in accounts) {
      batch.insert('accounts', {
        ...account,
        'active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<bool> get isConfigured async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM organizations',
    );
    return (result.first['count'] as int) > 0;
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      _db.transaction(action);

  Future<String> newId() async => _uuid.v4();

  Future<String> nextDocumentNumber(
    Transaction txn, {
    required String documentType,
    required String? branchId,
    String? prefix,
  }) async {
    final rows = await txn.query(
      'document_sequences',
      where: 'branch_id IS ? AND document_type = ?',
      whereArgs: [branchId, documentType],
      limit: 1,
    );
    final effectivePrefix = prefix ?? documentType.toUpperCase();
    if (rows.isEmpty) {
      final id = _uuid.v4();
      await txn.insert('document_sequences', {
        'id': id,
        'branch_id': branchId,
        'document_type': documentType,
        'prefix': effectivePrefix,
        'next_value': 2,
      });
      return '$effectivePrefix-000001';
    }
    final row = rows.first;
    final next = row['next_value'] as int;
    final savedPrefix = row['prefix'] as String;
    await txn.update(
      'document_sequences',
      {'next_value': next + 1},
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    return '$savedPrefix-${next.toString().padLeft(6, '0')}';
  }

  Future<void> audit(
    DatabaseExecutor executor, {
    String? userId,
    required String action,
    required String entityType,
    required String entityId,
    String? beforeJson,
    String? afterJson,
  }) async {
    await executor.insert('audit_logs', {
      'id': _uuid.v4(),
      'user_id': userId,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'before_json': beforeJson,
      'after_json': afterJson,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> close() => _db.close();
}
