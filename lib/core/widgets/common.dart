import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';
import 'package:spendwise/core/widgets/icons.dart';

final DateFormat _dayFmt = DateFormat('d MMM yyyy');
final DateFormat _monthFmt = DateFormat('MMMM yyyy');
final DateFormat _shortDayFmt = DateFormat('EEE, d MMM');
final DateFormat _timeFmt = DateFormat('h:mm a');

String formatDay(DateTime d) => _dayFmt.format(d);
String formatMonth(DateTime d) => _monthFmt.format(d);
String formatTime(DateTime d) => _timeFmt.format(d);

/// "Today", "Yesterday" or "Tue, 14 Oct" (adds the year when not current).
String friendlyDay(DateTime d, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff == 1) return 'Tomorrow';
  return d.year == today.year ? _shortDayFmt.format(d) : _dayFmt.format(d);
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
    this.gradient,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final fin = context.finance;
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(Gap.radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: fin.cardShadow,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: fin.cardShadow.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: gradient == null ? (color ?? theme.cardTheme.color) : null,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: gradient == null
              ? null
              : BoxDecoration(gradient: gradient),
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 26, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontSize: 18),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Layered halo: soft outer ring, tinted disc, gradient icon.
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.06),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.20),
                      scheme.primary.withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: Icon(icon, size: 36, color: scheme.primary),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 22),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline,
    title: 'Something went wrong',
    message: message,
    actionLabel: onRetry == null ? null : 'Try again',
    onAction: onRetry,
  );
}

/// Renders loading / error (with retry) / data uniformly.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
  });
  final AsyncValue<T> value;
  final Widget Function(T value) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: 'We could not load your data. Your records are safe on this device.',
        onRetry: onRetry,
      ),
    );
  }
}

class MoneyText extends ConsumerWidget {
  const MoneyText(
    this.minor, {
    super.key,
    this.style,
    this.color,
    this.signed = false,
    this.hideZeroFraction = false,
  });
  final int minor;
  final TextStyle? style;
  final Color? color;
  final bool signed;
  final bool hideZeroFraction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(currencyProvider);
    return Text(
      formatMinor(
        minor,
        currency: cur,
        signed: signed,
        hideZeroFraction: hideZeroFraction,
      ),
      style: (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.iconKey,
    required this.color,
    this.size = 44,
  });
  final String iconKey;
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(categoryIcon(iconKey), color: c, size: size * 0.5),
    );
  }
}

class ProBadge extends StatelessWidget {
  const ProBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'PRO',
        style: TextStyle(
          color: scheme.onSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

/// Previous / next month switcher used by Home, Budgets and Reports.
class MonthSwitcher extends ConsumerWidget {
  const MonthSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final notifier = ref.read(selectedMonthProvider.notifier);
    final isCurrent = isSameMonth(month, DateTime.now());
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous month',
            visualDensity: VisualDensity.compact,
            onPressed: () => notifier.shift(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: month,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'Pick any day in the month',
                );
                if (picked != null) notifier.set(picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isCurrent ? 'This month' : formatMonth(month),
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            visualDensity: VisualDensity.compact,
            onPressed: () => notifier.shift(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// Large, thumb-friendly numeric keypad that edits a decimal string with at
/// most two fraction digits.
class AmountKeypad extends StatelessWidget {
  /// [onKey] receives '0'-'9', '.' or 'back'; apply it to the *current* value with
  /// [apply] so rapid taps never act on a stale value. [onClear] is a long-press on backspace.
  const AmountKeypad({super.key, required this.onKey, required this.onClear});
  final ValueChanged<String> onKey;
  final VoidCallback onClear;

  static String apply(String current, String key) {
    if (key == 'back') {
      return current.isEmpty
          ? current
          : current.substring(0, current.length - 1);
    }
    if (key == '.') {
      if (current.contains('.')) return current;
      return current.isEmpty ? '0.' : '$current.';
    }
    final dot = current.indexOf('.');
    if (dot >= 0 && current.length - dot > 2) return current; // max 2 decimals
    if (dot < 0 && current.length >= 10) return current;
    if (current == '0') return key; // no leading zeros
    return current + key;
  }

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '.',
      '0',
      'back',
    ];
    final theme = Theme.of(context);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final k in keys)
          Semantics(
            button: true,
            label: k == 'back'
                ? 'Backspace'
                : (k == '.' ? 'Decimal point' : 'Digit $k'),
            child: Material(
              color: k == 'back'
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                  : theme.cardTheme.color,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onKey(k),
                onLongPress: k == 'back' ? onClear : null,
                child: Center(
                  child: k == 'back'
                      ? Icon(
                          Icons.backspace_outlined,
                          color: theme.colorScheme.primary,
                        )
                      : Text(
                          k,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Color amountColor(BuildContext context, bool isIncome) =>
    isIncome ? context.finance.income : context.finance.expense;
