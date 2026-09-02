import 'package:flutter/material.dart';

import 'slab_theme.dart';

/// The small pieces of SLAB chrome every panel is assembled from: a panel
/// heading, the recessed row, and the tag pill.
///
/// They live together for the same reason the pickers in `fields.dart` do —
/// four panels that each drew their own heading would drift into four
/// different products. See `docs/requirements/SLAB Design System - Mockups v2.html`.

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A day, the way every SLAB panel writes one: `Aug 30, 2026`.
///
/// Always rendered in the rider's own timezone. OSM hands back timestamps in
/// UTC, which is already tomorrow for an evening edit anywhere west of
/// Greenwich — and it agrees with the day-bucketing behind the streak and the
/// charts, so a changeset can't be listed under one date and counted under
/// another.
String formatSlabDate(DateTime date) {
  final local = date.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

/// The heading of a panel or dialog: the title, whatever the panel wants
/// beside it, and the control that dismisses it.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    required this.onClose,
    required this.closeTooltip,
    this.large = false,
    this.trailing,
  });

  final String title;
  final VoidCallback onClose;
  final String closeTooltip;

  /// Dialogs get the larger of the two heading sizes; panels floating on the
  /// map get the smaller one, because every pixel there costs map.
  final bool large;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: large
                  ? theme.textTheme.titleLarge
                  : theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: closeTooltip,
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// The design doc's `.card` — a row or block that sits *on* a panel, one step
/// lighter than the panel itself, hairline-bordered.
class SlabSurface extends StatelessWidget {
  const SlabSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color = SlabColors.ink700,
    this.borderColor = SlabColors.line,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(SlabRadii.card),
      border: Border.all(color: borderColor),
    ),
    child: child,
  );
}

/// The doc's `.tag` / `.chip`: a quiet pill carrying a fact or a hint, with an
/// optional glyph in front of it.
class SlabTag extends StatelessWidget {
  const SlabTag({
    super.key,
    required this.label,
    this.icon,
    this.color = SlabColors.sage,
    this.background = SlabColors.ink900,
    this.borderColor = SlabColors.line,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final Color background;
  final Color borderColor;

  /// The same pill in gold, for the one hint that is an invitation rather
  /// than a note.
  factory SlabTag.gold({required String label, IconData? icon}) => SlabTag(
    label: label,
    icon: icon,
    color: SlabColors.gold,
    background: SlabColors.goldSoft,
    borderColor: SlabColors.goldSoft,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SlabRadii.pill),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
