import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// SLAB's difficulty scale and its mapping onto OSM's `mtb:scale:imba`.
///
/// See the product description §3.1. Two things that look like quirks and are
/// not: `proLine` writes the same `4` as `expert` (OSM's schema tops out at 4,
/// and the Pro Line distinction is preserved in Commons instead), and `unrated`
/// writes nothing at all — absence of the tag *is* the un-rated state.
enum Difficulty {
  beginner('Beginner', 0, 'beginner'),
  easy('Easy', 1, 'easy'),
  medium('Medium', 2, 'medium'),
  difficult('Difficult', 3, 'difficult'),
  expert('Expert', 4, 'expert'),
  proLine('Pro Line', 4, 'pro-line'),
  unrated('Un-rated', null, 'unrated');

  const Difficulty(this.label, this.imbaScale, this._asset);

  final String label;

  /// The `mtb:scale:imba` value this writes, or null to write no tag.
  final int? imbaScale;

  final String _asset;

  /// The signage chip SLAB ships for this rating, in `assets/slab`.
  ///
  /// Shared artwork rather than a shape Steward draws for itself: the two apps
  /// have to put the same glyph in front of a rider, and a chip redrawn here
  /// would be a second definition of the scale waiting to drift from the
  /// first.
  String get assetPath => 'assets/slab/difficulty/difficulty-$_asset.svg';

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

/// The circle / square / diamond signage chip for a difficulty, drawn from
/// SLAB's own asset — see [Difficulty.assetPath].
///
/// Square whatever the rating: the doubled diamonds of Expert and Pro Line are
/// composed inside the artwork's own 48×48 box, so callers reserving space for
/// a glyph only ever need [size].
class DifficultyIcon extends StatelessWidget {
  const DifficultyIcon(this.difficulty, {super.key, this.size = 18});

  final Difficulty difficulty;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      difficulty.assetPath,
      width: size,
      height: size,
      // The chips carry their own colours — the gold outline is part of the
      // signage, not a tint the chrome gets to choose.
      semanticsLabel: '${difficulty.label} trail',
    );
  }
}
