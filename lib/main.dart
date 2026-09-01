import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/erp_database.dart';
import 'core/localization/app_strings.dart';
import 'core/services/providers.dart';
import 'core/services/backup_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/accounting/presentation/accounting_page.dart';
import 'features/administration/presentation/administration_page.dart';
import 'features/auth/presentation/auth_pages.dart';
import 'features/cash/presentation/cash_page.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/finance/presentation/finance_operations_page.dart';
import 'features/masters/presentation/master_pages.dart';
import 'features/inventory/presentation/inventory_operations_pages.dart';
import 'features/reports/presentation/reports_page.dart';
import 'features/returns/presentation/returns_page.dart';
import 'features/sales/presentation/transaction_page.dart';
import 'features/settings/presentation/settings_page.dart';
import 'features/settings/presentation/reference_data_page.dart';
import 'shared/widgets/app_scaffold.dart';
import 'shared/widgets/erp_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await ErpDatabase.open();
  final autoBackup = AutoBackupCoordinator(BackupService(database));
  await autoBackup.start();
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const ErpMaterialApp(),
    ),
  );
}

class ErpMaterialApp extends ConsumerWidget {
  const ErpMaterialApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'نظام المبيعات والمشتريات والإدارة المتكاملة',
    locale: ref.watch(localeProvider),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ref.watch(themeModeProvider),
    home: const AppGate(),
  );
}

class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  late Future<bool> _configured;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configured = ref.read(databaseProvider).isConfigured;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (ref.read(sessionProvider) != null) {
        _backgroundedAt = DateTime.now().toUtc();
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final leftAt = _backgroundedAt;
      _backgroundedAt = null;
      if (leftAt == null ||
          DateTime.now().toUtc().difference(leftAt) <
              const Duration(seconds: 60)) {
        return;
      }
      final user = ref.read(sessionProvider);
      if (user != null) {
        unawaited(ref.read(authRepositoryProvider).logout(user.id));
        ref.read(sessionProvider.notifier).state = null;
      }
    }
  }

  void _reloadConfiguration() =>
      setState(() => _configured = ref.read(databaseProvider).isConfigured);

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _configured,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Text('${context.tr('error')}: ${snapshot.error}'),
          ),
        );
      }
      if (snapshot.data != true) {
        return SetupPage(onConfigured: _reloadConfiguration);
      }
      final session = ref.watch(sessionProvider);
      if (session == null) {
        return LoginPage(
          onAuthenticated: (user) =>
              ref.read(sessionProvider.notifier).state = user,
        );
      }
      return const ErpShell();
    },
  );
}

class ErpShell extends ConsumerStatefulWidget {
  const ErpShell({super.key});

  @override
  ConsumerState<ErpShell> createState() => _ErpShellState();
}

class _ErpShellState extends ConsumerState<ErpShell> {
  String _active = 'dashboard';
  final List<String> _history = ['dashboard'];
  final Map<String, Widget> _pageCache = {};

  Widget _pageFor(String key) => _pageCache.putIfAbsent(
    key,
    () => switch (key) {
      'dashboard' => const DashboardPage(),
      'sales' => const TransactionPage(kind: 'sale'),
      'salesReturns' => const ReturnsPage(kind: 'sale'),
      'purchases' => const TransactionPage(kind: 'purchase'),
      'purchaseReturns' => const ReturnsPage(kind: 'purchase'),
      'inventory' => const MasterPage(type: 'products'),
      'referenceData' => const ReferenceDataPage(),
      'stockTransfers' => const StockTransfersPage(),
      'stockCount' => const StockCountsPage(),
      'customers' => const MasterPage(type: 'customers'),
      'suppliers' => const MasterPage(type: 'suppliers'),
      'cash' => const CashPage(),
      'expensesIncome' => const FinanceOperationsPage(),
      'accounting' => const AccountingPage(),
      'reports' => const ReportsPage(),
      'users' => const AdministrationPage(),
      _ => const SettingsPage(),
    },
  );

  void _navigate(String target) {
    if (target == _active) return;
    setState(() {
      final knownIndex = _history.indexOf(target);
      if (knownIndex >= 0) {
        _history.removeRange(knownIndex + 1, _history.length);
      } else {
        _history.add(target);
      }
      _active = target;
    });
  }

  Future<void> _handleSystemBack() async {
    if (_history.length > 1) {
      setState(() {
        _history.removeLast();
        _active = _history.last;
      });
      return;
    }
    final exit = await showErpConfirmation(
      context,
      title: 'الخروج من التطبيق',
      message: 'هل تريد الخروج من التطبيق؟',
      confirmLabel: 'خروج',
    );
    if (exit && mounted) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_handleSystemBack());
    },
    child: AppScaffold(
      titleKey: _active,
      active: _active,
      onNavigate: _navigate,
      onLogout: () async {
        final user = ref.read(sessionProvider);
        if (user != null) {
          await ref.read(authRepositoryProvider).logout(user.id);
        }
        ref.read(sessionProvider.notifier).state = null;
      },
      child: _pageFor(_active),
    ),
  );
}
