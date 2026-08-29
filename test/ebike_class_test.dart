import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slab_steward/src/model/ebike_class.dart';
import 'package:slab_steward/src/model/electric_bicycle.dart';
import 'package:slab_steward/src/model/lens.dart';
import 'package:slab_steward/src/model/staged_edit.dart';
import 'package:slab_steward/src/model/trail.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/trail_panel.dart';

/// A way in Bend, Oregon — Class 1 country.
String _wayJson({double lon = -121.31, double lat = 44.05}) =>
    '{"elements":['
    '{"type":"node","id":1,"lat":$lat,"lon":$lon},'
    '{"type":"node","id":2,"lat":${lat + 0.01},"lon":${lon + 0.01}},'
    '{"type":"way","id":42,"version":7,"nodes":[1,2],"tags":'
    '{"name":"Phil\'s Trail","highway":"path"}}'
    ']}';

StewardState _stateServing(String body) => StewardState(
  osmApi: OsmApi(client: MockClient((_) async => http.Response(body, 200))),
);

void main() {
  group('where a trail is', () {
    test('places the jurisdictions the mapping sheet covers', () {
      // Bend, Bergamo, Amsterdam, Brussels, Squamish, Sydney.
      expect(
        ebikeJurisdictionAt(-121.31, 44.05),
        EbikeJurisdiction.unitedStates,
      );
      expect(ebikeJurisdictionAt(9.67, 45.69), EbikeJurisdiction.europe);
      expect(ebikeJurisdictionAt(4.90, 52.37), EbikeJurisdiction.netherlands);
      expect(ebikeJurisdictionAt(4.35, 50.85), EbikeJurisdiction.belgium);
      expect(ebikeJurisdictionAt(-123.15, 49.70), EbikeJurisdiction.canada);
      expect(ebikeJurisdictionAt(151.21, -33.87), EbikeJurisdiction.australia);
    });

    test('falls back to the dialect every jurisdiction shares', () {
      // Mid-Atlantic: no vocabulary of its own, and no reason to guess one.
      expect(ebikeJurisdictionAt(-40.0, 25.0), EbikeJurisdiction.elsewhere);
      expect(EbikeJurisdiction.elsewhere.cap.osmKey, 'electric_bicycle');
    });

    test('a trail is placed by its tile bounds before OSM answers', () {
      final trail = Trail.fromTileProperties({
        'OSM_ID': 1,
        'MIN_LON': 11.0,
        'MAX_LON': 11.2,
        'MIN_LAT': 46.0,
        'MAX_LAT': 46.2,
        'highway': 'path',
      });
      expect(trail.isAuthoritative, isFalse);
      expect(trail.ebikeJurisdiction, EbikeJurisdiction.europe);
      expect(
        trail.tags.keys,
        isNot(contains('MIN_LON')),
        reason: 'the bounds are tileset bookkeeping, not an OSM tag',
      );
    });

    test('and by its real geometry once it has some', () {
      final trail = Trail(
        osmWayId: 1,
        tags: const {},
        isAuthoritative: true,
        geometry: const [
          [-121.31, 44.05],
          [-121.30, 44.06],
        ],
      );
      expect(trail.ebikeJurisdiction, EbikeJurisdiction.unitedStates);
    });
  });

  group('the ladder', () {
    test('every jurisdiction caps at the lowest class its law recognises', () {
      for (final jurisdiction in EbikeJurisdiction.values) {
        expect(
          jurisdiction.classes.first,
          jurisdiction.cap,
          reason: '${jurisdiction.name} writes its bottom rung and no more',
        );
      }
      // A pedelec almost everywhere...
      for (final jurisdiction in [
        EbikeJurisdiction.unitedStates,
        EbikeJurisdiction.europe,
        EbikeJurisdiction.canada,
        EbikeJurisdiction.australia,
        EbikeJurisdiction.elsewhere,
      ]) {
        expect(jurisdiction.cap.osmKey, 'electric_bicycle');
      }
      // ...but not in the Low Countries, where a pedelec is legally a bicycle
      // and the lowest class actually put on a path is the mofa.
      expect(EbikeJurisdiction.belgium.cap.label, 'Class A');
      expect(EbikeJurisdiction.belgium.cap.osmKey, 'electric_mofa');
      expect(EbikeJurisdiction.netherlands.cap.label, 'Snorfiets');
      expect(EbikeJurisdiction.netherlands.cap.osmKey, 'electric_mofa');
      expect(
        [
          for (final j in [
            EbikeJurisdiction.belgium,
            EbikeJurisdiction.netherlands,
          ])
            ...j.classes.map((c) => c.label),
        ],
        isNot(contains('Pedelec')),
        reason: 'the pedelec rung is not theirs to offer',
      );
    });

    test('the lens asks about every key a cap can write', () {
      // The lens spells its keys out — an enum's arguments have to be const —
      // so this is what keeps the two from drifting apart.
      expect(Lens.electricBicycle.keys.toSet(), EbikeJurisdiction.capKeys);
    });

    test('and offers nothing above it — for now', () {
      for (final jurisdiction in EbikeJurisdiction.values) {
        expect(
          jurisdiction.classes.where((c) => c.isSupported),
          hasLength(1),
          reason: 'Steward writes one rung, and shows the rest disabled',
        );
      }
      // The rungs above are real, and named, so the picker can show what it
      // is leaving alone.
      expect(EbikeJurisdiction.unitedStates.classes.map((c) => c.label), [
        'Class 1',
        'Class 2',
        'Class 3 pedal-assist',
        'Class 3 throttle',
      ]);
      expect(EbikeJurisdiction.europe.classes.map((c) => c.label), [
        'Pedelec',
        'S-pedelec',
      ]);
    });
  });

  group('staging with a cap', () {
    Trail trailIn(double lon, double lat) => Trail(
      osmWayId: 42,
      tags: const {'name': 'Gravy Train'},
      isAuthoritative: true,
      version: 7,
      geometry: [
        [lon, lat],
      ],
    );

    test('says the same thing to OSM wherever the rider is standing', () {
      final oregon = StagedEdit.electricBicycle(
        trailIn(-121.31, 44.05),
        EbikeAccess.allowed,
      );
      final italy = StagedEdit.electricBicycle(
        trailIn(9.67, 45.69),
        EbikeAccess.allowed,
      );

      expect(oregon.tagChanges, {'electric_bicycle': 'yes'});
      expect(italy.tagChanges, {'electric_bicycle': 'yes'});
      // Except in the Low Countries, where the bottom class is a mofa.
      expect(
        StagedEdit.electricBicycle(
          trailIn(4.90, 52.37),
          EbikeAccess.allowed,
        ).tagChanges,
        {'electric_mofa': 'yes'},
      );
      // The words differ, because the sign at the trailhead does.
      expect(oregon.summary, 'Not recorded → Allowed up to Class 1');
      expect(italy.summary, 'Not recorded → Allowed up to Pedelec');
    });

    test('a cap is not a ban on everything above it', () {
      final edit = StagedEdit.electricBicycle(
        trailIn(-121.31, 44.05),
        EbikeAccess.allowed,
      );
      // electric_mofa, speed_pedelec and motorcycle are the rungs above
      // Class 1 in the US. Steward says nothing about any of them: "up to
      // Class 1 may ride" is what the rider answered, and a ban on
      // motorcycles is not.
      expect(edit.tagChanges.keys, ['electric_bicycle']);
    });

    test('"not allowed" carries no class at all', () {
      final edit = StagedEdit.electricBicycle(
        trailIn(-121.31, 44.05),
        EbikeAccess.notAllowed,
      );
      expect(edit.summary, 'Not recorded → Not allowed');
      expect(edit.tagChanges, {'electric_bicycle': 'no'});
    });
  });

  group('the panel', () {
    testWidgets('asks for a cap once a trail is open to e-bikes, in the '
        'local vocabulary', (tester) async {
      final state = _stateServing(_wayJson());
      addTearDown(state.dispose);
      await state.selectFromTile({'OSM_ID': 42, 'name': "Phil's Trail"});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => TrailPanel(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing is recorded yet, so there is no class to cap.
      expect(find.text('UP TO'), findsNothing);

      await tester.tap(find.byType(DropdownButton<EbikeAccess>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allowed').last);
      await tester.pumpAndSettle();

      expect(find.text('UP TO'), findsOneWidget);
      expect(find.text(EbikeJurisdiction.unitedStates.label), findsOneWidget);
      expect(find.text('Class 1'), findsOneWidget);
      expect(
        find.text('pedal-assist, ≤20 mph'),
        findsOneWidget,
        reason: 'the class picker is what says which machine',
      );
      expect(
        find.textContaining('the same as any other bike'),
        findsOneWidget,
        reason: 'and the access picker keeps saying what allowed claims',
      );
      expect(
        find.textContaining('E-bikes up to'),
        findsNothing,
        reason: 'the allowed field says nothing about a class',
      );
      expect(state.stagedEdits.single.tagChanges, {'electric_bicycle': 'yes'});
    });

    testWidgets('the rungs Steward will not write are shown, and disabled', (
      tester,
    ) async {
      final state = _stateServing(_wayJson());
      addTearDown(state.dispose);
      await state.selectFromTile({'OSM_ID': 42, 'name': "Phil's Trail"});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => TrailPanel(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<EbikeAccess>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allowed').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<EbikeClass>));
      await tester.pumpAndSettle();

      expect(find.text('Class 2'), findsOneWidget);
      final classTwo = tester.widget<DropdownMenuItem<EbikeClass>>(
        find.ancestor(
          of: find.text('Class 2'),
          matching: find.byType(DropdownMenuItem<EbikeClass>),
        ),
      );
      expect(classTwo.enabled, isFalse);
      expect(find.textContaining('writes electric_mofa'), findsOneWidget);
    });
  });
}
