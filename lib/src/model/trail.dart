import '../osm/osm_environment.dart';
import 'difficulty.dart';
import 'ebike_class.dart';
import 'electric_bicycle.dart';
import 'surface.dart';

/// A trail as Steward knows it.
///
/// Two sources feed this, and the difference matters. Tile properties are fast
/// but can lag OSM by hours, so they're fine for drawing and for showing a
/// panel immediately. Anything the editor will write against has to come from
/// the OSM API — that's where [version] and [tags] come from, and a changeset
/// built on a stale version is how you clobber someone else's edit.
class Trail {
  const Trail({
    required this.osmWayId,
    required this.tags,
    required this.isAuthoritative,
    this.version,
    this.geometry,
    this.nodeIds,
    this.tileCenter,
  });

  /// Built from what the vector tile carried. Provisional by definition.
  ///
  /// [props] is the tile's attributes with the OSM way id filed in under
  /// `OSM_ID` — the tileset publishes identity as the MVT feature id now, so
  /// the map view splices it back in; see `otm_conventions.dart`. The same
  /// build dropped `OSM_VERSION` and the bounds columns, so [version] and
  /// [tileCenter] are usually null until the OSM API answers. Both are still
  /// read here: they cost nothing, and the columns may come back.
  factory Trail.fromTileProperties(Map<String, Object?> props) {
    final tags = <String, String>{};
    for (final entry in props.entries) {
      // Tileset bookkeeping columns aren't OSM tags.
      if (entry.key.startsWith('OSM_') || _tileOnlyKeys.contains(entry.key)) {
        continue;
      }
      final value = entry.value;
      if (value != null) tags[entry.key] = value.toString();
    }
    return Trail(
      osmWayId: (props['OSM_ID'] as num).toInt(),
      tags: tags,
      isAuthoritative: false,
      version: (props['OSM_VERSION'] as num?)?.toInt(),
      tileCenter: _boundsCenter(props),
    );
  }

  /// The middle of the bounding box the tileset publishes for a feature, as
  /// `[lon, lat]`. Not an OSM tag and never edited — it is here so a trail
  /// knows roughly where it is before the OSM API has answered with real
  /// geometry, which is all [ebikeJurisdiction] needs.
  static List<double>? _boundsCenter(Map<String, Object?> props) {
    final values = [
      for (final key in ['MIN_LON', 'MAX_LON', 'MIN_LAT', 'MAX_LAT'])
        props[key],
    ];
    if (values.any((v) => v is! num)) return null;
    final [minLon, maxLon, minLat, maxLat] = values.cast<num>();
    return [(minLon + maxLon) / 2, (minLat + maxLat) / 2];
  }

  static const _tileOnlyKeys = {'MIN_LAT', 'MAX_LAT', 'MIN_LON', 'MAX_LON'};

  final int osmWayId;

  /// Raw OSM tags. Never shown to the user as keys — the guided editor reads
  /// them through [difficulty] and [surface] instead.
  final Map<String, String> tags;

  /// True once these tags came from the OSM API rather than from a tile.
  /// The editor refuses to submit against anything else.
  final bool isAuthoritative;

  /// OSM element version, needed to upload a changeset without clobbering.
  final int? version;

  /// `[[lon, lat], ...]` in OSM node order, when it has been fetched.
  final List<List<double>>? geometry;

  /// The way's member node IDs, in the same order as [geometry]. Needed to
  /// round-trip a way through a changeset upload without truncating it.
  final List<int>? nodeIds;

  /// Where the tileset says this trail is, as `[lon, lat]`. Kept across a
  /// merge so a trail placed from a tile stays placed.
  final List<double>? tileCenter;

  /// Roughly where the trail is, as `[lon, lat]` — real geometry once the OSM
  /// API has answered, the tile's bounding box before that, and null for a
  /// trail Steward has no position for at all.
  List<double>? get center {
    final shape = geometry;
    if (shape != null && shape.isNotEmpty) return shape[shape.length ~/ 2];
    return tileCenter;
  }

  /// Whose e-bike vocabulary this trail is standing in. Trails Steward can't
  /// place fall back to [EbikeJurisdiction.elsewhere], which speaks the one
  /// dialect every jurisdiction shares.
  EbikeJurisdiction get ebikeJurisdiction => switch (center) {
    [final lon, final lat] => ebikeJurisdictionAt(lon, lat),
    _ => EbikeJurisdiction.elsewhere,
  };

  String? get name => tags['name'] ?? tags['mtb:name'];

  Difficulty get difficulty => Difficulty.fromImba(tags[Difficulty.osmKey]);

  bool get hasDifficulty => tags.containsKey(Difficulty.osmKey);

  String? get rawSurface => tags['surface'];

  TrailSurface? get surface => TrailSurface.fromOsm(rawSurface);

  /// A surface OSM knows about but SLAB's picker can't express — shown
  /// read-only rather than silently reported as missing.
  bool get hasUnmappedSurface => rawSurface != null && surface == null;

  /// The OSM key that carries this trail's e-bike answer.
  ///
  /// Local, because the machine a rider is asking about is local: a pedelec
  /// rides under `electric_bicycle` almost everywhere, but the lowest class
  /// Belgium and the Netherlands put on a path is a mofa, which rides under
  /// `electric_mofa`. See [EbikeJurisdiction].
  String get electricBicycleKey => ebikeJurisdiction.cap.osmKey;

  String? get rawElectricBicycle => tags[electricBicycleKey];

  EbikeAccess? get electricBicycle => EbikeAccess.fromOsm(rawElectricBicycle);

  /// Whether OSM says anything at all about e-bikes here.
  bool get hasElectricBicycle => tags.containsKey(electricBicycleKey);

  /// An access value OSM knows about but SLAB's picker can't express — shown
  /// read-only, the same as an unmapped surface.
  bool get hasUnmappedElectricBicycle =>
      rawElectricBicycle != null && electricBicycle == null;

  bool get isInformal => tags['informal'] == 'yes';

  /// Complete in the sense all three attribute lenses together mean it: every
  /// attribute Steward can write has an answer.
  bool get isComplete =>
      hasDifficulty && rawSurface != null && hasElectricBicycle;

  /// Built from [osmWebHost], not the API host: `/way/{id}` is served by the
  /// website, and the two are different machines.
  String get osmUrl => '$osmWebHost/way/$osmWayId';

  Trail mergeAuthoritative({
    required Map<String, String> tags,
    required int version,
    required List<List<double>> geometry,
    required List<int> nodeIds,
  }) => Trail(
    osmWayId: osmWayId,
    tags: tags,
    isAuthoritative: true,
    version: version,
    geometry: geometry,
    nodeIds: nodeIds,
    tileCenter: tileCenter,
  );
}
