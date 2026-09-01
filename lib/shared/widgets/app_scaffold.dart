import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/localization/app_strings.dart';
import '../../core/services/providers.dart';
import 'company_logo.dart';
import 'erp_ui.dart';

class AppScaffold extends ConsumerWidget {
  const AppScaffold({
    super.key,
    required this.titleKey,
    required this.active,
    required this.child,
    required this.onNavigate,
    required this.onLogout,
  });

  final String titleKey;
  final String active;
  final Widget child;
  final ValueChanged<String> onNavigate;
  final VoidCallback onLogout;

  static const _groups =
      <({String title, List<({String key, IconData icon})> items})>[
        (
          title: 'الرئيسية',
          items: [(key: 'dashboard', icon: Icons.dashboard_outlined)],
        ),
        (
          title: 'التجارة',
          items: [
            (key: 'sales', icon: Icons.point_of_sale_outlined),
            (key: 'salesReturns', icon: Icons.assignment_return_outlined),
            (key: 'purchases', icon: Icons.shopping_cart_outlined),
            (key: 'purchaseReturns', icon: Icons.keyboard_return_outlined),
          ],
        ),
        (
          title: 'المخزون والأطراف',
          items: [
            (key: 'inventory', icon: Icons.inventory_2_outlined),
            (key: 'referenceData', icon: Icons.category_outlined),
            (key: 'stockTransfers', icon: Icons.swap_horiz_outlined),
            (key: 'stockCount', icon: Icons.fact_check_outlined),
            (key: 'customers', icon: Icons.people_outline),
            (key: 'suppliers', icon: Icons.local_shipping_outlined),
          ],
        ),
        (
          title: 'المالية',
          items: [
            (key: 'cash', icon: Icons.account_balance_wallet_outlined),
            (key: 'expensesIncome', icon: Icons.receipt_long_outlined),
            (key: 'accounting', icon: Icons.account_tree_outlined),
          ],
        ),
        (
          title: 'الإدارة',
          items: [
            (key: 'reports', icon: Icons.assessment_outlined),
            (key: 'users', icon: Icons.admin_panel_settings_outlined),
            (key: 'settings', icon: Icons.settings_outlined),
          ],
        ),
      ];

  Future<void> _showAbout(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: context.tr('appName'),
      applicationVersion: '${info.version} (${info.buildNumber})',
      applicationLegalese: context.tr('company'),
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset('assets/app_icon_master.png', width: 52, height: 52),
      ),
      children: const [
        Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'نظام محلي متكامل للمبيعات والمشتريات والمخزون والحسابات.',
          ),
        ),
      ],
    );
  }

  Future<void> _showNotifications(BuildContext context, WidgetRef ref) async {
    final service = ref.read(inventoryAlertServiceProvider);
    await service.refresh();
    final rows = await service.unread();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('التنبيهات'),
        content: SizedBox(
          width: 460,
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد تنبيهات جديدة.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final row = rows[index];
                    return ListTile(
                      leading: Icon(
                        row['notification_type'] == 'expiry'
                            ? Icons.event_busy_outlined
                            : Icons.inventory_2_outlined,
                      ),
                      title: Text(row['title'] as String),
                      subtitle: Text(row['body'] as String),
                      onTap: () {
                        service.markRead(row['id'] as String);
                        Navigator.pop(dialogContext);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(organizationProfileProvider);
    final profile = switch (profileState) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final organizationName = profile?.nameAr ?? context.tr('shortName');
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CompanyLogo(logoPath: profile?.logoPath, size: 32, radius: 8),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '${context.tr(titleKey)} — $organizationName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined),
            tooltip: 'التنبيهات',
            onPressed: () => _showNotifications(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: context.tr('about'),
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      const Color(0xFF071D3A),
                    ],
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                  ),
                ),
                child: Row(
                  children: [
                    CompanyLogo(
                      logoPath: profile?.logoPath,
                      size: 54,
                      radius: 14,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            organizationName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.tr('company'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  children: [
                    for (final group in _groups) ...[
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          10,
                          12,
                          10,
                          4,
                        ),
                        child: Text(
                          group.title,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      for (final item in group.items)
                        ListTile(
                          selected: item.key == active,
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          leading: Icon(item.icon),
                          title: Text(context.tr(item.key)),
                          onTap: () {
                            Navigator.pop(context);
                            onNavigate(item.key);
                          },
                        ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(context.tr('logout')),
                onTap: () async {
                  final leave = await showErpConfirmation(
                    context,
                    title: 'تسجيل الخروج',
                    message: 'هل تريد تسجيل الخروج؟ ستحتاج إلى إدخال بياناتك للوصول مجدداً.',
                    confirmLabel: 'تسجيل الخروج',
                  );
                  if (leave) onLogout();
                },
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(child: child),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.action,
    this.icon = Icons.inbox_outlined,
  });
  final String message;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

void showAppMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      content: Text(message),
    ),
  );
}
