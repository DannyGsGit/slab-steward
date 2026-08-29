import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/osm/osm_auth.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/slab_theme.dart';
import 'package:slab_steward/src/ui/stats_panel.dart';

const _changesetsJson =
    '{"changesets":['
    '{"id":1,"created_at":"2024-01-01T10:00:00Z","changes_count":3,'
    '"tags":{"comment":"rate a few trails"}},'
    '{"id":2,"created_at":"2024-01-02T09:00:00Z","changes_count":1,'
    '"tags":{"comment":"one more"}}'
    ']}';

Future<StewardState> _pumpPanel(
  WidgetTester tester, {
  bool signedIn = false,
  String changesetsBody = _changesetsJson,
  int changesetsStatus = 200,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = OsmAuthState(
    client: MockClient((_) async => http.Response('{}', 200)),
  );
  if (signedIn) {
    auth.debugSignIn(
      token: 'test-token',
      identity: const OsmIdentity(id: 7, displayName: 'Rider'),
    );
  }

  final state = StewardState(
    osmApi: OsmApi(
      client: MockClient(
        (_) async => http.Response(changesetsBody, changesetsStatus),
      ),
    ),
    auth: auth,
  );
  addTearDown(state.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: slabTheme(),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: state,
          builder: (context, _) => StatsPanel(state: state),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('signed out asks for sign-in rather than fetching', (
    tester,
  ) async {
    final state = await _pumpPanel(tester);

    expect(
      find.textContaining('Sign in to see what you\'ve done'),
      findsOneWidget,
    );
    expect(state.stats, isNull);
  });

  testWidgets('signed in with changesets tallies them into stats', (
    tester,
  ) async {
    final state = await _pumpPanel(tester, signedIn: true);

    expect(state.statsError, isNull);
    expect(state.stats?.changesetCount, 2);
    expect(state.stats?.elementsChanged, 4);
    expect(find.text('CHANGESETS'), findsOneWidget);
    expect(find.text('TRAILS TOUCHED'), findsOneWidget);
  });

  testWidgets('signed in with no changesets shows the empty notice', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      signedIn: true,
      changesetsBody: '{"changesets":[]}',
    );

    expect(find.textContaining('No changesets yet'), findsOneWidget);
  });

  testWidgets('an API error is shown rather than left blank', (tester) async {
    final state = await _pumpPanel(
      tester,
      signedIn: true,
      changesetsBody: 'server error',
      changesetsStatus: 500,
    );

    expect(state.statsError, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('500'), findsOneWidget);
  });
}
