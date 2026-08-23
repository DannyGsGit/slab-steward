import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/difficulty.dart';

/// The small shared vocabulary the editors are built from: a labelled row, the
/// MISSING / STAGED markers, a compact icon button, and the difficulty picker.
///
/// These live apart from any one panel because the single-trail panel, the
/// in-view list and the bulk editor all have to read as the same editor —
/// three different chromes around the same guided vocabulary would be three
/// different products.

/// A labelled attribute row: the label line carries the state markers and any
/// edit affordances, and the value sits below it.
class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.label,
    required this.child,
    this.isMissing = false,
    this.isStaged = false,
    this.trailing,
  });

  final String label;
  final Widget child;
  final bool isMissing;
  final bool isStaged;

  /// The row's edit affordances, when the attribute has any. Sits on the label
  /// line so the value below it stays uncluttered.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          child: Row(
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.8),
              ),
              if (isMissing) ...[
                const SizedBox(width: 8),
                const StatusBadge.missing(),
              ],
              if (isStaged) ...[
                const SizedBox(width: 8),
                const StatusBadge.staged(),
              ],
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: 6),
        DefaultTextStyle.merge(style: theme.textTheme.bodyMedium, child: child),
      ],
    );
  }
}

/// A one-word state marker. Missing borrows the map's "OSM doesn't know this"
/// purple; staged borrows the Pro Line orange, the only other colour in the
/// app that means "look here".
class StatusBadge extends StatelessWidget {
  const StatusBadge._(this.label, this.color, {super.key});

  const StatusBadge.missing({Key? key})
    : this._('MISSING', const Color(0xFF8A0092), key: key);

  const StatusBadge.staged({Key? key})
    : this._('STAGED', const Color(0xFFB35400), key: key);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// A compact icon button that doesn't impose a 48px row on the panel.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.emphasised = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: emphasised ? scheme.onPrimary : null,
        backgroundColor: emphasised ? scheme.primary : null,
        disabledBackgroundColor: emphasised
            ? scheme.onSurface.withValues(alpha: 0.12)
            : null,
      ),
    );
  }
}

/// The difficulty picker: SLAB's signage glyphs, never a numeric scale.
class DifficultyDropdown extends StatelessWidget {
  const DifficultyDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = 'Choose a rating',
  });

  final Difficulty? value;

  /// Null disables the picker — a batch that is mid-apply must not be
  /// re-pointed underneath itself.
  final ValueChanged<Difficulty?>? onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Difficulty>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: Text(hint, style: theme.textTheme.bodyMedium),
          onChanged: onChanged,
          items: [
            for (final difficulty in Difficulty.selectable)
              DropdownMenuItem(
                value: difficulty,
                child: Row(
                  children: [
                    DifficultyIcon(difficulty, size: 14),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        difficulty.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What to call the multi-select modifier in front of the user.
///
/// Read off the platform rather than hard-coded, because the gesture itself
/// differs: on macOS ctrl-click is a right-click, so the additive modifier has
/// to be cmd.
String get multiSelectModifier => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.iOS => '⌘',
  _ => 'Ctrl',
};
