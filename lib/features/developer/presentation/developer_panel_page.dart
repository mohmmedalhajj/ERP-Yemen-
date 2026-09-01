import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/license_service.dart';
import '../../../core/services/providers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/company_logo.dart';
import '../../../shared/widgets/erp_ui.dart';

class DeveloperPanelPage extends ConsumerStatefulWidget {
  const DeveloperPanelPage({super.key});

  @override
  ConsumerState<DeveloperPanelPage> createState() => _DeveloperPanelPageState();
}

class _DeveloperPanelPageState extends ConsumerState<DeveloperPanelPage> {
  late Future<_DeveloperPanelData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_DeveloperPanelData> _load() async {
    final license = ref.read(licenseServiceProvider);
    final database = ref.read(databaseProvider);
    final results = await Future.wait([
      license.currentStatus(),
      database.raw.query(
        'audit_logs',
        where: "action LIKE 'developer.%' OR action LIKE 'license.%'",
        orderBy: 'created_at DESC',
        limit: 40,
      ),
    ]);
    return _DeveloperPanelData(
      status: results[0] as LicenseStatus,
      auditRows: results[1] as List<Map<String, Object?>>,
    );
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _createLicenseDialog() async {
    final customer = TextEditingController();
    final phone = TextEditingController();
    final customerId = TextEditingController();
    final duration = TextEditingController(text: '365');
    final privateKey = TextEditingController();
    final notes = TextEditingController();
    var busy = false;
    String? generated;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('إنشاء ترخيص للمستخدم'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (generated == null) ...[
                    TextField(controller: customer, decoration: const InputDecoration(labelText: 'اسم العميل *')),
                    const SizedBox(height: 8),
                    TextField(controller: phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                    const SizedBox(height: 8),
                    TextField(controller: customerId, decoration: const InputDecoration(labelText: 'معرف العميل')),
                    const SizedBox(height: 8),
                    TextField(controller: duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مدة الترخيص بالأيام *')),
                    const SizedBox(height: 8),
                    TextField(controller: privateKey, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'مفتاح Ed25519 الخاص (Base64) *', helperText: 'يُستخدم في الذاكرة فقط ولا يُحفظ داخل التطبيق')),
                    const SizedBox(height: 8),
                    TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات')),
                  ] else ...[
                    const Text('تم إنشاء كود موقّع. انسخه أو شاركه مع المستخدم.'),
                    const SizedBox(height: 12),
                    SelectableText(generated!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('إغلاق')),
            if (generated != null) ...[
              OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: generated!)); if (dialogContext.mounted) showAppMessage(dialogContext, 'تم نسخ كود الترخيص.'); }, icon: const Icon(Icons.copy_outlined), label: const Text('نسخ')),
              FilledButton.icon(onPressed: () => SharePlus.instance.share(ShareParams(text: generated!, subject: 'كود تفعيل ERP Yemen')), icon: const Icon(Icons.share_outlined), label: const Text('مشاركة')),
            ] else
              FilledButton(
                onPressed: busy ? null : () async {
                  setState(() => busy = true);
                  try {
                    generated = await ref.read(licenseServiceProvider).createLicenseCode(
                      privateKeyBase64: privateKey.text,
                      customerName: customer.text,
                      phone: phone.text,
                      customerId: customerId.text,
                      durationDays: int.parse(duration.text),
                      notes: notes.text,
                    );
                    setState(() {});
                  } catch (error) {
                    if (dialogContext.mounted) showAppMessage(dialogContext, error.toString().replaceFirst('Bad state: ', ''), error: true);
                  } finally {
                    if (dialogContext.mounted) setState(() => busy = false);
                  }
                },
                child: Text(busy ? 'جارٍ الإنشاء...' : 'إنشاء كود موقّع'),
              ),
          ],
        ),
      ),
    );
    customer.dispose();
    phone.dispose();
    customerId.dispose();
    duration.dispose();
    privateKey.dispose();
    notes.dispose();
  }

  Future<void> _deactivate() async {
    final confirmed = await showErpConfirmation(
      context,
      title: 'إيقاف الترخيص المحلي',
      message:
          'سيمنع هذا العمليات المدفوعة الجديدة على هذا التثبيت فقط، ولن يحذف بيانات العميل.',
      confirmLabel: 'إيقاف الترخيص',
    );
    if (!confirmed) return;
    try {
      await ref.read(licenseServiceProvider).deactivateCurrent();
      _reload();
      if (mounted)
        showAppMessage(context, 'تم إيقاف الترخيص المحلي وتسجيل الإجراء.');
    } catch (error) {
      if (mounted) {
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
      }
    }
  }

  int _strength(String value) {
    var score = 0;
    if (value.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(value)) score++;
    if (RegExp(r'[a-z]').hasMatch(value)) score++;
    if (RegExp(r'[0-9]').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return score;
  }

  Future<void> _changeDeveloperPassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    var saving = false;
    var score = 0;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تغيير كلمة مرور المطور'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: current,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الحالية',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: next,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (value) =>
                      setDialogState(() => score = _strength(value)),
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الجديدة',
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: score / 5),
                const SizedBox(height: 10),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور الجديدة',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (next.text != confirm.text || score < 3) {
                        showAppMessage(
                          context,
                          'تأكد من التطابق وقوة كلمة المرور.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await ref
                            .read(developerAccessServiceProvider)
                            .changePassword(
                              currentPassword: current.text,
                              newPassword: next.text,
                            );
                        if (context.mounted) Navigator.pop(dialogContext);
                        if (mounted)
                          showAppMessage(
                            this.context,
                            'تم تغيير كلمة مرور المطور.',
                          );
                      } catch (error) {
                        if (mounted) {
                          showAppMessage(
                            this.context,
                            error.toString().replaceFirst('Bad state: ', ''),
                            error: true,
                          );
                        }
                      } finally {
                        if (context.mounted)
                          setDialogState(() => saving = false);
                      }
                    },
              child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ'),
            ),
          ],
        ),
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('لوحة إدارة الترخيص'),
      actions: [
        IconButton(
          onPressed: _reload,
          tooltip: 'تحديث',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<_DeveloperPanelData>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final payload = data.status.payload ?? const <String, dynamic>{};
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const CompanyLogo(size: 52, radius: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'إدارة التراخيص والتثبيت المحلي',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ErpSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'حالة الترخيص: ${data.status.state}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(data.status.message),
                  const SizedBox(height: 12),
                  _detailsTable([
                    ('العميل', '${payload['customer_name'] ?? 'غير مفعل'}'),
                    ('رقم الترخيص', '${payload['license_id'] ?? '—'}'),
                    ('الباقة', '${payload['package_name'] ?? '—'}'),
                    (
                      'الميزات',
                      (payload['features'] as List?)?.join('، ') ?? '—',
                    ),
                    ('البداية', '${payload['starts_at'] ?? '—'}'),
                    ('الانتهاء', '${payload['expires_at'] ?? 'دائم'}'),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _createLicenseDialog,
                        icon: const Icon(Icons.add_moderator_outlined),
                        label: const Text('إنشاء ترخيص للمستخدم'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _changeDeveloperPassword,
                        icon: const Icon(Icons.password_outlined),
                        label: const Text('تغيير كلمة مرور المطور'),
                      ),
                      if (data.status.state == 'active')
                        FilledButton.tonalIcon(
                          onPressed: _deactivate,
                          icon: const Icon(Icons.block_outlined),
                          label: const Text('إيقاف الترخيص المحلي'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'سجل محاولات الوصول والتفعيل',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (data.auditRows.isEmpty)
              const ErpSectionCard(child: Text('لا توجد محاولات مسجلة بعد.'))
            else
              ErpSectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: data.auditRows
                      .map(
                        (row) => ListTile(
                          dense: true,
                          leading: Icon(
                            '${row['action']}'.contains('denied') ||
                                    '${row['action']}'.contains('failed')
                                ? Icons.error_outline
                                : Icons.verified_outlined,
                          ),
                          title: Text('${row['action']}'),
                          subtitle: Text('${row['created_at']}'),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _detailsTable(List<(String, String)> values) => Table(
    columnWidths: const {0: IntrinsicColumnWidth()},
    children: values
        .map(
          (value) => TableRow(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: 12,
                  top: 4,
                  bottom: 4,
                ),
                child: Text(
                  value.$1,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SelectableText(value.$2),
              ),
            ],
          ),
        )
        .toList(),
  );
}

class _DeveloperPanelData {
  const _DeveloperPanelData({
    required this.status,
    required this.auditRows,
  });

  final LicenseStatus status;
  final List<Map<String, Object?>> auditRows;
}
