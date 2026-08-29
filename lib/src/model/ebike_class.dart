/// What "e-bike" means where the trail actually is, and which OSM key carries
/// each machine.
///
/// The source is SLAB's own mapping sheet — region → app label → access →
/// `key=value` — which is itself a reading of
/// https://wiki.openstreetmap.org/wiki/Key:electric_bicycle. Two things fall
/// out of it, and both are why this file exists:
///
///  * '''The words are local.''' A rider in Bend reads "Class 1" off the sign
///    at the trailhead; a rider in Bergamo reads "pedelec". The same machine,
///    the same tag, two vocabularies — so the picker has to speak the one the
///    rider is standing in.
///  * '''The ladder is local.''' The US stacks Class 1 / 2 / 3; the EU stacks
///    pedelec then s-pedelec; Belgium and the Netherlands add their own mofa
///    and moped rungs on top. Each rung is its own OSM key, because OSM
///    describes machines rather than legal classes.
///
/// Steward writes the bottom rung and no more — see [EbikeClass.isSupported].
/// That rung is `electric_bicycle` in most of the table, and `electric_mofa`
/// in Belgium and the Netherlands, where the lowest class the law recognises
/// on a path is the mofa — a Class A or a snorfiets — and not the pedelec,
/// which those two treat as a bicycle and tag as one.
library;

/// One rung of a jurisdiction's e-bike ladder.
class EbikeClass {
  const EbikeClass({
    required this.label,
    required this.detail,
    required this.osmKey,
    this.isSupported = false,
    this.note,
  });

  /// What the rider's own trailhead sign would call it — "Class 1",
  /// "Pedelec", "Snorfiets".
  final String label;

  /// The machine behind the name, in the terms the law defines it with:
  /// "pedal-assist, ≤20 mph". Shown under [label] while choosing, because a
  /// class number alone is only meaningful to someone who already knows it.
  final String detail;

  /// The OSM access key this machine rides under. `yes` where it may ride,
  /// `no` where it may not — the access vocabulary, as everywhere else.
  final String osmKey;

  /// Whether Steward will actually write this rung.
  ///
  /// Only the lowest one, for now, per the product's own instruction: a cap of
  /// "up to Class 1" is the claim almost every trail sign in front of a rider
  /// is making, and the rungs above it reach keys — `moped`, `motorcycle` —
  /// that say far more about a trail than an e-bike question should.
  final bool isSupported;

  /// A caveat worth showing beside the rung.
  final String? note;

  /// The value written where this machine may ride, and where it may not.
  static const allowedValue = 'yes';
  static const bannedValue = 'no';
}

/// A place whose e-bike vocabulary Steward knows.
///
/// The boundaries are deliberately coarse — see [ebikeJurisdictionAt]. They
/// pick the words the picker uses and nothing else.
enum EbikeJurisdiction {
  unitedStates('United States', [
    EbikeClass(
      label: 'Class 1',
      detail: 'pedal-assist, ≤20 mph',
      osmKey: 'electric_bicycle',
      isSupported: true,
    ),
    EbikeClass(
      label: 'Class 2',
      detail: 'throttle, ≤20 mph',
      osmKey: 'electric_mofa',
    ),
    EbikeClass(
      label: 'Class 3 pedal-assist',
      detail: '≤28 mph',
      osmKey: 'speed_pedelec',
    ),
    EbikeClass(
      label: 'Class 3 throttle',
      detail: '≤28 mph with a throttle',
      osmKey: 'motorcycle',
      note: 'Rides under the motorcycle key in OSM.',
    ),
  ]),

  europe('Europe / UK', [
    EbikeClass(
      label: 'Pedelec',
      detail: '≤250 W, ≤25 km/h',
      osmKey: 'electric_bicycle',
      isSupported: true,
      note:
          'Where the law treats a pedelec as a bicycle, OSM often carries '
          'nothing more than bicycle=yes.',
    ),
    EbikeClass(
      label: 'S-pedelec',
      detail: '≤45 km/h, registered and plated',
      osmKey: 'speed_pedelec',
    ),
  ]),

  belgium('Belgium', [
    EbikeClass(
      label: 'Class A',
      detail: 'mofa, ≤25 km/h',
      osmKey: 'electric_mofa',
      isSupported: true,
    ),
    EbikeClass(
      label: 'Class P',
      detail: 'speed pedelec, ≤45 km/h',
      osmKey: 'speed_pedelec',
    ),
    EbikeClass(label: 'Class B', detail: 'moped, ≤45 km/h', osmKey: 'moped'),
  ]),

  netherlands('Netherlands', [
    EbikeClass(
      label: 'Snorfiets',
      detail: 'mofa, ≤25 km/h',
      osmKey: 'electric_mofa',
      isSupported: true,
    ),
    EbikeClass(label: 'Bromfiets', detail: 'moped', osmKey: 'moped'),
  ]),

  canada('Canada', [
    EbikeClass(
      label: 'Pedal-assist',
      detail: '≤500 W, ≤32 km/h',
      osmKey: 'electric_bicycle',
      isSupported: true,
    ),
    EbikeClass(
      label: 'Pedal-assist with throttle',
      detail: 'throttle within the same cap',
      osmKey: 'electric_mofa',
      note: 'Canada permits a throttle within the pedal-assist cap.',
    ),
  ]),

  australia('Australia / NZ', [
    EbikeClass(
      label: 'EPAC',
      detail: '≤250 W, ≤25 km/h',
      osmKey: 'electric_bicycle',
      isSupported: true,
    ),
  ]),

  /// Everywhere Steward has no local vocabulary for. The pedelec rung is the
  /// one the whole table agrees on, so an unplaced trail still gets a picker
  /// that says something true.
  elsewhere('This trail', [
    EbikeClass(
      label: 'Pedelec',
      detail: 'pedal-assist',
      osmKey: 'electric_bicycle',
      isSupported: true,
    ),
  ]);

  const EbikeJurisdiction(this.label, this.classes);

  /// What to call the place, in the one line that names it.
  final String label;

  /// The ladder, lowest machine first.
  final List<EbikeClass> classes;

  /// The highest rung Steward is willing to write — the cap a rider actually
  /// picks. Never null: every jurisdiction's lowest rung is supported.
  EbikeClass get cap => classes.firstWhere((c) => c.isSupported);

  /// Every key any jurisdiction's [cap] writes, which is the set of keys
  /// Steward reads a trail's e-bike answer out of. Two, today.
  static Set<String> get capKeys => {
    for (final jurisdiction in values) jurisdiction.cap.osmKey,
  };

  /// The rungs the picker lists. All of them: a rider choosing "up to Class 1"
  /// should be able to see what Class 2 would have been, and that Steward
  /// won't write it yet.
  List<EbikeClass> get selectable => classes;
}

/// A `(west, south, east, north)` box, in degrees.
typedef _Box = (double, double, double, double);

/// Jurisdiction boxes, in the order they are tested.
///
/// Rectangles, not borders. That is a deliberate limit rather than an
/// unfinished one: the only thing this decides is which words the picker uses,
/// and every jurisdiction in the table writes the same `electric_bicycle` tag
/// for the rung Steward will write. Getting a trail on the Maine border
/// "wrong" costs a rider the phrase "pedal-assist" instead of "Class 1", and
/// costs OpenStreetMap nothing at all.
///
/// The first two entries are exceptions that would otherwise lose to the
/// Canadian boxes below them; the specific jurisdictions come before the
/// continental ones for the same reason.
const List<(EbikeJurisdiction, _Box)> _jurisdictionBoxes = [
  // New England and Michigan's Upper Peninsula reach north of the straight
  // stretch of the 49th parallel the Canadian boxes are drawn from.
  (EbikeJurisdiction.unitedStates, (-74.0, 42.0, -66.9, 47.6)),
  (EbikeJurisdiction.unitedStates, (-90.5, 45.0, -82.4, 48.4)),

  // The Low Countries interlock, and rectangles can't follow that border.
  // The Dutch box is split so Limburg stays Dutch without swallowing
  // Flanders, and Belgium takes what is left below it.
  (EbikeJurisdiction.netherlands, (3.3, 51.5, 7.3, 53.7)),
  (EbikeJurisdiction.netherlands, (5.6, 50.75, 6.3, 51.5)),
  (EbikeJurisdiction.belgium, (2.5, 49.4, 6.5, 51.6)),
  (EbikeJurisdiction.europe, (-25.0, 34.0, 45.0, 72.0)),

  (EbikeJurisdiction.canada, (-141.0, 49.0, -95.0, 84.0)),
  (EbikeJurisdiction.canada, (-95.0, 46.5, -52.0, 84.0)),

  // Everything else in North America, including Alaska, Hawaii and the US
  // Virgin Islands.
  (EbikeJurisdiction.unitedStates, (-172.0, 17.0, -52.0, 72.0)),

  (EbikeJurisdiction.australia, (110.0, -48.0, 180.0, -9.0)),
];

/// Which vocabulary a trail at `(lon, lat)` is standing in.
EbikeJurisdiction ebikeJurisdictionAt(double lon, double lat) {
  for (final (jurisdiction, (west, south, east, north)) in _jurisdictionBoxes) {
    if (lon >= west && lon <= east && lat >= south && lat <= north) {
      return jurisdiction;
    }
  }
  return EbikeJurisdiction.elsewhere;
}
