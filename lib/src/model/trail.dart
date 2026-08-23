import 'difficulty.dart';
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
  });

  /// Built from what the vector tile carried. Provisional by definition.
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
    );
  }

  static const _tileOnlyKeys = {
    'MIN_LAT', 'MAX_LAT', 'MIN_LON', 'MAX_LON',
  };

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

  String? get name => tags['name'] ?? tags['mtb:name'];

  Difficulty get difficulty => Difficulty.fromImba(tags[Difficulty.osmKey]);

  bool get hasDifficulty => tags.containsKey(Difficulty.osmKey);

  String? get rawSurface => tags['surface'];

  TrailSurface? get surface => TrailSurface.fromOsm(rawSurface);

  /// A surface OSM knows about but SLAB's picker can't express — shown
  /// read-only rather than silently reported as missing.
  bool get hasUnmappedSurface => rawSurface != null && surface == null;

  bool get isInformal => tags['informal'] == 'yes';

  /// Complete in the sense the completeness lens means it.
  bool get isComplete => hasDifficulty && rawSurface != null;

  String get osmUrl => 'https://www.openstreetmap.org/way/$osmWayId';

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
  );

  Map<String, Object?> toGeoJsonFeature() => {
    'type': 'Feature',
    'properties': {'osmWayId': osmWayId},
    'geometry': {'type': 'LineString', 'coordinates': geometry ?? const []},
  };
}
