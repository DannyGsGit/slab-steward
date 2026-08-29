import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/difficulty.dart';
import '../model/electric_bicycle.dart';
import 'slab_theme.dart';

/// The small shared vocabulary the editors are built from: a labelled row, the
/// MISSING / STAGED markers, a compact icon button, and the guided pickers.
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
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
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

/// A one-word state marker, in the design system's badge shape: a tinted pill
/// carrying its own colour as text.
///
/// Both colours are the map's, lifted a few stops so they hold up as small
/// text on the dark chrome. Missing is the "OSM doesn't know this" purple the
/// map draws unspecified trails in; staged is the blue the map glows a trail
/// with once something is pending on it. Neither is gold — gold is what you
/// press, and a badge is not a button.
class StatusBadge extends StatelessWidget {
  const StatusBadge._(this.label, this.color, {super.key});

  const StatusBadge.missing({Key? key})
    : this._('MISSING', const Color(0xFFDB6FE0), key: key);

  const StatusBadge.staged({Key? key})
    : this._('STAGED', const Color(0xFF6FA8F0), key: key);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(SlabRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
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
  /// re-pointed underneath itself, and neither must a trail whose
  /// authoritative tags are still being read.
  final ValueChanged<Difficulty?>? onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return GuidedDropdown<Difficulty>(
      value: value,
      onChanged: onChanged,
      hint: hint,
      options: [
        for (final difficulty in Difficulty.selectable)
          PickerOption(
            difficulty,
            label: difficulty.label,
            glyph: DifficultyIcon(difficulty, size: 17),
          ),
      ],
    );
  }
}

/// The e-bike permission picker.
///
/// Every option carries its meaning, because "allowed" and "e-bike trail" are
/// a distinction a rider can only get right if it's spelled out at the moment
/// of choosing. See [EbikeAccess].
class ElectricBicycleDropdown extends StatelessWidget {
  const ElectricBicycleDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = 'Choose a permission',
  });

  final EbikeAccess? value;
  final ValueChanged<EbikeAccess?>? onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return GuidedDropdown<EbikeAccess>(
      value: value,
      onChanged: onChanged,
      hint: hint,
      options: [
        for (final access in EbikeAccess.selectable)
          PickerOption(
            access,
            label: access.label,
            glyph: EbikeIcon(access, size: 16),
            description: access.description,
          ),
      ],
    );
  }
}

/// One option in a guided picker: what it's worth, what to call it, what it
/// looks like, and — where the label alone can be misread — what it means.
class PickerOption<T> {
  const PickerOption(
    this.value, {
    required this.label,
    required this.glyph,
    this.description,
  });

  final T value;
  final String label;
  final Widget glyph;

  /// A line of plain language shown under [label] in the open menu. Null for
  /// options whose label is already unambiguous — a black diamond needs no
  /// gloss.
  final String? description;
}

/// The shared shape of every guided picker: a bordered, dense dropdown whose
/// options each carry a glyph, a plain-language label, and optionally a line
/// saying what the option actually claims.
///
/// The closed field stays one line whatever the options do — the explanation
/// is there to be read while choosing, not to double the height of a panel
/// that has already been answered.
class GuidedDropdown<T> extends StatelessWidget {
  const GuidedDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    required this.options,
    required this.hint,
  });

  final T? value;

  /// Null disables the picker.
  final ValueChanged<T?>? onChanged;

  /// In the order the picker offers them.
  final List<PickerOption<T>> options;

  final String hint;

  /// Menu rows have to be tall enough for a wrapped second line; a picker
  /// whose options are all one-liners keeps the default row height.
  static const _describedItemHeight = 76.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final described = options.any((o) => o.description != null);
    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          borderRadius: BorderRadius.circular(SlabRadii.card),
          iconEnabledColor: SlabColors.gold,
          iconDisabledColor: SlabColors.sageDim,
          style: theme.textTheme.bodyMedium,
          itemHeight: described
              ? _describedItemHeight
              : kMinInteractiveDimension,
          hint: Text(
            hint,
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
          onChanged: onChanged,
          // The closed field shows the label alone. Without this the button
          // would wear the whole two-line menu row.
          selectedItemBuilder: (context) => [
            for (final option in options)
              Row(
                children: [
                  option.glyph,
                  const SizedBox(width: 8),
                  _label(option),
                ],
              ),
          ],
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        option.glyph,
                        const SizedBox(width: 8),
                        _label(option),
                      ],
                    ),
                    if (option.description case final description?) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _label(PickerOption<T> option) =>
      Flexible(child: Text(option.label, overflow: TextOverflow.ellipsis));
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
