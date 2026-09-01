import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/services/providers.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../developer/presentation/developer_panel_page.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/company_logo.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, required this.onAuthenticated});
  final ValueChanged<AuthUser> onAuthenticated;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  final List<DateTime> _logoTapTimes = [];

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .login(_username.text, _password.text);
      if (user.mustChangePassword) {
        final changed = await _forcePasswordChange(user);
        if (!changed) return;
      }
      if (mounted) widget.onAuthenticated(user);
    } catch (error) {
      if (mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registerLogoTap() async {
    final now = DateTime.now();
    _logoTapTimes.removeWhere(
      (time) => now.difference(time) > const Duration(seconds: 3),
    );
    _logoTapTimes.add(now);
    if (_logoTapTimes.length < 5) return;
    _logoTapTimes.clear();
    final password = TextEditingController();
    var checking = false;
    final granted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          content: TextField(
            controller: password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            decoration: const InputDecoration(),
          ),
          actions: [
            TextButton(
              onPressed: checking
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: checking
                  ? null
                  : () async {
                      setDialogState(() => checking = true);
                      final valid = await ref
                          .read(developerAccessServiceProvider)
                          .verify(password.text);
                      if (context.mounted) {
                        Navigator.pop(dialogContext, valid);
                      }
                    },
              child: Text(checking ? 'جارٍ التحقق...' : 'متابعة'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    if (granted == true && mounted) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const DeveloperPanelPage()));
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

  Future<bool> _forcePasswordChange(AuthUser user) async {
    final next = TextEditingController();
    final confirm = TextEditingController();
    var score = 0;
    var saving = false;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('يلزم تغيير كلمة المرور'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'لأمان الحساب، اختر كلمة مرور جديدة متوسطة القوة على الأقل.',
                ),
                const SizedBox(height: 12),
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
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (next.text != confirm.text || score < 3) {
                        showAppMessage(
                          context,
                          'تأكد من التطابق ومن قوة كلمة المرور.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await ref
                            .read(authRepositoryProvider)
                            .changePassword(
                              userId: user.id,
                              currentPassword: _password.text,
                              newPassword: next.text,
                            );
                        if (context.mounted) Navigator.pop(dialogContext, true);
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
              child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ ومتابعة'),
            ),
          ],
        ),
      ),
    );
    next.dispose();
    confirm.dispose();
    return changed == true;
  }

  @override
  Widget build(BuildContext context) {
    final profile = switch (ref.watch(organizationProfileProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final organizationName = profile?.nameAr ?? context.tr('shortName');
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width > 600 ? 440 : double.infinity,
            ),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: GestureDetector(
                          onTap: _registerLogoTap,
                          child: CompanyLogo(
                            logoPath: profile?.logoPath,
                            size: 78,
                            radius: 18,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        organizationName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('company'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _username,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.tr('username'),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? context.tr('required')
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: context.tr('password'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? context.tr('required')
                            : null,
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(context.tr('login')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key, required this.onConfigured});
  final VoidCallback onConfigured;

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _form = GlobalKey<FormState>();
  final _organization = TextEditingController();
  final _branch = TextEditingController(text: 'الفرع الرئيسي');
  final _warehouse = TextEditingController(text: 'المخزن الرئيسي');
  final _cashbox = TextEditingController(text: 'الصندوق الرئيسي');
  final _adminName = TextEditingController();
  final _adminUsername = TextEditingController(text: 'admin');
  final _adminPassword = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    for (final controller in [
      _organization,
      _branch,
      _warehouse,
      _cashbox,
      _adminName,
      _adminUsername,
      _adminPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    final now = DateTime.now();
    try {
      await ref
          .read(authRepositoryProvider)
          .initialize(
            SetupInput(
              organizationName: _organization.text,
              branchName: _branch.text,
              warehouseName: _warehouse.text,
              cashboxName: _cashbox.text,
              adminName: _adminName.text,
              adminUsername: _adminUsername.text,
              adminPassword: _adminPassword.text,
              fiscalYearStart: DateTime(now.year, 1, 1),
              fiscalYearEnd: DateTime(now.year, 12, 31),
            ),
          );
      widget.onConfigured();
    } catch (error) {
      if (mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('setup'))),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: CompanyLogo(size: 82, radius: 18)),
            const SizedBox(height: 18),
            Text(
              'ابدأ بإنشاء بيانات مؤسستك وحساب المدير. جميع البيانات تبقى داخل الجهاز.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _field(_organization, context.tr('organizationName')),
            _field(_branch, context.tr('branchName')),
            _field(_warehouse, context.tr('warehouseName')),
            _field(_cashbox, context.tr('cashboxName')),
            const Divider(height: 32),
            _field(_adminName, context.tr('adminName')),
            _field(_adminUsername, context.tr('username')),
            _field(
              _adminPassword,
              context.tr('password'),
              obscure: true,
              extraValidator: (value) => value != null && value.length >= 8
                  ? null
                  : 'كلمة المرور يجب ألا تقل عن 8 أحرف',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text(context.tr('confirm')),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    String? Function(String?)? extraValidator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label),
      validator:
          extraValidator ??
          (value) => value == null || value.trim().isEmpty
              ? context.tr('required')
              : null,
    ),
  );
}
