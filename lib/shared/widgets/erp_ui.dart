import 'package:flutter/material.dart';

/// رأس موحد لصفحات ERP مع عنوان ووصف وإجراءات متكيفة مع عرض الهاتف.
class ErpPageHeader extends StatelessWidget {
  const ErpPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
        if (actions.isEmpty) return heading;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        );
      },
    ),
  );
}

class ErpSectionCard extends StatelessWidget {
  const ErpSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class ErpSearchFilterBar extends StatelessWidget {
  const ErpSearchFilterBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'بحث فوري',
    this.filterLabel,
    this.onFilter,
    this.sortLabel,
    this.onSort,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final String? filterLabel;
  final VoidCallback? onFilter;
  final String? sortLabel;
  final VoidCallback? onSort;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final buttons = <Widget>[
          if (onFilter != null)
            OutlinedButton.icon(
              onPressed: onFilter,
              icon: const Icon(Icons.filter_alt_outlined),
              label: Text(filterLabel ?? 'فلترة'),
            ),
          if (onSort != null)
            OutlinedButton.icon(
              onPressed: onSort,
              icon: const Icon(Icons.sort),
              label: Text(sortLabel ?? 'ترتيب'),
            ),
        ];
        final search = TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'مسح',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        );
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              search,
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
                ),
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            if (buttons.isNotEmpty) ...[const SizedBox(width: 8), ...buttons],
          ],
        );
      },
    ),
  );
}

class ErpMetricCard extends StatelessWidget {
  const ErpMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;
    return ErpSectionCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ErpStatusChip extends StatelessWidget {
  const ErpStatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final (label, color) = switch (normalized) {
      'posted' || 'approved' || 'received' || 'paid' => ('معتمد', Colors.green),
      'cancelled' || 'reversed' => ('ملغي', Colors.red),
      'draft' => ('مسودة', Colors.orange),
      'sent' => ('مرسل', Colors.blue),
      _ => (status, Theme.of(context).colorScheme.primary),
    };
    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text(label),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: color),
      backgroundColor: color.withValues(alpha: .10),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class ErpPagedFooter extends StatelessWidget {
  const ErpPagedFooter({
    super.key,
    required this.page,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    this.totalLabel,
  });

  final int page;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String? totalLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    child: Row(
      children: [
        if (totalLabel != null)
          Expanded(
            child: Text(
              totalLabel!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          const Spacer(),
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'الصفحة السابقة',
        ),
        Text('صفحة $page', style: Theme.of(context).textTheme.bodySmall),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'الصفحة التالية',
        ),
      ],
    ),
  );
}

Future<bool> showErpConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        destructive ? Icons.warning_amber_rounded : Icons.help_outline,
        color: destructive ? Theme.of(dialogContext).colorScheme.error : null,
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('تراجع'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class ErpErrorState extends StatelessWidget {
  const ErpErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ],
      ),
    ),
  );
}
