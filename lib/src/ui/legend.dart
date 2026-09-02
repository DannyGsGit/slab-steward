import 'package:flutter/material.dart';

import '../map/otm_conventions.dart';
import '../model/difficulty.dart';
import '../model/lens.dart';
import '../model/trail_filters.dart';
import '../state/steward_state.dart';

/// Explains the line vocabulary currently on screen.
///
/// Worth having even in a rough-in: the whole point of a colour scheme is that
/// it means something specific, and a map that colours things without saying
/// why is just decoration.
///
/// Two vocabularies, in the order `docs/specs/map_view.md` sets them out. A
/// line's *colour* is its IMBA rating, always — that half never changes. A
/// line's *glow* is what Steward has to say about it: gold for what the
/// Highlight rules found, teal for what is in hand, its own rating for what
/// has an edit waiting on it. Shape carries the rest: dashed for informal,
/// faded for shut.
class Legend extends StatelessWidget {
  const Legend({super.key, required this.state});

  final StewardState state;

  /// The rating tiers, in the order a trailhead board lists them. Beginner
  /// rides with Easy and Pro Line with Expert, because on the map they are the
  /// same colour — see [difficultyColor].
  static const _tiers = <(Difficulty, String)>[
    (Difficulty.unrated, 'Un-rated'),
    (Difficulty.easy, 'Beginner & Easy'),
    (Difficulty.medium, 'Medium'),
    (Difficulty.difficult, 'Difficult'),
    (Difficulty.expert, 'Expert & Pro Line'),
  ];

  @override
  Widget build(BuildContext context) {
    final lenses = state.lenses.inOrder;
    final modes = [
      for (final mode in TravelMode.values)
        if (state.modes.contains(mode)) mode.noun,
    ];
    final entries = <_Entry>[
      for (final (difficulty, label) in _tiers)
        _Entry(_color(difficultyColor(difficulty)), label),
      if (lenses.isNotEmpty)
        _Entry(
          _color(trailColor),
          _missing(lenses),
          glow: _color(highlightGlowColor),
        ),
      _Entry(_color(trailColor), 'Selected', glow: _color(selectionColor)),
      _Entry(
        _color(trailColor),
        'Change staged — glows the rating it will carry',
        glow: _color(difficultyColor(Difficulty.unrated)),
      ),
      if (modes.isNotEmpty)
        _Entry(
          _color(trailColor),
          'Not open to ${_join(modes, 'or')}',
          dashed: true,
          faded: true,
        ),
      // Only worth explaining while the map is drawing them.
      if (state.kinds.contains(TrailKind.informal))
        _Entry(_color(trailColor), 'Informal / unofficial', dashed: true),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries) ...[
          entry,
          if (entry != entries.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  static Color _color(String hex) =>
      Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

  /// The selected lenses as prose: "difficulty and e-bike rule".
  static String _list(List<Lens> lenses, String conjunction) =>
      _join([for (final lens in lenses) lens.noun], conjunction);

  /// A list of nouns as English: "a", "a or b", "a, b or c".
  static String _join(List<String> nouns, String conjunction) {
    if (nouns.length == 1) return nouns.single;
    return '${nouns.take(nouns.length - 1).join(', ')} '
        '$conjunction ${nouns.last}';
  }

  /// A trail has to answer every selected lens to stop glowing, so a gold line
  /// means any one of them is unanswered.
  static String _missing(List<Lens> lenses) =>
      lenses.length == 1 && lenses.single == Lens.access
      ? 'Access unknown'
      : 'Missing ${_list(lenses, 'or')}';
}

class _Entry extends StatelessWidget {
  const _Entry(
    this.color,
    this.label, {
    this.dashed = false,
    this.faded = false,
    this.glow,
  });

  final Color color;
  final String label;
  final bool dashed;

  /// Drawn at the same opacity the map fades a trail nobody may ride at.
  final bool faded;

  /// The halo under the line, for the entries whose whole point is one. The
  /// line itself is drawn in a plain trail colour then: what the swatch is
  /// naming is the glow, not the rating under it.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: SizedBox(
            width: 28,
            height: 10,
            child: CustomPaint(
              painter: _LinePainter(color, dashed, faded, glow),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Wraps rather than overflows: a legend line names every mode being
        // asked about, and two of those do not fit on one line of a pane.
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.color, this.dashed, this.faded, this.glow);

  final Color color;
  final bool dashed;
  final bool faded;
  final Color? glow;

  /// The line itself, inside the swatch's taller box — the rest of the height
  /// is room for the glow to spread into.
  static const _stroke = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    if (glow case final glow?) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = glow.withValues(alpha: 0.55)
          ..strokeWidth = size.height
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
    final paint = Paint()
      ..color = faded ? color.withValues(alpha: disallowedOpacity) : color
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    // Matches the map's [2, 2] dash pattern, scaled to the swatch.
    const dash = 5.0;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color ||
      old.dashed != dashed ||
      old.faded != faded ||
      old.glow != glow;
}
