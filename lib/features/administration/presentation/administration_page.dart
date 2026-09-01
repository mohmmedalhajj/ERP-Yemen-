import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/security.dart';
import '../../../core/services/providers.dart';
import '../../../data/repositories/administration_repository.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/erp_ui.dart';

class AdministrationPage extends ConsumerStatefulWidget {
  const AdministrationPage({super.key});

  @override
  ConsumerState<AdministrationPage> createState() => _AdministrationPageState();
}

class _AdministrationPageState extends ConsumerState<AdministrationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ErpPageHeader(
        title: 'المستخدمون والصلاحيات',
        subtitle:
            'تُطبق الصلاحيات في الواجهة وخدمات الأعمال، وتسجل جميع تغييرات الإدارة محلياً.',
      ),
      TabBar(
        controller: _tabs,
        tabs: const [
          Tab(icon: Icon(Icons.people_outline), text: 'المستخدمون'),
          Tab(icon: Icon(Icons.admin_panel_settings_outlined), text: 'الأدوار'),
          Tab(icon: Icon(Icons.history), text: 'سجل العمليات'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: const [
            UsersManagementTab(),
            RolesManagementTab(),
            AuditLogTab(),
          ],
        ),
      ),
    ],
  );
}

class UsersManagementTab extends ConsumerStatefulWidget {
  const UsersManagementTab({super.key});

  @override
  ConsumerState<UsersManagementTab> createState() => _UsersManagementTabState();
}

class _UsersManagementTabState extends ConsumerState<UsersManagementTab> {
  final _search = TextEditingController();
  String _query = '';
  int _refresh = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersFuture = ref
        .watch(administrationRepositoryProvider)
        .users(search: _query);
    return FutureBuilder<List<Map<String, Object?>>>(
      key: ValueKey(_refresh),
      future: usersFuture,
      builder: (context, snapshot) => Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 10),
            child: ErpSearchFilterBar(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              hint: 'ابحث بالاسم أو اسم المستخدم',
              filterLabel: 'إضافة مستخدم',
              onFilter: _add,
            ),
          ),
          Expanded(child: _body(snapshot)),
        ],
      ),
    );
  }

  Widget _body(AsyncSnapshot<List<Map<String, Object?>>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done)
      return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError)
      return ErpErrorState(
        message: 'تعذر تحميل المستخدمين: ${snapshot.error}',
        onRetry: () => setState(() => _refresh++),
      );
    final rows = snapshot.data ?? const [];
    if (rows.isEmpty)
      return EmptyState(
        message: 'لا يوجد مستخدمون مطابقون.',
        icon: Icons.people_outline,
        action: FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('إضافة مستخدم'),
        ),
      );
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = rows[index];
        final active = (user['active'] as int) == 1;
        return ErpSectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            leading: CircleAvatar(
              child: Text((user['display_name'] as String).substring(0, 1)),
            ),
            title: Text(user['display_name'] as String),
            subtitle: Text(
              '@${user['username']} • ${user['role_name']}\n${user['branch_name'] ?? 'دون فرع محدد'} ${active ? '' : '• معطل'}',
            ),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _edit(user);
                if (value == 'archive') _archive(user);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                if (active)
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('تعطيل المستخدم'),
                  ),
              ],
            ),
            onTap: () => _edit(user),
          ),
        );
      },
    );
  }

  Future<void> _add() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _UserDialog(),
    );
    if (saved == true && mounted) setState(() => _refresh++);
  }

  Future<void> _edit(Map<String, Object?> user) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UserDialog(initial: user),
    );
    if (saved == true && mounted) setState(() => _refresh++);
  }

  Future<void> _archive(Map<String, Object?> user) async {
    final confirmed = await showErpConfirmation(
      context,
      title: 'تعطيل المستخدم',
      message:
          'سيُمنع المستخدم «${user['display_name']}» من تسجيل الدخول حتى يُعاد تفعيله من الإدارة.',
      confirmLabel: 'تعطيل',
      destructive: true,
    );
    if (!confirmed) return;
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    try {
      await ref
          .read(administrationRepositoryProvider)
          .archiveUser(actor, user['id'] as String);
      if (mounted) setState(() => _refresh++);
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString(), error: true);
    }
  }
}

class _UserDialog extends ConsumerStatefulWidget {
  const _UserDialog({this.initial});
  final Map<String, Object?>? initial;

  @override
  ConsumerState<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<_UserDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _name;
  final _password = TextEditingController();
  String? _roleId;
  String? _branchId;
  String? _warehouseId;
  String? _cashboxId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    _username = TextEditingController(text: item?['username'] as String? ?? '');
    _name = TextEditingController(text: item?['display_name'] as String? ?? '');
    _roleId = item?['role_id'] as String?;
    _branchId = item?['branch_id'] as String?;
    _warehouseId = item?['warehouse_id'] as String?;
    _cashboxId = item?['cashbox_id'] as String?;
  }

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _roleId == null) {
      if (_roleId == null)
        showAppMessage(context, 'اختر الدور الوظيفي.', error: true);
      return;
    }
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(administrationRepositoryProvider)
          .saveUser(
            actor,
            ManagedUserInput(
              id: widget.initial?['id'] as String?,
              username: _username.text,
              displayName: _name.text,
              roleId: _roleId!,
              password: _password.text.isEmpty ? null : _password.text,
              branchId: _branchId,
              warehouseId: _warehouseId,
              cashboxId: _cashboxId,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        showAppMessage(
          context,
          error.toString().replaceFirst('Bad state: ', ''),
          error: true,
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(administrationRepositoryProvider);
    return AlertDialog(
      title: Text(widget.initial == null ? 'إضافة مستخدم' : 'تعديل مستخدم'),
      content: FutureBuilder<List<List<Map<String, Object?>>>>(
        future: Future.wait([
          repo.roles(),
          repo.branches(),
          repo.warehouses(),
          repo.cashboxes(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
          final roles = snapshot.data![0];
          final branches = snapshot.data![1];
          final warehouses = snapshot.data![2];
          final cashboxes = snapshot.data![3];
          return SizedBox(
            width: 460,
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'اسم العرض'),
                      validator: _required,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                      ),
                      validator: _usernameValidator,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: widget.initial == null
                            ? 'كلمة المرور'
                            : 'كلمة مرور جديدة (اختياري)',
                      ),
                      validator: widget.initial == null
                          ? _passwordValidator
                          : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _roleId,
                      decoration: const InputDecoration(labelText: 'الدور'),
                      items: roles
                          .map(
                            (row) => DropdownMenuItem(
                              value: row['id'] as String,
                              child: Text(row['name_ar'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _roleId = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _branchId,
                      decoration: const InputDecoration(labelText: 'الفرع'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('دون تخصيص'),
                        ),
                        ...branches.map(
                          (row) => DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text(row['name_ar'] as String),
                          ),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _branchId = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _warehouseId,
                      decoration: const InputDecoration(
                        labelText: 'المخزن الافتراضي',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('دون تخصيص'),
                        ),
                        ...warehouses.map(
                          (row) => DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text(row['name_ar'] as String),
                          ),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _warehouseId = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _cashboxId,
                      decoration: const InputDecoration(
                        labelText: 'الصندوق الافتراضي',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('دون تخصيص'),
                        ),
                        ...cashboxes.map(
                          (row) => DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text(row['name_ar'] as String),
                          ),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _cashboxId = value),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null;
  String? _usernameValidator(String? value) =>
      value == null || !RegExp(r'^[a-zA-Z0-9._-]{3,40}$').hasMatch(value.trim())
      ? '3 أحرف على الأقل دون مسافات'
      : null;
  String? _passwordValidator(String? value) => value == null || value.length < 8
      ? 'كلمة المرور يجب ألا تقل عن 8 أحرف'
      : null;
}

class RolesManagementTab extends ConsumerStatefulWidget {
  const RolesManagementTab({super.key});

  @override
  ConsumerState<RolesManagementTab> createState() => _RolesManagementTabState();
}

class _RolesManagementTabState extends ConsumerState<RolesManagementTab> {
  int _refresh = 0;

  @override
  Widget build(BuildContext context) {
    final future = ref.watch(administrationRepositoryProvider).roles();
    return FutureBuilder<List<Map<String, Object?>>>(
      key: ValueKey(_refresh),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return ErpErrorState(
            message: 'تعذر تحميل الأدوار: ${snapshot.error}',
            onRetry: () => setState(() => _refresh++),
          );
        final rows = snapshot.data ?? const [];
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final role = rows[index];
            return ErpSectionCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
                title: Text(role['name_ar'] as String),
                subtitle: Text(
                  'الصلاحيات الممنوحة: ${role['permissions_count']}',
                ),
                trailing: const Icon(Icons.tune),
                onTap: () async {
                  final saved = await showDialog<bool>(
                    context: context,
                    builder: (_) => _RolePermissionsDialog(role: role),
                  );
                  if (saved == true && mounted) setState(() => _refresh++);
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _RolePermissionsDialog extends ConsumerStatefulWidget {
  const _RolePermissionsDialog({required this.role});
  final Map<String, Object?> role;

  @override
  ConsumerState<_RolePermissionsDialog> createState() =>
      _RolePermissionsDialogState();
}

class _RolePermissionsDialogState
    extends ConsumerState<_RolePermissionsDialog> {
  Set<String>? _selected;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(administrationRepositoryProvider);
    return FutureBuilder<Set<String>>(
      future: _selected == null
          ? repo.rolePermissions(widget.role['id'] as String)
          : Future.value(_selected!),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const AlertDialog(
            content: SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        _selected ??= {...snapshot.data!};
        final actor = ref.watch(sessionProvider);
        final systemRole = (widget.role['system_role'] as int) == 1;
        final canEdit =
            actor?.permissions.contains(Permissions.usersManage) == true &&
            (!systemRole || actor?.roleCode == 'system_admin');
        return AlertDialog(
          title: Text('صلاحيات: ${widget.role['name_ar']}'),
          content: SizedBox(
            width: 500,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (!canEdit)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'لا تملك صلاحية تعديل هذا الدور.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                for (final permission in Permissions.all)
                  CheckboxListTile(
                    value: _selected!.contains(permission),
                    title: Text(_permissionLabel(permission)),
                    subtitle: Text(permission),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: !canEdit || _saving
                        ? null
                        : (checked) => setState(() {
                            if (checked == true) {
                              _selected!.add(permission);
                            } else {
                              _selected!.remove(permission);
                            }
                          }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            if (canEdit)
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الصلاحيات'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _save() async {
    final actor = ref.read(sessionProvider);
    if (actor == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(administrationRepositoryProvider)
          .updateRolePermissions(
            actor,
            widget.role['id'] as String,
            _selected!,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _permissionLabel(String code) => switch (code) {
    Permissions.usersManage => 'إدارة المستخدمين والأدوار',
    Permissions.settingsManage => 'إدارة الإعدادات',
    Permissions.productsView => 'عرض الأصناف',
    Permissions.productsManage => 'إدارة الأصناف',
    Permissions.customersManage => 'إدارة العملاء',
    Permissions.suppliersManage => 'إدارة الموردين',
    Permissions.salesCreate => 'إنشاء المبيعات',
    Permissions.salesPost => 'ترحيل المبيعات',
    Permissions.purchasesCreate => 'إنشاء المشتريات',
    Permissions.purchasesPost => 'ترحيل المشتريات',
    Permissions.inventoryManage => 'إدارة المخزون والجرد',
    Permissions.cashManage => 'إدارة الصناديق والسندات',
    Permissions.accountingPost => 'ترحيل القيود',
    Permissions.reportsView => 'عرض التقارير',
    Permissions.costView => 'عرض التكلفة',
    Permissions.profitView => 'عرض الأرباح',
    Permissions.backupsManage => 'النسخ والاستعادة',
    Permissions.licensesManage => 'إدارة الترخيص',
    _ => code,
  };
}

class AuditLogTab extends ConsumerStatefulWidget {
  const AuditLogTab({super.key});
  @override
  ConsumerState<AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends ConsumerState<AuditLogTab> {
  final _search = TextEditingController();
  String _query = '';
  int _refresh = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final future = ref
        .watch(administrationRepositoryProvider)
        .auditLog(search: _query);
    return FutureBuilder<List<Map<String, Object?>>>(
      key: ValueKey(_refresh),
      future: future,
      builder: (context, snapshot) => Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 10),
            child: ErpSearchFilterBar(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              hint: 'ابحث بالإجراء أو المستخدم أو الكيان',
            ),
          ),
          Expanded(
            child: snapshot.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : snapshot.hasError
                ? ErpErrorState(
                    message: 'تعذر تحميل السجل: ${snapshot.error}',
                    onRetry: () => setState(() => _refresh++),
                  )
                : _list(snapshot.data ?? const []),
          ),
        ],
      ),
    );
  }

  Widget _list(List<Map<String, Object?>> rows) {
    if (rows.isEmpty)
      return const EmptyState(
        message: 'لا توجد عمليات مطابقة في السجل.',
        icon: Icons.history,
      );
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        return ErpSectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.history)),
            title: Text(row['action'] as String),
            subtitle: Text(
              '${row['display_name'] ?? 'النظام'} • ${row['entity_type']}\n${row['created_at']}',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
