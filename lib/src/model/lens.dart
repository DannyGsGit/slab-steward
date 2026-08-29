/// Which trails are drawn, and what questions the colouring answers.
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

/// One question the map can ask of a trail.
///
/// Lenses combine rather than compete: the rider picks any number of them, and
/// a trail is only "done" when it answers all of them. That is what used to be
/// a single fixed "Missing any" lens — selecting the attribute lenses
/// together is exactly it — and selecting none of them is the plain map.
enum Lens {
  /// Purple where OSM doesn't say whether the current travel mode is allowed.
  /// Meaningless without a mode, so the UI hides it under [TravelMode.all].
  access('Unknown access', 'access', []),

  /// Does this trail have an IMBA difficulty rating?
  difficulty('Missing difficulty', 'difficulty', ['mtb:scale:imba']),

  /// Does this trail say whether e-bikes may ride it?
  electricBicycle('Missing e-bike access', 'e-bike rule', ['electric_bicycle']);

  const Lens(this.label, this.noun, this.keys);

  /// How the picker names the lens.
  final String label;

  /// What the legend calls the thing the lens looks for, as a bare noun so it
  /// reads inside a list: "Missing difficulty or e-bike rule".
  final String noun;

  /// The OSM keys this lens inspects. Empty for [access], which asks about
  /// access rather than about an attribute.
  final List<String> keys;
}

/// The set of lenses currently applied, and what it implies for the map.
extension LensSelection on Iterable<Lens> {
  /// The selection in enum order, so the legend and the picker list it the
  /// same way however it was assembled.
  List<Lens> get inOrder => [
    for (final lens in Lens.values)
      if (contains(lens)) lens,
  ];

  /// Whether passing every selected lens recolours the trail teal. Attribute
  /// lenses say "this one is done"; [Lens.access] on its own leaves passing
  /// trails in plain brown, the way OpenTrailMap does.
  bool get tintsSpecified => any((lens) => lens.keys.isNotEmpty);
}
