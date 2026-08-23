/// Which trails are drawn, and what question the colouring answers.
///
/// Both concepts come straight from OpenTrailMap: a travel mode decides what is
/// shown, a lens decides how it is coloured. Steward ships a narrow slice of
/// each — the modes a mountain biker cares about, and the lenses that map onto
/// the fields the guided editor can actually write.
library;

enum TravelMode {
  /// Everything in the tileset, nothing dimmed.
  all('All trails', null),

  mtb('Mountain biking', 'mtb'),
  foot('Hiking', 'foot');

  const TravelMode(this.label, this.osmKey);

  final String label;

  /// The OSM access key, or null for [all].
  final String? osmKey;
}

enum Lens {
  /// No question asked; every trail renders in the plain OpenTrailMap brown.
  none('Plain', []),

  /// Purple where OSM doesn't say whether the current travel mode is allowed.
  /// Meaningless without a mode, so the UI hides it under [TravelMode.all].
  access('Unknown access', []),

  /// Does this trail have an IMBA difficulty rating?
  difficulty('Missing difficulty', ['mtb:scale:imba']),

  /// Does this trail have a surface?
  surface('Missing surface', ['surface']),

  /// Steward's own composite: a trail is complete when it has both.
  /// This is the "completeness indicator" of the product description §2.
  completeness('Missing either', ['mtb:scale:imba', 'surface']);

  const Lens(this.label, this.keys);

  final String label;

  /// The OSM keys this lens inspects. Empty for [none] and [access], which ask
  /// about access rather than about an attribute.
  final List<String> keys;

  /// Whether trails that fail the lens draw in purple. [none] asks nothing, so
  /// nothing is ever purple.
  bool get showsUnspecified => this != Lens.none;

  /// Whether passing the lens recolours the trail teal. Attribute lenses say
  /// "this one is done"; [access] leaves passing trails in plain brown, the way
  /// OpenTrailMap does.
  bool get tintsSpecified => keys.isNotEmpty;

  /// [completeness] needs *every* key present; the single-attribute lenses need
  /// only their one key. This is the one place Steward diverges from
  /// OpenTrailMap, whose attribute lenses are all any-of.
  bool get requiresAllKeys => this == Lens.completeness;
}
