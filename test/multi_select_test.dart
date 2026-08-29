import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slab_steward/src/model/difficulty.dart';
import 'package:slab_steward/src/model/electric_bicycle.dart';
import 'package:slab_steward/src/model/staged_edit.dart';
import 'package:slab_steward/src/model/trail.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/model/sidebar_section.dart';
import 'package:slab_steward/src/ui/selection_panel.dart';
import 'package:slab_steward/src/ui/staged_changes.dart';
import 'package:slab_steward/src/ui/trail_list_panel.dart';

/// A tile feature as the map reports it.
Map<String, Object?> _tile(
  int id,
  String name, {
  String? imba,
  String? surface,
  String? ebike,
}) => {
  'OSM_ID': id,
  'OSM_VERSION': 7,
  'name': name,
  'mtb:scale:imba': ?imba,
  'surface': ?surface,
  'electric_bicycle': ?ebike,
};

/// A fake OSM API that answers any way id, and counts what it was asked for —
/// bulk selection is exactly where an accidental request-per-trail hides.
class _FakeOsm {
  _FakeOsm({this.tagsFor = _noTags, this.status = 200});

  final Map<String, String> Function(int wayId) tagsFor;
  final int status;
  final List<int> reads = [];

  static Map<String, String> _noTags(int _) => const {};

  StewardState newState() => StewardState(osmApi: OsmApi(client: client()));

  MockClient client() => MockClient((request) async {
    final id = int.parse(
      RegExp(r'/way/(\d+)/full\.json').firstMatch(request.url.path)!.group(1)!,
    );
    reads.add(id);
    if (status != 200) return http.Response('nope', status);
    final tags = {'name': 'Way $id', ...tagsFor(id)};
    return http.Response(
      '{"elements":['
      '{"type":"node","id":1,"lat":47.5,"lon":-122.0},'
      '{"type":"node","id":2,"lat":47.51,"lon":-122.01},'
      '{"type":"way","id":$id,"version":9,"nodes":[1,2],"tags":'
      '{${tags.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}}'
      ']}',
      200,
    );
  });
}

void main() {
  group('the working set', () {
    test('a plain click replaces it, a modified click adds to it', () async {
      final osm = _FakeOsm();
      final state = osm.newState();
      addTearDown(state.dispose);

      await state.selectFromTile(_tile(1, 'Gravy Train'));
      expect(state.selectionCount, 1);
      expect(state.selected?.osmWayId, 1);

      await state.toggleFromTile(_tile(2, 'Bootcamp'));
      expect(state.selectionCount, 2);
      // Two trails is not a detail view — the bulk editor takes over.
      expect(state.selected, isNull);
      expect(state.hasMultiSelection, isTrue);

      // A modified click on a trail already in the set takes it back out.
      await state.toggleFromTile(_tile(1, 'Gravy Train'));
      expect(state.selectionCount, 1);
      expect(state.selected?.osmWayId, 2);

      // A plain click starts over.
      await state.selectFromTile(_tile(3, 'Luge'));
      expect([for (final t in state.selectedTrails) t.osmWayId], [3]);
    });

    test('trails picked one at a time are read from the OSM API', () async {
      final osm = _FakeOsm();
      final state = osm.newState();
      addTearDown(state.dispose);

      await state.selectFromTile(_tile(1, 'Gravy Train'));
      await state.toggleFromTile(_tile(2, 'Bootcamp'));

      expect(osm.reads, [1, 2]);
      expect(state.selectedTrails.every((t) => t.isAuthoritative), isTrue);
    });

    test(
      '"select all" reads nothing until there is an edit to compose',
      () async {
        final osm = _FakeOsm();
        final state = osm.newState();
        addTearDown(state.dispose);

        state.setVisibleTrails([
          for (var i = 1; i <= 30; i++) _tile(i, 'Trail $i'),
        ]);
        state.setSelection([for (var i = 1; i <= 30; i++) i]);

        expect(state.selectionCount, 30);
        expect(
          osm.reads,
          isEmpty,
          reason: 'one click must not be 30 API calls',
        );

        final progress = <(int, int)>[];
        await state.resolveSelection(
          onProgress: (done, total) => progress.add((done, total)),
        );

        expect(osm.reads, hasLength(30));
        expect(state.editableSelection, hasLength(30));
        expect(progress.first, (0, 30));
        expect(progress.last, (30, 30));
      },
    );

    test('dropping a trail mid-read abandons the answer', () async {
      final osm = _FakeOsm();
      final state = osm.newState();
      addTearDown(state.dispose);

      final pending = state.selectFromTile(_tile(1, 'Gravy Train'));
      state.clearSelection();
      await pending;

      expect(state.hasSelection, isFalse);
      expect(state.trailFor(1)?.isAuthoritative, isFalse);
    });

    test('a way the API cannot read is named, and left alone', () async {
      final osm = _FakeOsm(status: 410);
      final state = osm.newState();
      addTearDown(state.dispose);

      await state.selectFromTile(_tile(1, 'Gravy Train'));
      expect(state.readErrorFor(1), contains('no longer in OpenStreetMap'));
      expect(state.editableSelection, isEmpty);
    });
  });

  group('a selection box', () {
    test('adds every trail it caught to the set, and reads nothing', () async {
      final osm = _FakeOsm();
      final state = osm.newState();
      addTearDown(state.dispose);

      await state.selectFromTile(_tile(1, 'Gravy Train'));
      osm.reads.clear();

      // What the map hands back: features repeated across tile boundaries,
      // and one trail the box caught that was already in the set.
      state.addFromTiles([
        _tile(2, 'Bootcamp'),
        _tile(3, 'Luge'),
        _tile(2, 'Bootcamp'),
        _tile(1, 'Gravy Train'),
      ]);

      expect(state.selectionCount, 3);
      expect(
        [for (final trail in state.selectedTrails) trail.osmWayId],
        [1, 2, 3],
      );
      expect(
        osm.reads,
        isEmpty,
        reason: 'one gesture can name a hundred trails',
      );
    });

    test('a box is additive — it never drops what it caught', () async {
      final osm = _FakeOsm();
      final state = osm.newState();
      addTearDown(state.dispose);

      state.addFromTiles([_tile(1, 'Gravy Train'), _tile(2, 'Bootcamp')]);
      state.addFromTiles([_tile(2, 'Bootcamp')]);

      expect(state.selectionCount, 2, reason: 'a second pass is not a toggle');
    });

    test('one notification for the whole box, and none for nothing', () {
      final osm = _FakeOsm();
      final state = osm.newState();
      addTearDown(state.dispose);

      var notifications = 0;
      state.addListener(() => notifications++);

      state.addFromTiles([for (var i = 1; i <= 20; i++) _tile(i, 'Trail $i')]);
      expect(notifications, 1);

      // A box drawn over trails already selected changes nothing, and a box
      // that caught only features with no usable way id names nothing.
      state.addFromTiles([_tile(1, 'Trail 1')]);
      state.addFromTiles([
        {'name': 'no id here'},
      ]);
      expect(notifications, 1);
      expect(state.selectionCount, 20);
    });

    test('the trails it named are resolvable, like any other set', () async {
      final osm = _FakeOsm();
      final state = osm.newState();
      addTearDown(state.dispose);

      state.addFromTiles([_tile(1, 'Gravy Train'), _tile(2, 'Bootcamp')]);
      await state.resolveSelection();

      expect(osm.reads, hasLength(2));
      expect(state.editableSelection, hasLength(2));
    });
  });

  group('applying one rating across a selection', () {
    /// Two authoritative trails: way 1 un-rated, way 2 already Medium.
    Future<StewardState> twoSelected() async {
      final osm = _FakeOsm(
        tagsFor: (id) => id == 2 ? const {'mtb:scale:imba': '2'} : const {},
      );
      final state = osm.newState();
      addTearDown(state.dispose);
      await state.selectFromTile(_tile(1, 'Gravy Train'));
      await state.toggleFromTile(_tile(2, 'Bootcamp'));
      return state;
    }

    test('stages one edit per trail, and says what it skipped', () async {
      final state = await twoSelected();

      final report = state.applyDifficulty(
        state.selectedTrails,
        Difficulty.medium,
      );

      expect(report, (staged: 1, unchanged: 1, unreadable: 0, protected: 0));
      // A batch is a convenience for composing changes, not a different kind
      // of change: the review list still holds one edit per trail.
      expect(state.stagedEditsByTrail.keys, [1]);
      expect(state.stagedEditFor(1, TrailAttribute.difficulty)?.tagChanges, {
        'mtb:scale:imba': '2',
      });
    });

    test('one notification for the whole batch', () async {
      final state = await twoSelected();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.applyDifficulty(state.selectedTrails, Difficulty.expert);
      expect(state.stagedEditCount, 2);
      expect(notifications, 1);

      // Re-applying the value both trails now carry is a no-op on OSM, but it
      // does replace both pending edits, so the map still has to redraw.
      state.applyDifficulty(state.selectedTrails, Difficulty.expert);
      expect(notifications, 2);
    });

    test('re-applying what OSM already holds walks the batch back', () async {
      final state = await twoSelected();
      state.applyDifficulty(state.selectedTrails, Difficulty.difficult);
      expect(state.stagedEditCount, 2);

      // Way 1 is un-rated, so Difficult stays staged there; way 2 goes back to
      // the Medium it already had, which means no pending change at all.
      final report = state.applyDifficulty(
        state.selectedTrails,
        Difficulty.medium,
      );
      expect(report, (staged: 1, unchanged: 1, unreadable: 0, protected: 0));
      expect(state.stagedEditsByTrail.keys, [1]);
    });

    test('never composes an edit against tile data', () {
      final state = StewardState();
      addTearDown(state.dispose);
      final provisional = Trail.fromTileProperties(_tile(5, 'Tiles Only'));

      final report = state.applyDifficulty([provisional], Difficulty.easy);

      expect(report, (staged: 0, unchanged: 0, unreadable: 1, protected: 0));
      expect(state.hasStagedEdits, isFalse);
    });
  });

  group('the in-view list', () {
    test('dedupes the tile features and sorts unnamed trails last', () {
      final state = StewardState();
      addTearDown(state.dispose);

      state.setVisibleTrails([
        _tile(2, 'Bootcamp'),
        _tile(1, 'Gravy Train'),
        // The same way, reported twice because it crosses a tile boundary.
        _tile(2, 'Bootcamp'),
        {'OSM_ID': 3, 'OSM_VERSION': 1},
        // No usable way id: nothing Steward can edit.
        const {'name': 'Mystery'},
      ]);

      expect([for (final t in state.visibleTrails) t.osmWayId], [2, 1, 3]);
      expect(state.hasListedVisibleTrails, isTrue);
    });

    test('closing the list drops it — it is only ever one viewport old', () {
      final state = StewardState();
      addTearDown(state.dispose);

      state.openSection(SidebarSection.trails);
      state.setVisibleTrails([_tile(1, 'Gravy Train')]);
      expect(state.visibleTrails, hasLength(1));

      state.closeSection();
      expect(state.visibleTrails, isEmpty);
      expect(state.hasListedVisibleTrails, isFalse);
      // The trail itself is still known — a selection outlives the list.
      expect(state.trailFor(1), isNotNull);
    });
  });

  group('TrailListPanel', () {
    Future<StewardState> pumpList(
      WidgetTester tester, {
      _FakeOsm? osm,
      List<Map<String, Object?>>? trails,
    }) async {
      final state = (osm ?? _FakeOsm()).newState();
      addTearDown(state.dispose);
      state.openSection(SidebarSection.trails);
      state.setVisibleTrails(
        trails ??
            [
              _tile(1, 'Gravy Train'),
              _tile(2, 'Bootcamp', imba: '2', surface: 'compacted'),
            ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => Align(
                alignment: Alignment.topLeft,
                child: TrailListPanel(state: state),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('lists what the map is drawing, with what it knows', (
      tester,
    ) async {
      await pumpList(tester);

      expect(find.text('Bootcamp'), findsOneWidget);
      expect(find.text('Gravy Train'), findsOneWidget);
      expect(find.text('No rating, no surface'), findsOneWidget);
      expect(find.text('Medium · Hardpack / Groomed'), findsOneWidget);
    });

    testWidgets('select all ticks every trail the list is showing', (
      tester,
    ) async {
      final osm = _FakeOsm();
      final state = await pumpList(tester, osm: osm);

      await tester.tap(find.text('Select all 2'));
      await tester.pumpAndSettle();

      expect(state.selectionCount, 2);
      expect(find.text('2 selected'), findsOneWidget);
      expect(osm.reads, isEmpty, reason: 'ticking a box is not an OSM read');

      await tester.tap(find.text('Select all 2'));
      await tester.pumpAndSettle();
      expect(state.hasSelection, isFalse);
    });

    testWidgets('a single checkbox reads that trail, so the map can draw it', (
      tester,
    ) async {
      final osm = _FakeOsm();
      final state = await pumpList(tester, osm: osm);

      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();

      expect(state.selectionCount, 1);
      expect(osm.reads, hasLength(1));
    });

    testWidgets('the list picks trails and edits nothing', (tester) async {
      final osm = _FakeOsm();
      final state = await pumpList(tester, osm: osm);

      // No pickers: a 250-row list of live dropdowns answered a question the
      // list is not asking, and spent an OSM read every time one was touched.
      expect(find.byType(DropdownButton<Difficulty>), findsNothing);
      // Every row still says how it is rated — as the signage glyph, which is
      // how a rating reads everywhere else in both apps.
      expect(find.byType(DifficultyIcon), findsNWidgets(2));
      expect(find.text('Medium · Hardpack / Groomed'), findsOneWidget);

      // The whole row is the selector, not just its checkbox.
      await tester.tap(find.text('Bootcamp'));
      await tester.pumpAndSettle();
      expect(state.selectionCount, 1);
      expect(state.isSelected(2), isTrue);
      expect(state.hasStagedEdits, isFalse);
    });

    testWidgets('a rating staged elsewhere shows up on the row', (
      tester,
    ) async {
      final osm = _FakeOsm();
      final state = await pumpList(tester, osm: osm);

      await state.setDifficulty(1, Difficulty.difficult);
      await tester.pumpAndSettle();

      expect(state.stagedEditCount, 1);
      expect(find.text('STAGED'), findsOneWidget);
      expect(find.text('Not rated → Difficult'), findsOneWidget);
    });
  });

  group('SelectionPanel', () {
    testWidgets('stages one edit per trail, and reports the batch', (
      tester,
    ) async {
      final osm = _FakeOsm(
        tagsFor: (id) => id == 2 ? const {'mtb:scale:imba': '2'} : const {},
      );
      final state = osm.newState();
      addTearDown(state.dispose);
      await state.selectFromTile(_tile(1, 'Gravy Train'));
      await state.toggleFromTile(_tile(2, 'Bootcamp'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => Stack(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: SelectionPanel(state: state),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The pane's own heading names the count; the editor names it on every
      // field it is about to write.
      expect(find.text('DIFFICULTY ON ALL 2'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<Difficulty>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medium').last);
      await tester.pumpAndSettle();

      expect(state.hasStagedEdits, isFalse);
      await tester.tap(find.widgetWithText(FilledButton, 'Stage on 2 trails'));
      await tester.pumpAndSettle();

      expect(state.stagedEditCount, 1);
      expect(
        find.text('Difficulty — staged 1 change. 1 already rated medium.'),
        findsOneWidget,
      );
      // What the rider sees of that count now lives on the rail's badge —
      // see sidebar_test.dart.
    });

    testWidgets('one pass can set both fields, and reports each on its own', (
      tester,
    ) async {
      // Room for both pickers and the report under them, so what's asserted
      // is what the panel draws rather than what fits an 800×600 window.
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final osm = _FakeOsm(
        tagsFor: (id) => id == 2 ? const {'electric_bicycle': 'no'} : const {},
      );
      final state = osm.newState();
      addTearDown(state.dispose);
      await state.selectFromTile(_tile(1, 'Gravy Train'));
      await state.toggleFromTile(_tile(2, 'Bootcamp'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => SelectionPanel(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<Difficulty>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Easy').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<EbikeAccess>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not allowed').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Stage on 2 trails'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Stage on 2 trails'));
      await tester.pumpAndSettle();

      // Two trails rated, one e-bike permission staged — Bootcamp already
      // said no e-bikes, which is not an edit.
      expect(state.stagedEditCount, 3);
      expect(
        state.stagedEditFor(1, TrailAttribute.electricBicycle)?.tagChanges,
        {'electric_bicycle': 'no'},
      );
      expect(state.stagedEditFor(2, TrailAttribute.electricBicycle), isNull);
      // One line per attribute: "staged 2" means something different for a
      // rating than for an access tag, and a merged total would hide that.
      expect(
        find.textContaining('Difficulty — staged 2 changes.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'E-bike access — staged 1 change. 1 already set to not allowed.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a trail can be dropped from the set', (tester) async {
      final state = _FakeOsm().newState();
      addTearDown(state.dispose);
      await state.selectFromTile(_tile(1, 'Gravy Train'));
      await state.toggleFromTile(_tile(2, 'Bootcamp'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => SelectionPanel(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip('Drop this trail from the selection').first,
      );
      await tester.pumpAndSettle();
      expect(state.selectionCount, 1);
    });
  });

  group('the review list after a bulk edit', () {
    testWidgets('shows every trail on its own, and prunes one at a time', (
      tester,
    ) async {
      // Room for the whole review sheet, so "each edit appears on its own" is
      // tested against what is drawn rather than against what fits.
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final osm = _FakeOsm();
      final state = osm.newState();
      addTearDown(state.dispose);
      await state.selectFromTile(_tile(1, 'Gravy Train'));
      await state.toggleFromTile(_tile(2, 'Bootcamp'));
      await state.toggleFromTile(_tile(3, 'Luge'));

      state.applyDifficulty(state.selectedTrails, Difficulty.difficult);
      expect(state.stagedEditCount, 3);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // The sidebar is what rebuilds a pane when the state changes.
            body: ListenableBuilder(
              listenable: state,
              builder: (context, _) => StagedChangesPanel(state: state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The way name comes back from the OSM API, so each trail is named on
      // its own line with its own diff — a batch is never one opaque entry.
      expect(find.text('Way 1'), findsOneWidget);
      expect(find.text('Way 2'), findsOneWidget);
      expect(find.text('Way 3'), findsOneWidget);
      expect(find.text('Difficulty: Not rated → Difficult'), findsNWidgets(3));
      expect(find.text('mtb:scale:imba=3'), findsNWidgets(3));

      await tester.tap(find.byTooltip('Remove this change').first);
      await tester.pumpAndSettle();
      expect(state.stagedEditCount, 2);
      expect(find.text('Way 1'), findsNothing);
    });
  });
}
