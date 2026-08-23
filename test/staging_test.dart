import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:slab_steward/src/model/difficulty.dart';
import 'package:slab_steward/src/model/staged_edit.dart';
import 'package:slab_steward/src/model/trail.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/staged_changes.dart';
import 'package:slab_steward/src/ui/trail_panel.dart';

Trail _trail({Map<String, String> tags = const {}, bool authoritative = true}) =>
    Trail(
      osmWayId: 42,
      tags: {'name': 'Gravy Train', ...tags},
      isAuthoritative: authoritative,
      version: 7,
    );

/// The `/full.json` shape [OsmApi.fetchWay] parses, for one two-node way.
String _wayJson(Map<String, String> tags) =>
    '{"elements":['
    '{"type":"node","id":1,"lat":47.5,"lon":-122.0},'
    '{"type":"node","id":2,"lat":47.51,"lon":-122.01},'
    '{"type":"way","id":42,"version":7,"nodes":[1,2],"tags":'
    '{${tags.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}}'
    ']}';

StewardState _stateServing(String body, {int status = 200}) => StewardState(
  osmApi: OsmApi(
    client: MockClient((_) async => http.Response(body, status)),
  ),
);

/// The `/full.json` shape [OsmApi.fetchWay] parses, for an arbitrary way id
/// with its own two-node geometry.
String _wayJsonFor(int id, int version, Map<String, String> tags) =>
    '{"elements":['
    '{"type":"node","id":${id * 10 + 1},"lat":47.5,"lon":-122.0},'
    '{"type":"node","id":${id * 10 + 2},"lat":47.51,"lon":-122.01},'
    '{"type":"way","id":$id,"version":$version,"nodes":[${id * 10 + 1},${id * 10 + 2}],"tags":'
    '{${tags.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}}'
    ']}';

/// An [OsmApi] that answers a fixed set of ways, keyed by id — for exercising
/// the submission gate's fetch step against more than one trail at once.
OsmApi _multiWayApi(Map<int, (int version, Map<String, String> tags)> ways) =>
    OsmApi(
      client: MockClient((request) async {
        final match = RegExp(r'/way/(\d+)/full\.json').firstMatch(request.url.path);
        final id = int.parse(match!.group(1)!);
        final entry = ways[id];
        if (entry == null) return http.Response('not found', 404);
        return http.Response(_wayJsonFor(id, entry.$1, entry.$2), 200);
      }),
    );

void main() {
  group('StagedEdit.difficulty', () {
    test('diffs the tag against what the trail actually has', () {
      final edit = StagedEdit.difficulty(_trail(), Difficulty.medium);
      expect(edit.tagChanges, {'mtb:scale:imba': '2'});
      expect(edit.changesOsm, isTrue);
      expect(edit.fromLabel, 'Not rated');
      expect(edit.toLabel, 'Medium');
      expect(edit.baseVersion, 7);
    });

    test('carries the plain-language and raw-tag halves of the preview', () {
      final edit = StagedEdit.difficulty(
        _trail(tags: {'mtb:scale:imba': '1'}),
        Difficulty.difficult,
      );
      expect(edit.summary, 'Easy → Difficult');
      expect(edit.tagDiffLines, ['mtb:scale:imba=3']);
    });

    test('Pro Line over Expert changes nothing in OSM, and says so', () {
      final edit = StagedEdit.difficulty(
        _trail(tags: {'mtb:scale:imba': '4'}),
        Difficulty.proLine,
      );
      expect(edit.tagChanges, isEmpty);
      expect(edit.changesOsm, isFalse);
      expect(edit.note, contains('Commons'));
    });

    test('the picker never offers un-rated, which would delete a rating', () {
      expect(Difficulty.selectable, isNot(contains(Difficulty.unrated)));
      expect(Difficulty.selectable, hasLength(Difficulty.values.length - 1));
    });
  });

  group('StewardState staging', () {
    test('one pending change per attribute, however many times it is set', () {
      final state = StewardState();
      final trail = _trail();
      state.stageEdit(StagedEdit.difficulty(trail, Difficulty.easy));
      state.stageEdit(StagedEdit.difficulty(trail, Difficulty.expert));

      expect(state.stagedEditCount, 1);
      expect(
        state.stagedEditFor(42, TrailAttribute.difficulty)?.toLabel,
        'Expert',
      );
    });

    test('groups by trail in staging order', () {
      final state = StewardState();
      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.easy));
      state.stageEdit(
        StagedEdit.difficulty(
          Trail(osmWayId: 9, tags: const {}, isAuthoritative: true),
          Difficulty.medium,
        ),
      );

      expect(state.stagedEditsByTrail.keys, [42, 9]);
      expect(state.stagedEditsByTrail[42], hasLength(1));
    });

    test('a staged trail keeps its shape after the rider clicks away', () {
      final state = StewardState();
      final trail = Trail(
        osmWayId: 42,
        tags: const {'name': 'Gravy Train'},
        isAuthoritative: true,
        version: 7,
        geometry: const [
          [-122.0, 47.5],
          [-122.0, 47.6],
        ],
      );
      state.stageEdit(StagedEdit.difficulty(trail, Difficulty.medium));
      state.clearSelection();

      final staged = state.stagedTrails.single;
      expect(staged.osmWayId, 42);
      expect(staged.difficulty, Difficulty.medium);
      // The glow follows the geometry captured at staging time.
      final feature = staged.toGeoJsonFeature()!;
      expect((feature['geometry']! as Map)['coordinates'], hasLength(2));
      // The badge sits halfway along it.
      expect(staged.badgePoint, [-122.0, closeTo(47.55, 1e-9)]);
    });

    test('a trail staged before the API answered glows nowhere', () {
      final state = StewardState();
      // No geometry: the panel gates editing on authoritative tags, so this
      // shouldn't happen — but a missing shape must not crash the map.
      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.easy));

      final staged = state.stagedTrails.single;
      expect(staged.toGeoJsonFeature(), isNull);
      expect(staged.badgePoint, isNull);
      expect(staged.difficulty, Difficulty.easy);
    });

    test('the staged revision moves only when the staged set changes', () {
      final state = StewardState();
      final start = state.stagedRevision;
      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.easy));
      expect(state.stagedRevision, start + 1);

      // Re-staging the same attribute replaces one edit with another — the
      // list length is unchanged, but the map has to redraw.
      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.expert));
      expect(state.stagedRevision, start + 2);

      state.unstageEdit(99, TrailAttribute.difficulty);
      expect(state.stagedRevision, start + 2, reason: 'nothing was staged for 99');
    });

    test('notifies on stage, unstage and clear — and not on a no-op', () {
      final state = StewardState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.easy));
      expect(notifications, 1);

      state.unstageEdit(999, TrailAttribute.difficulty);
      expect(notifications, 1, reason: 'nothing staged for way 999');

      state.unstageEdit(42, TrailAttribute.difficulty);
      expect(notifications, 2);
      expect(state.hasStagedEdits, isFalse);

      state.clearStagedEdits();
      expect(notifications, 2, reason: 'already empty');
    });

    test('unstageTrail drops every change to one trail', () {
      final state = StewardState();
      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.easy));
      state.stageEdit(
        StagedEdit.difficulty(
          Trail(osmWayId: 9, tags: const {}, isAuthoritative: true),
          Difficulty.medium,
        ),
      );

      state.unstageTrail(42);
      expect(state.stagedEditsByTrail.keys, [9]);
    });

    test('a passed gate finalizes and clears the list', () async {
      final state = _stateServing(_wayJson({}));
      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.easy));
      final gate = state.createSubmissionGate();
      final passed = await gate.run(
        comment: 'Rated from a ride',
        trails: state.stagedTrails,
      );
      expect(passed, isTrue);
      state.finalizeSubmission(gate: gate, requestReview: false);
      expect(state.hasStagedEdits, isFalse);
    });
  });

  group('TrailPanel difficulty editor', () {
    Future<StewardState> pumpSelected(
      WidgetTester tester, {
      required String body,
      int status = 200,
    }) async {
      final state = _stateServing(body, status: status);
      addTearDown(state.dispose);
      await state.selectFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => Stack(
                children: [
                  StagedChangesButton(state: state),
                  Align(
                    alignment: Alignment.topRight,
                    child: TrailPanel(state: state),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return state;
    }

    testWidgets('pencil → dropdown → check stages the change', (tester) async {
      final state = await pumpSelected(tester, body: _wayJson({}));

      expect(find.text('Not rated yet'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit difficulty'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<Difficulty>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medium').last);
      await tester.pumpAndSettle();

      // Staging is explicit: picking a value alone changes nothing.
      expect(state.hasStagedEdits, isFalse);

      await tester.tap(find.byTooltip('Stage this change'));
      await tester.pumpAndSettle();

      expect(state.stagedEditCount, 1);
      expect(
        state.stagedEditFor(42, TrailAttribute.difficulty)?.tagChanges,
        {'mtb:scale:imba': '2'},
      );
      // The panel shows the pending value, flagged as pending, and the map
      // overlay picks up a count.
      expect(find.text('STAGED'), findsOneWidget);
      expect(find.text('Was not rated'), findsOneWidget);
      expect(find.text('Review 1 change'), findsOneWidget);
    });

    testWidgets('the X discards without staging', (tester) async {
      final state = await pumpSelected(tester, body: _wayJson({}));

      await tester.tap(find.byTooltip('Edit difficulty'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<Difficulty>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Easy').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Discard'));
      await tester.pumpAndSettle();

      expect(state.hasStagedEdits, isFalse);
      expect(find.text('Not rated yet'), findsOneWidget);
    });

    testWidgets('re-picking the value OSM already has clears the stage', (
      tester,
    ) async {
      final state = await pumpSelected(
        tester,
        body: _wayJson({'mtb:scale:imba': '1'}),
      );

      state.stageEdit(
        StagedEdit.difficulty(state.selected!, Difficulty.expert),
      );
      await tester.pumpAndSettle();
      expect(find.text('STAGED'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit difficulty'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<Difficulty>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Easy').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stage this change'));
      await tester.pumpAndSettle();

      expect(state.hasStagedEdits, isFalse);
    });

    testWidgets('cannot edit against tile data the API could not confirm', (
      tester,
    ) async {
      await pumpSelected(tester, body: 'nope', status: 500);

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.edit_outlined),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('StagedChangesDialog', () {
    Future<StewardState> pumpDialog(
      WidgetTester tester, {
      OsmApi? osmApi,
    }) async {
      final state = StewardState(osmApi: osmApi);
      addTearDown(state.dispose);
      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.medium));
      state.stageEdit(
        StagedEdit.difficulty(
          Trail(
            osmWayId: 9,
            tags: const {'name': 'Bootcamp'},
            isAuthoritative: true,
            version: 2,
          ),
          Difficulty.expert,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: StagedChangesDialog(state: state))),
      );
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('lists the changes by trail', (tester) async {
      await pumpDialog(tester);

      expect(find.text('Gravy Train'), findsOneWidget);
      expect(find.text('Bootcamp'), findsOneWidget);
      expect(find.text('Difficulty: Not rated → Medium'), findsOneWidget);
      expect(find.text('mtb:scale:imba=4'), findsOneWidget);
    });

    testWidgets('submit needs a description', (tester) async {
      final state = await pumpDialog(
        tester,
        osmApi: _multiWayApi({
          42: (7, {'name': 'Gravy Train'}),
          9: (2, {'name': 'Bootcamp'}),
        }),
      );

      final submit = find.widgetWithText(FilledButton, 'Submit 2 changes');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Rated from a ride');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(state.hasStagedEdits, isFalse);

      // The checklist reports success but stays open — the rider closes it,
      // it doesn't vanish out from under them the moment checks pass.
      expect(find.text('All checks passed'), findsOneWidget);
      expect(find.byType(StagedChangesDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(StagedChangesDialog), findsNothing);
    });

    testWidgets('a generic comment fails the gate and stays staged', (
      tester,
    ) async {
      final state = await pumpDialog(tester);

      await tester.enterText(find.byType(TextField), 'update');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit 2 changes'));
      await tester.pumpAndSettle();

      expect(find.text('Submission checks'), findsOneWidget);
      expect(find.text('Edit comment'), findsOneWidget);
      // Nothing was thrown away — the gate blocks, it doesn't discard.
      expect(state.stagedEditCount, 2);
    });

    testWidgets(
      'a field changed on OSM since staging raises a conflict, not a silent overwrite',
      (tester) async {
        // Room for the whole conflict card and its action buttons.
        tester.view.physicalSize = const Size(1200, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final state = await pumpDialog(
          tester,
          osmApi: _multiWayApi({
            // Way 42 was staged against "Gravy Train" with no rating; by
            // submit time someone else has rated it Difficult (3) — a real
            // conflict, since that's neither what staging saw nor what this
            // edit wants to write (Medium, "2").
            42: (8, {'name': 'Gravy Train', 'mtb:scale:imba': '3'}),
            9: (2, {'name': 'Bootcamp'}),
          }),
        );

        await tester.enterText(
          find.byType(TextField),
          'Rated difficulty from a ride',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Submit 2 changes'));
        await tester.pumpAndSettle();

        expect(find.text('Someone else edited these fields'), findsOneWidget);
        expect(find.textContaining('When you started: (not set)'), findsOneWidget);
        expect(find.textContaining('On OpenStreetMap now: 3'), findsOneWidget);
        expect(find.textContaining('You are submitting: 2'), findsOneWidget);
        // Staged, not discarded — the rider has to choose.
        expect(state.stagedEditCount, 2);

        await tester.ensureVisible(find.text('Keep my change'));
        await tester.tap(find.text('Keep my change'));
        await tester.pumpAndSettle();

        expect(find.text('Retry checks'), findsOneWidget);
        await tester.tap(find.text('Retry checks'));
        await tester.pumpAndSettle();

        expect(state.hasStagedEdits, isFalse);
      },
    );

    testWidgets('a single change can be removed without touching the rest', (
      tester,
    ) async {
      final state = await pumpDialog(tester);

      await tester.tap(find.byTooltip('Remove this change').first);
      await tester.pumpAndSettle();

      expect(state.stagedEditCount, 1);
      expect(find.text('Gravy Train'), findsNothing);
      expect(find.text('Bootcamp'), findsOneWidget);
    });

    testWidgets('discard all asks first', (tester) async {
      final state = await pumpDialog(tester);

      await tester.tap(find.text('Discard all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep them'));
      await tester.pumpAndSettle();
      expect(state.stagedEditCount, 2);

      await tester.tap(find.text('Discard all').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard all'));
      await tester.pumpAndSettle();
      expect(state.hasStagedEdits, isFalse);
    });
  });
}
