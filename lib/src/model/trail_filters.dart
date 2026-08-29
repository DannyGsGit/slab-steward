/// The kinds of line the trail tileset carries, as things a rider can switch
/// off.
///
/// The old control asked one question — bike, foot, or everything — and the
/// answer was never the one a steward wanted. "Everything" buries a trail
/// network under the sidewalks and driveways that share the tileset with it;
/// "mountain biking" is about who may ride, which is a different question from
/// what kind of line this is.
///
/// So the two questions are separated. [TravelMode] stays the access question
/// — who is allowed here — and this is the shape question: doubletrack,
/// pavement, sidewalks, unsanctioned singletrack. Each kind is a plain toggle,
/// and a trail is drawn unless it matches a kind that is switched off. Nothing
/// here narrows what may be *edited*: a hidden trail is a trail off the map,
/// and Steward has no opinion about it beyond that.
enum TrailKind {
  informal(
    'Informal trails',
    'Unsanctioned lines, tagged informal=yes',
    onByDefault: true,
  ),
  track('Tracks & fire roads', 'Doubletrack, highway=track'),
  footway(
    'Footways & sidewalks',
    'Sidewalks, crossings, urban paths, highway=footway',
  ),
  paved('Paved surfaces', 'Asphalt, concrete, paving stones and the like');

  const TrailKind(this.label, this.description, {this.onByDefault = false});

  /// How the picker names the kind.
  final String label;

  /// One line saying what the toggle actually covers, shown under [label].
  final String description;

  /// Whether a fresh session draws this kind.
  final bool onByDefault;

  /// What the map starts out drawing.
  static Set<TrailKind> get defaults => {
    for (final kind in values)
      if (kind.onByDefault) kind,
  };
}
