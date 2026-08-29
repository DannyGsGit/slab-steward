import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/osm/osm_auth.dart';
import 'package:slab_steward/src/osm/osm_environment.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/account_panel.dart';

Future<StewardState> _pump(WidgetTester tester, {OsmAuthState? auth}) async {
  final state = StewardState(auth: auth ?? OsmAuthState());
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AccountPanel(state: state)),
    ),
  );
  return state;
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
    // The avatar answers "whose account" at a glance, which is the whole
    // reason the rail wears one.
    expect(find.text('TR'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(state.auth.isSignedIn, isFalse);
    expect(find.text('Sign in to OpenStreetMap'), findsOneWidget);
  });
}
