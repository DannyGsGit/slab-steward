import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/model/difficulty.dart';
import 'package:slab_steward/src/model/electric_bicycle.dart';
import 'package:slab_steward/src/model/surface.dart';
import 'package:slab_steward/src/model/trail.dart';

void main() {
  group('Difficulty', () {
    test('maps every IMBA scale value', () {
      expect(Difficulty.fromImba('0'), Difficulty.beginner);
      expect(Difficulty.fromImba('1'), Difficulty.easy);
      expect(Difficulty.fromImba('2'), Difficulty.medium);
      expect(Difficulty.fromImba('3'), Difficulty.difficult);
      expect(Difficulty.fromImba('4'), Difficulty.expert);
    });

    test('treats absent, blank and nonsense values as un-rated', () {
      expect(Difficulty.fromImba(null), Difficulty.unrated);
      expect(Difficulty.fromImba(''), Difficulty.unrated);
      expect(Difficulty.fromImba('7'), Difficulty.unrated);
      expect(Difficulty.fromImba('hard'), Difficulty.unrated);
    });

    test('un-rated writes no tag, so a completeness count stays honest', () {
      expect(Difficulty.unrated.imbaScale, isNull);
    });

    test('Pro Line writes 4 and keeps its distinction in Commons', () {
      expect(Difficulty.proLine.imbaScale, 4);
      expect(Difficulty.proLine.isCommonsOnly, isTrue);
      expect(Difficulty.expert.isCommonsOnly, isFalse);
    });
  });

  group('TrailSurface', () {
    test('maps SLAB options to OSM values', () {
      expect(TrailSurface.hardpack.osmValue, 'compacted');
      expect(TrailSurface.naturalDirt.osmValue, 'ground');
      expect(TrailSurface.rock.osmValue, 'rock');
    });

    test('reads common OSM synonyms back', () {
      expect(TrailSurface.fromOsm('dirt'), TrailSurface.naturalDirt);
      expect(TrailSurface.fromOsm('gravel'), TrailSurface.looseOverHard);
      expect(TrailSurface.fromOsm('asphalt'), TrailSurface.paved);
    });

    test('returns null for values the picker cannot express', () {
      // Real OSM values SLAB has no option for. Reporting these as "not set"
      // would be a lie, so the panel shows them read-only instead.
      expect(TrailSurface.fromOsm('woodchips'), isNull);
      expect(TrailSurface.fromOsm('mud'), isNull);
    });
  });

  group('EbikeAccess', () {
    test('offers yes and no, and nothing else', () {
      expect(EbikeAccess.values.map((a) => a.osmValue), ['yes', 'no']);
    });

    test('reads those values back', () {
      expect(EbikeAccess.fromOsm('yes'), EbikeAccess.allowed);
      expect(EbikeAccess.fromOsm(' no '), EbikeAccess.notAllowed);
    });

    test('returns null for access values the picker cannot express', () {
      // Real access values on real paths, including two Steward deliberately
      // doesn't offer. The panel shows these raw and read-only rather than
      // pretending nobody has answered — and never flattens them to "allowed".
      expect(EbikeAccess.fromOsm('designated'), isNull);
      expect(EbikeAccess.fromOsm('permissive'), isNull);
      expect(EbikeAccess.fromOsm('destination'), isNull);
      expect(EbikeAccess.fromOsm('use_sidepath'), isNull);
      expect(EbikeAccess.fromOsm(null), isNull);
      expect(EbikeAccess.fromOsm(''), isNull);
    });

    test('offers no "clear it" option — that would delete somebody\'s tag', () {
      expect(EbikeAccess.selectable, EbikeAccess.values);
      expect(
        EbikeAccess.selectable.map((a) => a.osmValue),
        isNot(contains(isEmpty)),
      );
    });
  });

  group('Trail e-bike access', () {
    Trail trailWith(Map<String, String> tags) =>
        Trail(osmWayId: 1, tags: tags, isAuthoritative: true);

    test('reads the tag through the picker vocabulary', () {
      final trail = trailWith({'electric_bicycle': 'no'});
      expect(trail.electricBicycle, EbikeAccess.notAllowed);
      expect(trail.hasElectricBicycle, isTrue);
      expect(trail.hasUnmappedElectricBicycle, isFalse);
    });

    test('keeps an unmapped value visible rather than calling it absent', () {
      final trail = trailWith({'electric_bicycle': 'destination'});
      expect(trail.electricBicycle, isNull);
      expect(trail.hasElectricBicycle, isTrue);
      expect(trail.hasUnmappedElectricBicycle, isTrue);
      expect(trail.rawElectricBicycle, 'destination');
    });

    test('a trail that says nothing about e-bikes is incomplete', () {
      final trail = trailWith({'mtb:scale:imba': '2', 'surface': 'ground'});
      expect(trail.hasElectricBicycle, isFalse);
      expect(trail.isComplete, isFalse);
      expect(
        trailWith({
          'mtb:scale:imba': '2',
          'surface': 'ground',
          'electric_bicycle': 'yes',
        }).isComplete,
        isTrue,
      );
    });
  });

  group('Trail.fromTileProperties', () {
    final props = <String, Object?>{
      'OSM_ID': 1182960573,
      'OSM_VERSION': 2,
      'OSM_TIMESTAMP': 1700000000,
      'MIN_LAT': 47.5,
      'MAX_LON': -121.9,
      'name': 'Gravy Train',
      'highway': 'path',
      'mtb:scale:imba': '3',
      'surface': 'ground',
      'electric_bicycle': 'no',
      'informal': 'yes',
    };

    test('keeps OSM tags and drops tileset bookkeeping columns', () {
      final trail = Trail.fromTileProperties(props);
      expect(trail.tags.keys, containsAll(['name', 'highway', 'surface']));
      expect(trail.tags.keys, isNot(contains('OSM_ID')));
      expect(trail.tags.keys, isNot(contains('MIN_LAT')));
    });

    test('reads through to the guided fields', () {
      final trail = Trail.fromTileProperties(props);
      expect(trail.name, 'Gravy Train');
      expect(trail.difficulty, Difficulty.difficult);
      expect(trail.surface, TrailSurface.naturalDirt);
      expect(trail.electricBicycle, EbikeAccess.notAllowed);
      expect(trail.isInformal, isTrue);
      expect(trail.isComplete, isTrue);
    });

    test('is never authoritative — tiles lag OSM', () {
      expect(Trail.fromTileProperties(props).isAuthoritative, isFalse);
    });

    test('becomes authoritative once the OSM API answers', () {
      final merged = Trail.fromTileProperties(props).mergeAuthoritative(
        tags: {'name': 'Gravy Train', 'mtb:scale:imba': '4'},
        version: 3,
        geometry: [
          [-122.0, 47.5],
          [-122.01, 47.51],
        ],
        nodeIds: [1, 2],
      );
      expect(merged.isAuthoritative, isTrue);
      expect(merged.version, 3);
      expect(merged.difficulty, Difficulty.expert);
      // Tags are replaced wholesale, not merged — a tag deleted in OSM must
      // not survive from the stale tile copy.
      expect(merged.surface, isNull);
    });
  });
}
