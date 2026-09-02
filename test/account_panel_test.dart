import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/osm/osm_auth.dart';
import 'package:slab_steward/src/osm/osm_environment.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/account_panel.dart';
import 'package:slab_steward/src/ui/slab_theme.dart';

const _changesetsJson =
    '{"changesets":['
    '{"id":41,"created_at":"2024-01-01T10:00:00Z","changes_count":3,'
    '"tags":{"comment":"rate a few trails #slabsteward",'
    '"hashtags":"#slabsteward"}},'
    '{"id":42,"created_at":"2024-03-04T09:00:00Z","changes_count":1,'
    '"tags":{"comment":"one more #slabsteward",'
    '"hashtags":"#slabsteward"}}'
    ']}';

/// A signed-in rider, so the tests that care about the changeset list don't
/// each rebuild the same auth state.
OsmAuthState _signedIn() => OsmAuthState()
  ..debugSignIn(
    token: 't',
    identity: const OsmIdentity(id: 1, displayName: 'Test Rider'),
  );

Future<StewardState> _pump(
  WidgetTester tester, {
  OsmAuthState? auth,
  String changesetsBody = _changesetsJson,
  int changesetsStatus = 200,
}) async {
  tester.view.physicalSize = const Size(420, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final state = StewardState(
    auth: auth ?? OsmAuthState(),
    osmApi: OsmApi(
      client: MockClient(
        (_) async => http.Response(changesetsBody, changesetsStatus),
      ),
    ),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: slabTheme(),
      home: Scaffold(body: AccountPanel(state: state)),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

/// Scrolls a control into view before pressing it, the way a rider reaches
/// one. The pane carries the stats and the changeset fold above the sign-out
/// button now, so its foot is off the bottom of the window — and the pane is a
/// lazy [ListView], so a control down there has not been built yet either.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 120);
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  // The regression this guards: sign-in used to live only inside the staged
  // changes dialog, which needs staged edits to open — so a fresh session had
  // no way to sign in at all. It has had a home of its own ever since, and the
  // rail's account button is now that home.
  testWidgets('offers sign-in with nothing staged and nothing selected', (
    tester,
  ) async {
    final state = await _pump(tester);

    expect(state.hasStagedEdits, isFalse);
    expect(state.hasSelection, isFalse);
    final signIn = find.widgetWithText(
      FilledButton,
      'Sign in to OpenStreetMap',
    );
    expect(signIn, findsOneWidget);
    expect(
      tester.widget<FilledButton>(signIn).onPressed,
      isNotNull,
      reason: 'the control has to be pressable, not just visible',
    );
  });

  testWidgets('names the server in both states', (tester) async {
    await _pump(tester);
    expect(find.text(osmShortLabel), findsOneWidget);

    await _pump(tester, auth: _signedIn());
    expect(find.text(osmShortLabel), findsOneWidget);
  });

  testWidgets('shows the account and can sign out once signed in', (
    tester,
  ) async {
    final state = await _pump(tester, auth: _signedIn());

    expect(find.text('Test Rider'), findsOneWidget);
    expect(find.text('Sign in to OpenStreetMap'), findsNothing);
    // The avatar answers "whose account" at a glance, which is the whole
    // reason the rail wears one.
    expect(find.text('TR'), findsOneWidget);

    await _tap(tester, find.widgetWithText(OutlinedButton, 'Sign out'));

    expect(state.auth.isSignedIn, isFalse);
    expect(find.text('Sign in to OpenStreetMap'), findsOneWidget);
  });

  // The rider's own record of what has actually left this machine. The pane
  // used to end at "signed in as", which answered whose account without ever
  // showing what had been written from it.
  testWidgets('folds the submitted changesets away until asked for', (
    tester,
  ) async {
    final state = await _pump(tester, auth: _signedIn());

    expect(state.changesets, hasLength(2));
    // Shut, but advertising what's behind it. The count is scoped to the
    // fold's own header: the stats above it are full of numbers, and two of
    // them are also 2.
    expect(find.text('Submitted changesets'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(InkWell, 'Submitted changesets'),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(find.text('one more #slabsteward'), findsNothing);

    await _tap(tester, find.text('Submitted changesets'));

    expect(find.text('rate a few trails #slabsteward'), findsOneWidget);
    expect(find.text('one more #slabsteward'), findsOneWidget);
    // Newest first, whatever order OSM answered in.
    expect(
      tester.getTopLeft(find.text('one more #slabsteward')).dy,
      lessThan(
        tester.getTopLeft(find.text('rate a few trails #slabsteward')).dy,
      ),
    );
  });

  testWidgets('each row carries its date, size and a link to OSM', (
    tester,
  ) async {
    await _pump(tester, auth: _signedIn());
    await _tap(tester, find.text('Submitted changesets'));

    expect(find.text('Mar 4, 2024 · #42 · 1 trail'), findsOneWidget);
    expect(find.text('Jan 1, 2024 · #41 · 3 trails'), findsOneWidget);
    // The link is the point: OSM's own page holds the diff, the discussion
    // and the revert button.
    expect(
      find.byTooltip('$osmWebHost/changeset/42'),
      findsOneWidget,
      reason: 'the row has to say where tapping it goes',
    );
  });

  testWidgets('says so rather than showing an empty fold', (tester) async {
    await _pump(tester, auth: _signedIn(), changesetsBody: '{"changesets":[]}');
    await _tap(tester, find.text('Submitted changesets'));

    expect(find.textContaining('Nothing submitted yet'), findsOneWidget);
  });

  // One read feeds the stats and the fold, so it reports itself once, in
  // full, under the heading that carries the Refresh which retries it. The
  // fold only has to say why it is empty.
  testWidgets('surfaces a failed read once, above the fold', (tester) async {
    await _pump(
      tester,
      auth: _signedIn(),
      changesetsBody: 'nope',
      changesetsStatus: 503,
    );

    expect(find.textContaining('503'), findsOneWidget);

    await _tap(tester, find.text('Submitted changesets'));

    expect(find.textContaining('503'), findsOneWidget);
    expect(find.text('Couldn\'t read your changesets.'), findsOneWidget);
  });

  testWidgets('signing out drops the last rider\'s changesets', (tester) async {
    final state = await _pump(tester, auth: _signedIn());
    await _tap(tester, find.text('Submitted changesets'));
    expect(find.text('one more #slabsteward'), findsOneWidget);

    await _tap(tester, find.widgetWithText(OutlinedButton, 'Sign out'));

    expect(state.changesets, isEmpty);
    expect(find.text('one more #slabsteward'), findsNothing);
    expect(find.text('Submitted changesets'), findsNothing);
  });

  // The stats pane had a rail button of its own until both were fed by one
  // read of the same changesets. Folded in, the pane reads as the account's
  // record: what has been done, the changesets it went out in, and the way
  // out last.
  testWidgets('carries the stats, then the changesets, then the way out', (
    tester,
  ) async {
    await _pump(tester, auth: _signedIn());

    final stats = find.text('YOUR STATS');
    final changesets = find.text('Submitted changesets');
    final signOut = find.widgetWithText(OutlinedButton, 'Sign out');
    expect(stats, findsOneWidget);
    expect(find.text('CHANGESETS'), findsOneWidget);
    expect(find.text('TRAILS TOUCHED'), findsOneWidget);

    expect(
      tester.getTopLeft(stats).dy,
      lessThan(tester.getTopLeft(changesets).dy),
    );
    expect(
      tester.getTopLeft(changesets).dy,
      lessThan(tester.getTopLeft(signOut).dy),
    );
  });

  // It said what the Staged changes pane already says, on the pane a rider
  // opens to answer a different question.
  testWidgets('drops the staged-locally note', (tester) async {
    await _pump(tester, auth: _signedIn());
    expect(find.textContaining('staged locally'), findsNothing);

    await _pump(tester);
    expect(find.textContaining('staged locally'), findsNothing);
  });

  testWidgets('signed out, the way in comes before the empty stats', (
    tester,
  ) async {
    await _pump(tester);

    final signIn = find.widgetWithText(
      FilledButton,
      'Sign in to OpenStreetMap',
    );
    final notice = find.textContaining('Sign in to see what you\'ve done');
    expect(notice, findsOneWidget);
    expect(
      tester.getTopLeft(signIn).dy,
      lessThan(tester.getTopLeft(notice).dy),
    );
    expect(find.text('CHANGESETS'), findsNothing);
  });
}
