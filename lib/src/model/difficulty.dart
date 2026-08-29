import 'package:flutter/material.dart';

/// SLAB's difficulty scale and its mapping onto OSM's `mtb:scale:imba`.
///
/// See the product description §3.1. Two things that look like quirks and are
/// not: `proLine` writes the same `4` as `expert` (OSM's schema tops out at 4,
/// and the Pro Line distinction is preserved in Commons instead), and `unrated`
/// writes nothing at all — absence of the tag *is* the un-rated state.
enum Difficulty {
  beginner('Beginner', 0, Color(0xFF7B4FA8), _Shape.circle, 1),
  easy('Easy', 1, Color(0xFF2E9E4F), _Shape.circle, 1),
  medium('Medium', 2, Color(0xFF2C6FBB), _Shape.square, 1),
  difficult('Difficult', 3, Color(0xFF1A1A1A), _Shape.diamond, 1),
  expert('Expert', 4, Color(0xFF1A1A1A), _Shape.diamond, 2),
  proLine('Pro Line', 4, Color(0xFFE1701A), _Shape.diamond, 2),
  unrated('Un-rated', null, Color(0xFFC8A02C), _Shape.ring, 1);

  const Difficulty(
    this.label,
    this.imbaScale,
    this.color,
    this._shape,
    this._count,
  );

  final String label;

  /// The `mtb:scale:imba` value this writes, or null to write no tag.
  final int? imbaScale;

  final Color color;
  final _Shape _shape;
  final int _count;

  /// The one OSM key this scale reads and writes. `mtb:scale` is a different
  /// scale for a different question — see the product description §3.1.
  static const osmKey = 'mtb:scale:imba';

  /// Everything a rider can pick in the editor.
  ///
  /// [unrated] is excluded on purpose: choosing it would *delete* an existing
  /// rating, which is a destructive edit dressed up as a dropdown entry. If
  /// clearing a bad rating turns out to be needed, it wants its own affordance
  /// and its own confirmation.
  static List<Difficulty> get selectable =>
      values.where((d) => d != Difficulty.unrated).toList();

  /// Pro Line is a Commons-only refinement; OSM cannot represent it.
  bool get isCommonsOnly => this == Difficulty.proLine;

  /// The caveat that has to accompany a Pro Line choice, wherever it's made —
  /// the picker, the staged edit, the review list. Saying it in one place is
  /// how it stays the same sentence in all three.
  static const commonsOnlyNote =
      'OpenStreetMap records Pro Line as Expert (4). The Pro Line '
      'distinction needs Commons, which is not built yet.';

  /// Reads a raw `mtb:scale:imba` value off an OSM feature.
  ///
  /// `4` always resolves to [expert] — Pro Line is not recoverable from OSM
  /// alone, it has to come back from Commons.
  static Difficulty fromImba(String? raw) {
    if (raw == null || raw.isEmpty) return Difficulty.unrated;
    return switch (int.tryParse(raw.trim())) {
      0 => Difficulty.beginner,
      1 => Difficulty.easy,
      2 => Difficulty.medium,
      3 => Difficulty.difficult,
      4 => Difficulty.expert,
      _ => Difficulty.unrated,
    };
  }
}

enum _Shape { circle, square, diamond, ring }

/// The circle / square / diamond signage glyph for a difficulty.
class DifficultyIcon extends StatelessWidget {
  const DifficultyIcon(this.difficulty, {super.key, this.size = 18});

  final Difficulty difficulty;
  final double size;

  /// How wide the glyph will draw at [size] — doubled diamonds overlap rather
  /// than tile, so this isn't just `size * count`. Callers that have to
  /// reserve space for the glyph (the map badge) need it up front.
  static double widthFor(Difficulty difficulty, double size) =>
      size * difficulty._count - (difficulty._count - 1) * size * 0.35;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widthFor(difficulty, size),
      height: size,
      child: CustomPaint(painter: _GlyphPainter(difficulty)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.difficulty);

  final Difficulty difficulty;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.height;
    // Doubled glyphs overlap slightly, the way trail signage prints them.
    final step = side * 0.65;
    for (var i = 0; i < difficulty._count; i++) {
      _paintGlyph(canvas, Rect.fromLTWH(i * step, 0, side, side));
    }
  }

  void _paintGlyph(Canvas canvas, Rect r) {
    final fill = Paint()..color = difficulty.color;
    switch (difficulty._shape) {
      case _Shape.circle:
        canvas.drawCircle(r.center, r.width / 2, fill);
      case _Shape.square:
        canvas.drawRect(r.deflate(r.width * 0.06), fill);
      case _Shape.diamond:
        final c = r.center;
        final half = r.width / 2;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - half)
            ..lineTo(c.dx + half, c.dy)
            ..lineTo(c.dx, c.dy + half)
            ..lineTo(c.dx - half, c.dy)
            ..close(),
          fill,
        );
      case _Shape.ring:
        canvas.drawCircle(
          r.center,
          r.width / 2 - r.width * 0.1,
          Paint()
            ..color = difficulty.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = r.width * 0.2,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.difficulty != difficulty;
}
