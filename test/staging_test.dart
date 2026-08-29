import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:slab_steward/src/model/difficulty.dart';
import 'package:slab_steward/src/model/electric_bicycle.dart';
import 'package:slab_steward/src/model/staged_edit.dart';
import 'package:slab_steward/src/model/trail.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/osm/osm_auth.dart';
import 'package:slab_steward/src/osm/osm_environment.dart';
import 'package:slab_steward/src/osm/submission_gate.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/staged_changes.dart';
import 'package:slab_steward/src/ui/trail_panel.dart';

Trail _trail({
  Map<String, String> tags = const {},
  bool authoritative = true,
}) => Trail(
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

/// The changeset id every fake write path here reports back.
const _fakeChangesetId = 999;

/// Answers the three changeset write calls — create, upload, close — with a
/// fixed success, or null for anything that isn't one of them so the caller
/// can fall through to its own read handling.
Future<http.Response>? _changesetResponse(http.BaseRequest request) {
  final path = request.url.path;
  if (path.endsWith('/changeset/create')) {
    return Future.value(http.Response('$_fakeChangesetId', 200));
  }
  if (path.endsWith('/upload')) {
    return Future.value(
      http.Response('<diffResult version="0.6" generator="test"/>', 200),
    );
  }
  if (path.endsWith('/close')) return Future.value(http.Response('', 200));
  return null;
}

/// A [StewardState] that answers `/full.json` with [body]/[status], and the
/// changeset write path with a fixed success — enough to exercise
/// [SubmissionGate.submit] without a real OSM server.
///
/// [OsmEnvironment.live] unless told otherwise: the write path is the thing
/// under test here, and it's the configuration the build does *not* currently
/// ship, so it has to be asked for by name rather than inherited.
StewardState _stateServing(
  String body, {
  int status = 200,
  OsmEnvironment environment = OsmEnvironment.live,
}) => StewardState(
  osmApi: OsmApi(
    client: MockClient(
      (request) async =>
          await _changesetResponse(request) ?? http.Response(body, status),
    ),
  ),
  auth: _signedIn(),
  environment: environment,
);

/// A signed-in [OsmAuthState] with no popup and no network — submit is gated
/// on sign-in, so anything exercising the submit path needs one.
OsmAuthState _signedIn() => OsmAuthState()
  ..debugSignIn(
    token: 'test-token',
    identity: const OsmIdentity(id: 1, displayName: 'Test Rider'),
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
/// the submission gate's fetch step against more than one trail at once — and
/// the changeset write path that follows it.
OsmApi _multiWayApi(Map<int, (int version, Map<String, String> tags)> ways) =>
    OsmApi(
      client: MockClient((request) async {
        final changeset = await _changesetResponse(request);
        if (changeset != null) return changeset;
        final match = RegExp(
          r'/way/(\d+)/full\.json',
        ).firstMatch(request.url.path);
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
      expect(
        state.stagedRevision,
        start + 2,
        reason: 'nothing was staged for 99',
      );
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

    test('a passed gate submits and clears the list', () async {
      final state = _stateServing(_wayJson({}));
      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.easy));
      final gate = state.createSubmissionGate();
      final passed = await gate.run(
        comment: 'Rated from a ride',
        trails: state.stagedTrails,
      );
      expect(passed, isTrue);

      final submitted = await gate.submit(
        bearerToken: state.auth.bearerToken!,
        requestReview: false,
      );
      expect(submitted, isTrue);
      expect(gate.changesetId, 999);

      state.clearStagedEdits();
      expect(state.hasStagedEdits, isFalse);
    });

    // The whole point of the dry-run configuration: everything up to the
    // three changeset calls happens for real, against the same hosts and the
    // same data, and then those three calls don't.
    test('a dry run passes every check without opening a changeset', () async {
      final writes = <String>[];
      final state = StewardState(
        osmApi: OsmApi(
          client: MockClient((request) async {
            if (await _changesetResponse(request) case final response?) {
              writes.add(request.url.path);
              return response;
            }
            return http.Response(_wayJson({'name': 'Gravy Train'}), 200);
          }),
        ),
        auth: _signedIn(),
        environment: OsmEnvironment.dryRun,
      );
      addTearDown(state.dispose);
      state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.easy));

      final gate = state.createSubmissionGate();
      expect(
        await gate.run(
          comment: 'Rated from a ride',
          trails: state.stagedTrails,
        ),
        isTrue,
        reason: 'the gate itself is unchanged — it reads and checks for real',
      );
      expect(
        await gate.submit(
          bearerToken: state.auth.bearerToken!,
          requestReview: false,
        ),
        isTrue,
        reason: 'the caller must go on to clear staging exactly as it would',
      );

      expect(writes, isEmpty, reason: 'nothing may reach the changeset API');
      expect(
        gate.changesetId,
        isNull,
        reason: 'there is no changeset, so there is no permalink to offer',
      );
      expect(gate.changesetUrl, isNull);
      expect(
        gate.checks.every((c) => c.status == CheckStatus.passed),
        isTrue,
        reason: 'the checklist reads the same as a real submission',
      );
    });

    test(
      'a rejected submit keeps the edits staged, and a 401 signs out',
      () async {
        final state = StewardState(
          osmApi: OsmApi(
            client: MockClient((request) async {
              if (request.url.path.endsWith('/changeset/create')) {
                return http.Response('', 401);
              }
              return http.Response(_wayJson({'name': 'Gravy Train'}), 200);
            }),
          ),
          auth: _signedIn(),
          environment: OsmEnvironment.live,
        );
        addTearDown(state.dispose);
        state.stageEdit(StagedEdit.difficulty(_trail(), Difficulty.easy));

        final gate = state.createSubmissionGate();
        expect(
          await gate.run(
            comment: 'Rated from a ride',
            trails: state.stagedTrails,
          ),
          isTrue,
        );
        expect(
          await gate.submit(
            bearerToken: state.auth.bearerToken!,
            requestReview: false,
          ),
          isFalse,
        );

        // Nothing reached OSM, so nothing may be thrown away.
        expect(state.hasStagedEdits, isTrue);
        expect(gate.changesetId, isNull);
        expect(gate.tokenRejected, isTrue);
        expect(
          gate.checks.firstWhere((c) => c.id == 'submit').status,
          CheckStatus.failed,
        );
      },
    );

    test(
      'the upload carries every tag and every node, not just the diff',
      () async {
        // The spec's central rule: an OSM way modify replaces the element
        // wholesale, so anything left out of the payload is deleted. See
        // docs/slab-steward-osm-changeset-spec.md §2.
        final sent = <String, String>{};
        final state = StewardState(
          osmApi: OsmApi(
            client: MockClient((request) async {
              final changeset = await _changesetResponse(request);
              if (changeset != null) {
                sent[request.url.path] = request.body;
                return changeset;
              }
              return http.Response(
                _wayJson({
                  'name': 'Gravy Train',
                  'highway': 'path',
                  'surface': 'ground',
                }),
                200,
              );
            }),
          ),
          auth: _signedIn(),
          environment: OsmEnvironment.live,
        );
        addTearDown(state.dispose);

        state.stageEdit(
          StagedEdit.difficulty(
            _trail(tags: {'highway': 'path', 'surface': 'ground'}),
            Difficulty.easy,
          ),
        );
        final gate = state.createSubmissionGate();
        expect(
          await gate.run(
            comment: 'Rated from a ride',
            trails: state.stagedTrails,
          ),
          isTrue,
        );
        expect(
          await gate.submit(
            bearerToken: state.auth.bearerToken!,
            requestReview: false,
          ),
          isTrue,
        );

        final upload = sent.entries
            .firstWhere((e) => e.key.endsWith('/upload'))
            .value;

        // The version read at submit time, echoed exactly — a mismatch is a 409.
        expect(upload, contains('version="7"'));
        expect(upload, contains('changeset="$_fakeChangesetId"'));
        // Both member nodes, in order. Dropping one truncates the geometry.
        expect(
          upload.indexOf('<nd ref="1"/>'),
          lessThan(upload.indexOf('<nd ref="2"/>')),
        );
        // Every pre-existing tag survives, not just the one being edited.
        expect(upload, contains('k="name" v="Gravy Train"'));
        expect(upload, contains('k="highway" v="path"'));
        expect(upload, contains('k="surface" v="ground"'));
        expect(upload, contains('k="mtb:scale:imba" v="1"'));

        // And the changeset itself carries the attribution the spec requires.
        final create = sent.entries
            .firstWhere((e) => e.key.endsWith('/changeset/create'))
            .value;
        expect(create, contains('k="created_by"'));
        expect(create, contains('k="hashtags" v="#slabsteward"'));
        expect(create, contains('Rated from a ride #slabsteward'));
      },
    );
  });

  group('StagedEdit.electricBicycle', () {
    test('diffs the access tag against what the trail actually has', () {
      final edit = StagedEdit.electricBicycle(_trail(), EbikeAccess.notAllowed);
      expect(edit.tagChanges, {'electric_bicycle': 'no'});
      expect(edit.summary, 'Not recorded → Not allowed');
      expect(edit.changesOsm, isTrue);
    });

    test('re-stating what OSM already says changes no tags', () {
      final edit = StagedEdit.electricBicycle(
        _trail(tags: {'electric_bicycle': 'yes'}),
        EbikeAccess.allowed,
      );
      expect(edit.tagChanges, isEmpty);
      expect(edit.changesOsm, isFalse);
    });

    test(
      'names a value the picker cannot express, rather than "not recorded"',
      () {
        final edit = StagedEdit.electricBicycle(
          _trail(tags: {'electric_bicycle': 'destination'}),
          EbikeAccess.allowed,
        );
        expect(edit.summary, 'destination → Allowed');
        expect(edit.tagChanges, {'electric_bicycle': 'yes'});
      },
    );
  });

  group('TrailPanel editors', () {
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

    /// Picks [label] out of the panel's difficulty picker.
    Future<void> pickDifficulty(WidgetTester tester, String label) async {
      await tester.tap(find.byType(DropdownButton<Difficulty>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('picking a rating stages it, with no edit mode in between', (
      tester,
    ) async {
      final state = await pumpSelected(tester, body: _wayJson({}));

      // The picker is the resting state of the field — there is no pencil.
      expect(find.byTooltip('Edit difficulty'), findsNothing);
      expect(find.text('Choose a rating'), findsOneWidget);

      await pickDifficulty(tester, 'Medium');

      expect(state.stagedEditCount, 1);
      expect(state.stagedEditFor(42, TrailAttribute.difficulty)?.tagChanges, {
        'mtb:scale:imba': '2',
      });
      // The panel shows the pending value, flagged as pending, and the map
      // overlay picks up a count.
      expect(find.text('STAGED'), findsOneWidget);
      expect(find.text('Was not rated'), findsOneWidget);
      expect(find.text('Review 1 change'), findsOneWidget);
    });

    testWidgets('the undo beside the field walks the change back', (
      tester,
    ) async {
      final state = await pumpSelected(tester, body: _wayJson({}));

      await pickDifficulty(tester, 'Easy');
      expect(state.stagedEditCount, 1);

      await tester.tap(find.byTooltip('Discard this staged change'));
      await tester.pumpAndSettle();

      expect(state.hasStagedEdits, isFalse);
      expect(find.text('Choose a rating'), findsOneWidget);
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

      await pickDifficulty(tester, 'Easy');

      expect(state.hasStagedEdits, isFalse);
    });

    testWidgets('cannot edit against tile data the API could not confirm', (
      tester,
    ) async {
      await pumpSelected(tester, body: 'nope', status: 500);

      final picker = tester.widget<DropdownButton<Difficulty>>(
        find.byType(DropdownButton<Difficulty>),
      );
      expect(picker.onChanged, isNull);
    });

    testWidgets('an e-bike answer outside the two options is read-only', (
      tester,
    ) async {
      final state = await pumpSelected(
        tester,
        body: _wayJson({'electric_bicycle': 'designated'}),
      );

      // electric_bicycle is one key, so a pick would replace this rather than
      // add to it — and "designated" says everything "allowed" says and more.
      expect(find.byType(DropdownButton<EbikeAccess>), findsNothing);
      expect(find.text('designated'), findsOneWidget);
      expect(find.textContaining('Steward leaves it alone'), findsOneWidget);
      expect(state.hasStagedEdits, isFalse);
      // It counts as answered, so it isn't nagged about either.
      expect(find.text('MISSING'), findsNWidgets(2));
    });

    testWidgets('a rating outside the 0–4 scale renders, and says so', (
      tester,
    ) async {
      // A DropdownButton asserts if handed a value it has no item for, so an
      // always-visible picker has to cope with junk in the tag.
      await pumpSelected(tester, body: _wayJson({'mtb:scale:imba': '7'}));

      expect(find.text('Choose a rating'), findsOneWidget);
      expect(find.textContaining('is not a rating on the 0–4 scale'), findsOne);
    });

    testWidgets('e-bike access asks its own completeness question', (
      tester,
    ) async {
      final state = await pumpSelected(tester, body: _wayJson({}));

      // Difficulty, surface and e-bike access all count towards completeness,
      // so an untagged trail wears three badges, not two.
      expect(find.text('MISSING'), findsNWidgets(3));
      expect(find.textContaining('Answer from the trailhead sign'), findsOne);

      await tester.tap(find.byType(DropdownButton<EbikeAccess>));
      await tester.pumpAndSettle();
      // Two options, and each says what it claims — this key is about e-bikes
      // alone, which a bare "allowed" doesn't convey.
      expect(find.byType(DropdownMenuItem<EbikeAccess>), findsNWidgets(2));
      expect(find.textContaining('the same as any other bike'), findsOneWidget);
      await tester.tap(find.text('Not allowed').last);
      await tester.pumpAndSettle();

      expect(state.stagedEditCount, 1);
      final edit = state.stagedEditFor(42, TrailAttribute.electricBicycle);
      expect(edit?.tagChanges, {'electric_bicycle': 'no'});
      expect(edit?.summary, 'Not recorded → Not allowed');
      // And the meaning of the chosen value survives the menu closing.
      expect(
        find.textContaining('E-bikes are shut out of this trail'),
        findsOneWidget,
      );
    });
  });

  group('values Steward will not overwrite', () {
    test('a bulk apply skips them, and reports that it did', () async {
      final state = StewardState();
      addTearDown(state.dispose);
      final report = state.applyElectricBicycle([
        _trail(tags: {'electric_bicycle': 'designated'}),
        _trail(tags: {'electric_bicycle': 'permissive'}),
        _trail(),
      ], EbikeAccess.allowed);

      expect(report, (staged: 1, unchanged: 0, unreadable: 0, protected: 2));
      expect(
        state.stagedEdits.single.tagChanges,
        {'electric_bicycle': 'yes'},
        reason: 'only the trail that said nothing is written to',
      );
    });
  });

  group('StagedChangesDialog', () {
    Future<StewardState> pumpDialog(
      WidgetTester tester, {
      OsmApi? osmApi,
    }) async {
      final state = StewardState(osmApi: osmApi, auth: _signedIn());
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
        MaterialApp(
          home: Scaffold(body: StagedChangesDialog(state: state)),
        ),
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
        expect(
          find.textContaining('When you started: (not set)'),
          findsOneWidget,
        );
        expect(find.textContaining('On OpenStreetMap now: 3'), findsOneWidget);
        expect(find.textContaining('You are submitting: 2'), findsOneWidget);
        // Staged, not discarded — the rider has to choose.
        expect(state.stagedEditCount, 2);

        // ensureVisible kicks off a scroll animation; without settling it
        // first, the tap is aimed at where the button used to be.
        await tester.ensureVisible(find.text('Keep my change'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep my change'));
        await tester.pumpAndSettle();

        expect(find.text('Retry checks'), findsOneWidget);
        await tester.ensureVisible(find.text('Retry checks'));
        await tester.pumpAndSettle();
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
