import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slab_steward/src/model/difficulty.dart';
import 'package:slab_steward/src/model/staged_edit.dart';
import 'package:slab_steward/src/model/trail.dart';
import 'package:slab_steward/src/model/trail_overrides.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/state/steward_state.dart';

/// Answers any way read with [tags], so a test can say what OSM currently
/// holds without spelling out a full response.
MockClient _osmReturning(Map<String, String> tags) => MockClient((
  request,
) async {
  final id = int.parse(
    RegExp(r'/way/(\d+)/full\.json').firstMatch(request.url.path)!.group(1)!,
  );
  final pairs = tags.entries.map((e) => '"${e.key}":"${e.value}"').join(',');
  return http.Response(
    '{"elements":['
    '{"type":"node","id":1,"lat":47.5,"lon":-122.0},'
    '{"type":"node","id":2,"lat":47.51,"lon":-122.01},'
    '{"type":"way","id":$id,"version":9,"nodes":[1,2],"tags":{$pairs}}'
    ']}',
    200,
  );
});

void main() {
  setUp(() {
    // Off the web the storage stub is one map for the whole process, so
    // without this a state built in the next test loads this one's cache.
    TrailOverrides().clear();
  });

  group('TrailOverrides', () {
    test('a later observation supersedes an earlier one', () {
      final overrides = TrailOverrides();
      final t0 = DateTime.utc(2026, 8, 20);
      overrides.record(
        1,
        {'surface': 'dirt'},
        source: OverrideSource.submitted,
        observedAt: t0,
      );
      overrides.record(
        1,
        {'surface': 'gravel'},
        source: OverrideSource.read,
        observedAt: t0.add(const Duration(hours: 1)),
      );
      expect(overrides[1]!.tags['surface'], 'gravel');
      expect(overrides[1]!.source, OverrideSource.read);
    });

    test('an older observation never overwrites a newer one', () {
      // A slow read landing after a submit must not resurrect the pre-edit
      // tags — the whole cache would flicker backwards.
      final overrides = TrailOverrides();
      final now = DateTime.utc(2026, 8, 20, 12);
      overrides.record(
        1,
        {'mtb:scale:imba': '4'},
        source: OverrideSource.submitted,
        observedAt: now,
      );
      overrides.record(
        1,
        {},
        source: OverrideSource.read,
        observedAt: now.subtract(const Duration(minutes: 5)),
      );
      expect(overrides[1]!.tags, {'mtb:scale:imba': '4'});
    });

    test('re-recording identical tags does not restyle the map', () {
      var changes = 0;
      final overrides = TrailOverrides(onChanged: () => changes++);
      overrides.record(1, {'surface': 'dirt'}, source: OverrideSource.read);
      overrides.record(1, {'surface': 'dirt'}, source: OverrideSource.read);
      expect(changes, 1, reason: 'clicking the same trail twice is not news');
    });

    test(
      'pruning drops what the tileset has caught up with, and nothing else',
      () {
        final overrides = TrailOverrides();
        final build = DateTime.utc(2026, 8, 17, 19);
        overrides.record(
          1,
          {'surface': 'dirt'},
          source: OverrideSource.read,
          observedAt: build.subtract(const Duration(days: 1)),
        );
        overrides.record(
          2,
          {'surface': 'gravel'},
          source: OverrideSource.read,
          observedAt: build.add(const Duration(days: 1)),
        );

        overrides.pruneObservedBefore(build);

        expect(
          overrides[1],
          isNull,
          reason: 'the tiles now say this themselves',
        );
        expect(overrides[2], isNotNull);
      },
    );
  });

  group('what feeds the cache', () {
    test('an authoritative read records what OSM currently holds', () async {
      final state = StewardState(
        osmApi: OsmApi(client: _osmReturning({'surface': 'gravel'})),
      );
      addTearDown(state.dispose);
      await state.selectFromTile({'OSM_ID': 42, 'OSM_VERSION': 7});

      expect(state.overrides[42]!.tags['surface'], 'gravel');
      expect(state.overrides[42]!.source, OverrideSource.read);
    });

    test('a read that only repeats the tiles is not cached', () async {
      // The API returns every tag; a tile carries a subset. Treating that as
      // a contradiction would cache — and restyle the map for — every single
      // first click, which is most clicks.
      final state = StewardState(
        osmApi: OsmApi(
          client: _osmReturning({
            'highway': 'path',
            'surface': 'gravel',
            'source': 'survey;gps',
            'check_date': '2026-05-01',
          }),
        ),
      );
      addTearDown(state.dispose);
      await state.selectFromTile({
        'OSM_ID': 42,
        'OSM_VERSION': 7,
        'highway': 'path',
        'surface': 'gravel',
      });

      expect(state.overrides[42], isNull);
      expect(state.styleRevision, 0, reason: 'nothing to restyle for');
    });

    test('a submitted edit is folded in as the staging area empties', () async {
      final state = StewardState(
        osmApi: OsmApi(client: _osmReturning({'surface': 'dirt'})),
      );
      addTearDown(state.dispose);
      final trail = Trail(
        osmWayId: 42,
        tags: const {'highway': 'path', 'surface': 'dirt'},
        isAuthoritative: true,
        version: 9,
      );
      state.stageEdit(StagedEdit.difficulty(trail, Difficulty.expert));

      final styleBefore = state.styleRevision;
      state.applySubmitted();

      expect(state.hasStagedEdits, isFalse);
      expect(state.overrides[42]!.source, OverrideSource.submitted);
      expect(
        state.overrides[42]!.tags,
        containsPair(Difficulty.osmKey, Difficulty.expert.imbaScale.toString()),
      );
      expect(
        state.overrides[42]!.tags,
        containsPair('surface', 'dirt'),
        reason: 'the tags it was not editing have to survive the fold',
      );
      expect(
        state.styleRevision,
        greaterThan(styleBefore),
        reason: 'the map has to restyle or the trail stays the old colour',
      );
    });

    test('the override is keyed by the id the tiles use', () async {
      // The style expressions match on the tile feature's own id, so keying
      // by anything else means the filter matches nothing at all.
      final state = StewardState(
        osmApi: OsmApi(client: _osmReturning({'surface': 'gravel'})),
      );
      addTearDown(state.dispose);
      await state.selectFromTile({'OSM_ID': 9001, 'OSM_VERSION': 7});

      expect(state.overrides[9001], isNotNull);
    });
  });
}
