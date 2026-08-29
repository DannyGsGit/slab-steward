import 'package:flutter/material.dart';

import '../map/otm_conventions.dart';
import '../model/lens.dart';
import '../model/trail_filters.dart';
import '../state/steward_state.dart';

/// Explains the line vocabulary currently on screen.
///
/// Worth having even in a rough-in: the whole point of following
/// OpenTrailMap's conventions is that they mean something specific, and a map
/// that colours things without saying why is just decoration.
class Legend extends StatelessWidget {
  const Legend({super.key, required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final lenses = state.lenses.inOrder;
    final modes = [
      for (final mode in TravelMode.values)
        if (state.modes.contains(mode)) mode.noun,
    ];
    final entries = <_Entry>[
      if (lenses.tintsSpecified)
        _Entry(_color(specifiedColor), 'Has ${_list(lenses, 'and')}')
      else
        _Entry(_color(trailColor), 'Trail'),
      if (lenses.isNotEmpty) _Entry(_color(unspecifiedColor), _missing(lenses)),
      if (modes.isNotEmpty)
        _Entry(
          _color(noAccessTrailColor),
          'Not open to ${_join(modes, 'or')}',
          dashed: true,
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

  /// A trail has to answer every selected lens to draw teal, so a purple line
  /// means any one of them is unanswered.
  static String _missing(List<Lens> lenses) =>
      lenses.length == 1 && lenses.single == Lens.access
      ? 'Access unknown'
      : 'Missing ${_list(lenses, 'or')}';
}

class _Entry extends StatelessWidget {
  const _Entry(this.color, this.label, {this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            width: 28,
            height: 4,
            child: CustomPaint(painter: _LinePainter(color, dashed)),
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
  _LinePainter(this.color, this.dashed);

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
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
      old.color != color || old.dashed != dashed;
}
