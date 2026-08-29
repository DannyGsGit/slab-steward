import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/model/lens.dart';
import 'package:slab_steward/src/osm/osm_auth.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/legend.dart';
import 'package:slab_steward/src/ui/map_controls.dart';

/// The controls and the legend together: the menu is only worth having if the
/// map's own explanation of the colours follows what was ticked.
Future<StewardState> pump(WidgetTester tester) async {
  final state = StewardState(auth: OsmAuthState());
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: state,
          builder: (context, _) => Column(
            children: [
              MapControls(state: state),
              Legend(state: state),
            ],
          ),
        ),
      ),
    ),
  );
  // The pickers live behind the collapsed header.
  await tester.tap(find.text('MAP CONTROLS'));
  await tester.pumpAndSettle();
  return state;
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(OutlinedButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens with both attribute rules ticked', (tester) async {
    final state = await pump(tester);

    expect(state.lenses, {Lens.difficulty, Lens.electricBicycle});
    expect(find.text('2 rules'), findsOneWidget);
    expect(find.text('Missing difficulty or e-bike rule'), findsOne);
  });

  testWidgets('ticking rules accumulates, and the menu stays open', (
    tester,
  ) async {
    final state = await pump(tester);
    await openMenu(tester);

    // Untick a default and tick another without reopening in between — the
    // whole point of a multi-select.
    await tester.tap(find.text(Lens.electricBicycle.label));
    await tester.pumpAndSettle();

    expect(state.lenses, {Lens.difficulty});
    expect(
      find.text(Lens.access.label),
      findsOneWidget,
      reason: 'the menu is still open after two taps',
    );

    await tester.tap(find.text(Lens.access.label));
    await tester.pumpAndSettle();
    expect(state.lenses, {Lens.access, Lens.difficulty});
  });

  testWidgets('the legend spells out whatever combination is ticked', (
    tester,
  ) async {
    final state = await pump(tester);

    Finder inLegend(String text) =>
        find.descendant(of: find.byType(Legend), matching: find.text(text));

    state.setLenses({Lens.difficulty});
    await tester.pumpAndSettle();
    expect(
      find.text(Lens.difficulty.label),
      findsNWidgets(2),
      reason: 'a lone rule names itself on the button as well as the legend',
    );
    expect(inLegend('Has difficulty'), findsOneWidget);
    expect(inLegend('Missing difficulty'), findsOneWidget);

    state.setLenses({Lens.access});
    await tester.pumpAndSettle();
    expect(
      inLegend('Access unknown'),
      findsOneWidget,
      reason: 'the access rule asks about access, not about a missing tag',
    );
    expect(
      inLegend('Trail'),
      findsOneWidget,
      reason: 'access alone leaves passing trails plain brown, as OTM does',
    );
  });

  testWidgets('clear all empties the selection and the map goes plain', (
    tester,
  ) async {
    final state = await pump(tester);
    await openMenu(tester);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    expect(state.lenses, isEmpty);
    await tester.tap(find.byType(Scaffold).first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Nothing highlighted'), findsOneWidget);
    expect(find.textContaining('Missing'), findsNothing);
  });

  testWidgets('the access rule is withdrawn when no mode is chosen', (
    tester,
  ) async {
    final state = await pump(tester);
    state.setLenses({Lens.access, Lens.difficulty});
    await tester.pumpAndSettle();

    state.setMode(TravelMode.all);
    await tester.pumpAndSettle();
    expect(
      state.lenses,
      {Lens.difficulty},
      reason: '"unknown access" has no meaning without a travel mode',
    );

    await openMenu(tester);
    expect(find.text(Lens.access.label), findsNothing);
  });
}
