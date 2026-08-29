import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/osm/osm_auth.dart';
import 'package:slab_steward/src/osm/osm_environment.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/account_button.dart';
import 'package:slab_steward/src/ui/trail_panel.dart';

Future<StewardState> _pump(WidgetTester tester, {OsmAuthState? auth}) async {
  final state = StewardState(auth: auth ?? OsmAuthState());
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AccountButton(state: state)),
    ),
  );
  return state;
}

void main() {
  // The regression this guards: sign-in used to live only inside the staged
  // changes dialog, which needs staged edits to open — so a fresh session had
  // no way to sign in at all.
  testWidgets('offers sign-in with nothing staged and nothing selected', (
    tester,
  ) async {
    final state = await _pump(tester);

    expect(state.hasStagedEdits, isFalse);
    expect(state.hasSelection, isFalse);
    expect(find.text('Sign in to OpenStreetMap'), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byType(InkWell)).onTap,
      isNotNull,
      reason: 'the control has to be tappable, not just visible',
    );
  });

  testWidgets('names the server in both states', (tester) async {
    await _pump(tester);
    expect(find.text(osmShortLabel), findsOneWidget);

    await _pump(
      tester,
      auth: OsmAuthState()
        ..debugSignIn(
          token: 't',
          identity: const OsmIdentity(id: 1, displayName: 'Test Rider'),
        ),
    );
    expect(find.text(osmShortLabel), findsOneWidget);
  });

  testWidgets('shows the account and can sign out once signed in', (
    tester,
  ) async {
    final state = await _pump(
      tester,
      auth: OsmAuthState()
        ..debugSignIn(
          token: 't',
          identity: const OsmIdentity(id: 1, displayName: 'Test Rider'),
        ),
    );

    expect(find.text('Test Rider'), findsOneWidget);
    expect(find.text('Sign in to OpenStreetMap'), findsNothing);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(state.auth.isSignedIn, isFalse);
    expect(find.text('Sign in to OpenStreetMap'), findsOneWidget);
  });

  // The chip shares the top-right column with the editor panel, so the two
  // have to coexist in a short viewport rather than the panel pushing the
  // chip off-screen or overflowing the column.
  testWidgets('coexists with the trail panel in a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = StewardState(
      osmApi: OsmApi(
        client: MockClient(
          (_) async => http.Response(
            '{"elements":['
            '{"type":"node","id":1,"lat":47.5,"lon":-122.0},'
            '{"type":"node","id":2,"lat":47.51,"lon":-122.01},'
            '{"type":"way","id":42,"version":7,"nodes":[1,2],'
            '"tags":{"name":"Gravy Train","highway":"path"}}]}',
            200,
          ),
        ),
      ),
    );
    addTearDown(state.dispose);
    await state.selectFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AccountButton(state: state),
                    const SizedBox(height: 12),
                    Flexible(child: TrailPanel(state: state)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.text('Sign in to OpenStreetMap'), findsOneWidget);
    expect(find.text('Gravy Train'), findsOneWidget);

    // The chip keeps its full height and sits above the panel, rather than
    // being the thing that gets squeezed.
    final chip = tester.getRect(find.byType(AccountButton));
    final panel = tester.getRect(find.byType(TrailPanel));
    expect(chip.height, greaterThan(40));
    expect(chip.bottom, lessThanOrEqualTo(panel.top));
  });
}
