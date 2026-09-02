import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:slab_steward/src/analytics/analytics.dart';
import 'package:slab_steward/src/model/difficulty.dart';
import 'package:slab_steward/src/model/staged_edit.dart';
import 'package:slab_steward/src/model/trail.dart';
import 'package:slab_steward/src/osm/oauth_storage.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/osm/osm_auth.dart';
import 'package:slab_steward/src/osm/osm_environment.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/staged_changes.dart';

/// The instrumentation behind docs/specs/analytics.md §2.
///
/// These run against the io sink (analytics_stub.dart), which records instead
/// of sending — so what's asserted here is exactly what the web build would
/// hand PostHog, minus the network.

/// Every captured event's name, in order.
List<String> get _names => [for (final e in debugAnalyticsEvents) e.name];

/// The properties of the one event named [name]. Fails if it wasn't captured
/// exactly once, which is the point: a double-counted funnel step is the
/// failure mode that quietly ruins a conversion rate.
Map<String, Object?> _only(String name) {
  final matches = debugAnalyticsEvents.where((e) => e.name == name).toList();
  expect(matches, hasLength(1), reason: 'expected one $name in $_names');
  return matches.single.properties;
}

String _wayJson(int id) =>
    '{"elements":['
    '{"type":"node","id":${id * 10 + 1},"lat":47.5,"lon":-122.0},'
    '{"type":"node","id":${id * 10 + 2},"lat":47.51,"lon":-122.01},'
    '{"type":"way","id":$id,"version":7,'
    '"nodes":[${id * 10 + 1},${id * 10 + 2}],'
    '"tags":{"name":"Trail $id","highway":"path"}}]}';

/// Answers any way read, and the three changeset write calls.
OsmApi _api() => OsmApi(
  client: MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/changeset/create')) {
      return http.Response('999', 200);
    }
    if (path.endsWith('/upload')) {
      return http.Response('<diffResult version="0.6"/>', 200);
    }
    if (path.endsWith('/close')) return http.Response('', 200);
    final id = int.parse(
      RegExp(r'/way/(\d+)/full\.json').firstMatch(path)!.group(1)!,
    );
    return http.Response(_wayJson(id), 200);
  }),
);

OsmAuthState _signedIn() => OsmAuthState()
  ..debugSignIn(
    token: 'test-token',
    identity: const OsmIdentity(id: 7, displayName: 'Test Rider'),
  );

Trail _trail(int id) => Trail(
  osmWayId: id,
  tags: {'name': 'Trail $id'},
  isAuthoritative: true,
  version: 7,
);

void main() {
  PackageInfo.setMockInitialValues(
    appName: 'SLAB Steward',
    packageName: 'com.example.slab_steward',
    version: '0.1.0',
    buildNumber: '1',
    buildSignature: '',
  );

  // The sink is process-wide, so every test starts from an empty log.
  setUp(debugClearAnalytics);

  group('trail_selected', () {
    test('a plain click is one un-bulk selection', () async {
      final state = StewardState(osmApi: _api());
      await state.selectFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});

      expect(_only('trail_selected'), {'bulk': false, 'count': 1});
    });

    test('a box sweep is one event carrying how many it caught', () {
      StewardState(osmApi: _api()).addFromTiles([
        {'OSM_ID': 42, 'name': 'Gravy Train'},
        {'OSM_ID': 9, 'name': 'Bootcamp'},
      ]);

      expect(_only('trail_selected'), {'bulk': true, 'count': 2});
    });

    test('ctrl-clicking counts once, not once per code path', () async {
      final state = StewardState(osmApi: _api());
      // Seeds the trail without going through selectFromTile, so the only
      // selection here is the toggle itself.
      state.setVisibleTrails([
        {'OSM_ID': 42, 'name': 'Gravy Train'},
      ]);
      await state.toggleFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});

      // toggleFromTile delegates to setSelected; instrumenting both would
      // report two selections for one click.
      expect(_only('trail_selected'), {'bulk': false, 'count': 1});
    });

    test('clearing a selection is not a selection', () async {
      final state = StewardState(osmApi: _api());
      state.setVisibleTrails([
        {'OSM_ID': 42, 'name': 'Gravy Train'},
      ]);
      state.setSelection([42]);
      debugClearAnalytics();

      state.setSelection(const []);
      state.clearSelection();

      expect(_names, isEmpty);
    });
  });

  group('edit_staged', () {
    test('a bulk apply is one event over many trails, not many events', () {
      final state = StewardState(osmApi: _api());

      state.applyDifficulty([
        _trail(42),
        _trail(9),
        _trail(3),
      ], Difficulty.medium);

      expect(_only('edit_staged'), {
        'attribute': 'difficulty',
        'trail_count': 3,
      });
    });

    test('picking the value OSM already holds stages nothing, and says so', () {
      final state = StewardState(osmApi: _api());
      final rated = Trail(
        osmWayId: 42,
        tags: const {'name': 'Gravy Train', 'mtb:scale:imba': '2'},
        isAuthoritative: true,
        version: 7,
      );

      state.applyDifficulty([rated], Difficulty.medium);

      expect(_names, isEmpty);
    });

    test('a trail the API could not answer for stages nothing', () {
      final state = StewardState(osmApi: _api());
      final fromTile = Trail(
        osmWayId: 42,
        tags: const {'name': 'Gravy Train'},
        isAuthoritative: false,
        version: 7,
      );

      state.applyDifficulty([fromTile], Difficulty.medium);

      expect(_names, isEmpty);
    });
  });

  group('identity', () {
    test('a restored session identifies the rider it belongs to', () {
      writeStorage('osm_oauth_token', 'stored-token');
      writeStorage('osm_oauth_identity', '{"id":7,"displayName":"Test Rider"}');
      addTearDown(() {
        removeStorage('osm_oauth_token');
        removeStorage('osm_oauth_identity');
      });

      OsmAuthState().restoreSession();

      // The numeric id, never the display name.
      expect(_only('_identify'), {'distinct_id': '7'});
    });

    test(
      'signing out drops the identity rather than merging the next rider',
      () {
        _signedIn().signOut();

        expect(_names, contains('_reset'));
      },
    );
  });

  group('the submit path', () {
    Future<StewardState> pumpPanel(WidgetTester tester) async {
      final state = StewardState(
        osmApi: _api(),
        auth: _signedIn(),
        environment: OsmEnvironment.live,
      );
      state.stageEdit(StagedEdit.difficulty(_trail(42), Difficulty.medium));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => StagedChangesPanel(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      debugClearAnalytics();
      return state;
    }

    testWidgets('a generic comment reports which gate step stopped it', (
      tester,
    ) async {
      await pumpPanel(tester);

      await tester.enterText(find.byType(TextField), 'update');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit 1 change'));
      await tester.pumpAndSettle();

      expect(_only('submit_opened'), {'trail_count': 1});
      // The whole reason gate_failed carries a property.
      expect(_only('gate_failed'), {'check': 'comment'});
      expect(_names, isNot(contains('submit_succeeded')));
    });

    testWidgets('a real submission carries its changeset id', (tester) async {
      await pumpPanel(tester);

      await tester.enterText(
        find.byType(TextField),
        'Rated from a ride this weekend',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit 1 change'));
      await tester.pumpAndSettle();

      expect(_only('submit_succeeded'), {
        'trail_count': 1,
        'changeset_id': 999,
      });
      expect(_names, isNot(contains('gate_failed')));
    });
  });
}
