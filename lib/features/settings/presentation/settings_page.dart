import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/organization_profile_service.dart';
import '../../../core/services/providers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/company_logo.dart';
import '../../../shared/widgets/erp_ui.dart';
import 'reference_data_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final theme = ref.watch(themeModeProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ErpPageHeader(
          title: 'الإعدادات',
          subtitle: 'إدارة إعدادات المؤسسة والعمليات والنسخ والترخيص محلياً.',
        ),
        ErpSectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.business_outlined),
                title: const Text('بيانات المؤسسة وإعدادات العمليات'),
                subtitle: const Text(
                  'اسم المؤسسة ومنع الرصيد السالب ومهلة الجلسة.',
                ),
                onTap: _organizationSettingsDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('إدارة الفروع والمخازن والعملات والضرائب'),
                subtitle: const Text(
                  'إضافة وتعديل وتعطيل البيانات المرجعية والفترات المالية بصلاحيات محمية.',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReferenceDataPage()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('استعراض البيانات المرجعية والفترات'),
                subtitle: const Text(
                  'ملخص سريع للبيانات والفترات المالية الحالية.',
                ),
                onTap: _referenceOverview,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.language),
            title: Text(context.tr('language')),
            subtitle: Text(
              locale.languageCode == 'ar'
                  ? context.tr('arabic')
                  : context.tr('english'),
            ),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: locale.languageCode,
                items: [
                  DropdownMenuItem(
                    value: 'ar',
                    child: Text(context.tr('arabic')),
                  ),
                  DropdownMenuItem(
                    value: 'en',
                    child: Text(context.tr('english')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null)
                    ref.read(localeProvider.notifier).state = Locale(value);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.contrast_outlined),
            title: Text(context.tr('theme')),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<ThemeMode>(
                value: theme,
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('تلقائي'),
                  ),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('فاتح')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('داكن')),
                ],
                onChanged: (value) {
                  if (value != null)
                    ref.read(themeModeProvider.notifier).state = value;
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('تغيير كلمة مرور الحساب'),
            subtitle: const Text(
              'يتطلب كلمة المرور الحالية ثم يحفظ كلمة جديدة بتجزئة مملحة.',
            ),
            onTap: _changeCurrentPassword,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text(context.tr('backup')),
                subtitle: const Text(
                  'إنشاء ملف مشفر بكلمة مرور؛ لا تُرفع البيانات إلى الإنترنت.',
                ),
                enabled: !_working,
                onTap: _createBackup,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('استعادة نسخة احتياطية'),
                subtitle: const Text(
                  'يتحقق التطبيق من كلمة المرور وسلامة الملف قبل الاستبدال.',
                ),
                enabled: !_working,
                onTap: _restoreBackup,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(context.tr('license')),
                subtitle: FutureBuilder(
                  future: ref.watch(licenseServiceProvider).currentStatus(),
                  builder: (context, snapshot) => Text(
                    snapshot.hasData
                        ? snapshot.data!.message
                        : 'جارٍ التحقق من حالة الترخيص',
                  ),
                ),
                enabled: !_working,
                onTap: _licenseDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: const Text('التواصل مع دعم محمد الحاج سوفت'),
                subtitle: const Text(
                  '+967780961823 — اتصال أو WhatsApp مع فريق الدعم',
                ),
                onTap: _supportDialog,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(context.tr('about')),
            subtitle: Text(
              '${context.tr('shortName')}\n${context.tr('company')}',
            ),
            isThreeLine: true,
            onTap: () async {
              final info = await PackageInfo.fromPlatform();
              if (!context.mounted) return;
              showAboutDialog(
                context: context,
                applicationName: context.tr('appName'),
                applicationVersion: '${info.version} (${info.buildNumber})',
                applicationLegalese: context.tr('company'),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _organizationSettingsDialog() async {
    final profileService = ref.read(organizationProfileServiceProvider);
    final repository = ref.read(administrationRepositoryProvider);
    final profile = await profileService.current();
    final settings = await repository.settings();
    if (!mounted) return;
    if (profile == null) {
      showAppMessage(context, 'لا توجد مؤسسة مهيأة بعد.', error: true);
      return;
    }
    final name = TextEditingController(text: profile.nameAr);
    final nameEn = TextEditingController(text: profile.nameEn ?? '');
    final address = TextEditingController(text: profile.address ?? '');
    final phone = TextEditingController(text: profile.phones ?? '');
    final email = TextEditingController(text: profile.email ?? '');
    final taxNumber = TextEditingController(text: profile.taxNumber ?? '');
    final commercialRegister = TextEditingController(
      text: profile.commercialRegister ?? '',
    );
    final notes = TextEditingController(text: profile.notes ?? '');
    final timeout = TextEditingController(
      text: settings['session_timeout_minutes'] ?? '15',
    );
    var logoPath = profile.logoPath;
    var preventNegative = (settings['prevent_negative_stock'] ?? '1') == '1';
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('بيانات المؤسسة وإعدادات العمليات'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CompanyLogo(logoPath: logoPath, size: 78, radius: 16),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final selected = await FilePicker.platform
                                          .pickFiles(type: FileType.image);
                                      final source =
                                          selected?.files.single.path;
                                      if (source == null) return;
                                      try {
                                        final saved = await profileService
                                            .persistLogo(File(source));
                                        setDialogState(() => logoPath = saved);
                                      } catch (error) {
                                        if (mounted) {
                                          showAppMessage(
                                            this.context,
                                            error.toString().replaceFirst(
                                              'Bad state: ',
                                              '',
                                            ),
                                            error: true,
                                          );
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.upload_file_outlined),
                              label: Text(
                                logoPath == null
                                    ? 'اختيار الشعار'
                                    : 'تغيير الشعار',
                              ),
                            ),
                            if (logoPath != null)
                              TextButton.icon(
                                onPressed: saving
                                    ? null
                                    : () =>
                                          setDialogState(() => logoPath = null),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('استخدام الافتراضي'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'اسم المؤسسة بالعربية *',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameEn,
                    decoration: const InputDecoration(
                      labelText: 'اسم المؤسسة بالإنجليزية',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: address,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'الهواتف'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: taxNumber,
                          decoration: const InputDecoration(
                            labelText: 'الرقم الضريبي',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: commercialRegister,
                          decoration: const InputDecoration(
                            labelText: 'السجل التجاري',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات المؤسسة',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: preventNegative,
                    title: const Text('منع الرصيد السالب'),
                    subtitle: const Text(
                      'يرفض بيع أو إرسال صنف عندما لا يكفي الرصيد المتاح.',
                    ),
                    onChanged: saving
                        ? null
                        : (value) =>
                              setDialogState(() => preventNegative = value),
                  ),
                  TextField(
                    controller: timeout,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'مهلة الجلسة بالدقائق',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('تراجع'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final actor = ref.read(sessionProvider);
                      final minutes = int.tryParse(timeout.text.trim());
                      if (actor == null ||
                          name.text.trim().isEmpty ||
                          minutes == null ||
                          minutes < 1 ||
                          minutes > 1440) {
                        showAppMessage(
                          context,
                          'تحقق من اسم المؤسسة ومهلة الجلسة (من 1 إلى 1440 دقيقة).',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await profileService.save(
                          OrganizationProfile(
                            id: profile.id,
                            nameAr: name.text,
                            nameEn: nameEn.text,
                            address: address.text,
                            phones: phone.text,
                            email: email.text,
                            taxNumber: taxNumber.text,
                            commercialRegister: commercialRegister.text,
                            notes: notes.text,
                            logoPath: logoPath,
                          ),
                          actorUserId: actor.id,
                        );
                        await repository.saveSetting(
                          actor,
                          'prevent_negative_stock',
                          preventNegative ? '1' : '0',
                        );
                        await repository.saveSetting(
                          actor,
                          'session_timeout_minutes',
                          '$minutes',
                        );
                        ref.invalidate(organizationProfileProvider);
                        if (context.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          showAppMessage(
                            this.context,
                            'تم حفظ بيانات المؤسسة والشعار وإعدادات العمليات.',
                          );
                        }
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
    for (final controller in [
      name,
      nameEn,
      address,
      phone,
      email,
      taxNumber,
      commercialRegister,
      notes,
      timeout,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _referenceOverview() async {
    final repository = ref.read(administrationRepositoryProvider);
    final data = await Future.wait([
      repository.branches(),
      repository.warehouses(),
      repository.cashboxes(),
      repository.currencies(),
      repository.fiscalPeriods(),
    ]);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .72,
          minChildSize: .35,
          maxChildSize: .92,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'البيانات المرجعية والفترات',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _referenceSection('الفروع', data[0], 'name_ar'),
              _referenceSection('المخازن', data[1], 'name_ar'),
              _referenceSection('الصناديق', data[2], 'name_ar'),
              _referenceSection('العملات', data[3], 'code'),
              _referenceSection('الفترات المالية', data[4], 'name'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _referenceSection(
    String title,
    List<Map<String, Object?>> rows,
    String label,
  ) => ErpSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          const Text('لا توجد بيانات.')
        else
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('• ${row[label] ?? ''}'),
            ),
          ),
      ],
    ),
  );

  int _passwordStrength(String value) {
    var score = 0;
    if (value.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(value)) score++;
    if (RegExp(r'[a-z]').hasMatch(value)) score++;
    if (RegExp(r'[0-9]').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return score;
  }

  Future<void> _changeCurrentPassword() async {
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
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
          title: const Text('تغيير كلمة المرور'),
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
                      setDialogState(() => score = _passwordStrength(value)),
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الجديدة',
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: score / 5),
                const SizedBox(height: 4),
                Text(
                  score >= 4
                      ? 'قوية'
                      : score >= 3
                      ? 'متوسطة'
                      : 'ضعيفة — استخدم 10 أحرف تشمل أحرفاً كبيرة وصغيرة وأرقاماً ورمزاً',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
                          'تأكد من تطابق كلمة المرور وأنها متوسطة القوة على الأقل.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await ref
                            .read(authRepositoryProvider)
                            .changePassword(
                              userId: actor.id,
                              currentPassword: current.text,
                              newPassword: next.text,
                            );
                        if (context.mounted) Navigator.pop(dialogContext);
                        if (mounted)
                          showAppMessage(
                            this.context,
                            'تم تغيير كلمة المرور بنجاح.',
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
              child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ كلمة المرور'),
            ),
          ],
        ),
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
  }

  Future<String?> _passwordDialog(String title) async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (password.text.length < 8 || password.text != confirm.text) {
                showAppMessage(
                  context,
                  'تأكد من تطابق كلمة مرور لا تقل عن 8 أحرف',
                  error: true,
                );
                return;
              }
              Navigator.pop(context, password.text);
            },
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    password.dispose();
    confirm.dispose();
    return result;
  }

  Future<void> _createBackup() async {
    final password = await _passwordDialog('كلمة مرور النسخة الاحتياطية');
    if (password == null || !mounted) return;
    setState(() => _working = true);
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'اختر مجلد حفظ النسخة الاحتياطية',
      );
      final file = await ref
          .read(backupServiceProvider)
          .createEncryptedBackup(
            password: password,
            directory: path == null ? null : Directory(path),
          );
      if (!mounted) return;
      showAppMessage(context, 'تم إنشاء نسخة مشفرة: ${file.path}');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'نسخة احتياطية مشفرة للنظام المتكامل',
        ),
      );
    } catch (error) {
      if (mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreBackup() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['merp'],
    );
    if (selected?.files.single.path == null || !mounted) return;
    final password = await _passwordDialog('كلمة مرور النسخة المراد استعادتها');
    if (password == null || !mounted) return;
    setState(() => _working = true);
    try {
      final backup = File(selected!.files.single.path!);
      final manifest = await ref
          .read(backupServiceProvider)
          .inspectEncryptedBackup(backup, password);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تأكيد الاستعادة'),
          content: Text(
            'نسخة من ${manifest.createdAt}\nإصدار المخطط ${manifest.schemaVersion}\nسيُنشأ ملف أمان قبل الاستبدال.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('استعادة'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await ref
          .read(backupServiceProvider)
          .restoreEncryptedBackup(backup, password);
      if (mounted)
        showAppMessage(
          context,
          'تمت الاستعادة. أغلق التطبيق وافتحه مجدداً لإعادة فتح قاعدة البيانات.',
        );
    } catch (error) {
      if (mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _licenseDialog() async {
    final service = ref.read(licenseServiceProvider);
    final initialStatus = await service.currentStatus();
    if (!mounted) return;
    final code = TextEditingController();
    var status = initialStatus;
    var activating = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('license')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(status.message),
                  const SizedBox(height: 12),
                  if (status.payload != null) ...[
                    const Divider(),
                    Text('العميل: ${status.payload!['customer_name'] ?? '—'}'),
                    Text('الباقة: ${status.payload!['package_name'] ?? '—'}'),
                    Text(
                      'الميزات: ${(status.payload!['features'] as List?)?.join('، ') ?? '—'}',
                    ),
                    Text(
                      'الانتهاء: ${status.payload!['expires_at'] ?? 'دائم'}',
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: code,
                    minLines: 3,
                    maxLines: 6,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'كود التفعيل',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: activating ? null : () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
            OutlinedButton.icon(
              onPressed: activating
                  ? null
                  : () async {
                      final selected = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['merp', 'json', 'lic'],
                      );
                      final path = selected?.files.single.path;
                      if (path == null) return;
                      setDialogState(() => activating = true);
                      try {
                        final result = await service.install(File(path));
                        setDialogState(() => status = result);
                        if (mounted) setState(() {});
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
                          setDialogState(() => activating = false);
                      }
                    },
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('اختيار ملف'),
            ),
            FilledButton(
              onPressed: activating
                  ? null
                  : () async {
                      if (code.text.trim().isEmpty) {
                        showAppMessage(
                          context,
                          'أدخل كود التفعيل أو اختر ملف الترخيص.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => activating = true);
                      try {
                        final result = await service.installCode(code.text);
                        setDialogState(() => status = result);
                        if (mounted) setState(() {});
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
                          setDialogState(() => activating = false);
                      }
                    },
              child: Text(activating ? 'جارٍ التحقق...' : 'تفعيل'),
            ),
          ],
        ),
      ),
    );
    code.dispose();
  }

  Future<void> _supportDialog() async {
    if (!mounted) return;
    const number = '+967780961823';
    const message = 'طلب دعم ERP — أحتاج مساعدة في استخدام النظام أو تفعيل الترخيص.';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('دعم محمد الحاج سوفت'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'يمكنك التواصل مع فريق الدعم عبر الاتصال أو WhatsApp. لا يرسل التطبيق أي بيانات تقنية عن جهازك.',
            ),
            const SizedBox(height: 10),
            SelectableText('$number\n$message'),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message));
                if (mounted) showAppMessage(context, 'تم نسخ رسالة الدعم.');
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('نسخ رسالة الدعم'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
          OutlinedButton(
            onPressed: () async {
              final launched = await launchUrl(Uri.parse('tel:$number'));
              if (!launched && mounted)
                showAppMessage(context, 'تعذر فتح تطبيق الاتصال.', error: true);
            },
            child: const Text('اتصال'),
          ),
          FilledButton(
            onPressed: () async {
              final uri = Uri.https('wa.me', '/967780961823', {
                'text': message,
              });
              final launched = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
              if (!launched && mounted)
                showAppMessage(context, 'تعذر فتح WhatsApp.', error: true);
            },
            child: const Text('WhatsApp'),
          ),
        ],
      ),
    );
  }
}
