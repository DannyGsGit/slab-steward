import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/model/lens.dart';
import 'package:slab_steward/src/model/trail_filters.dart';
import 'package:slab_steward/src/osm/osm_auth.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/legend.dart';
import 'package:slab_steward/src/ui/map_controls.dart';

/// The Map pane and the legend inside it: the toggles are only worth having if
/// the map's own explanation of the colours follows what was ticked.
Future<StewardState> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final state = StewardState(auth: OsmAuthState());
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: state,
          builder: (context, _) => MapControlsPanel(state: state),
        ),
      ),
    ),
  );
  return state;
}

Finder inLegend(String text) =>
    find.descendant(of: find.byType(Legend), matching: find.text(text));

void main() {
  testWidgets('opens on the questions a steward is here to answer', (
    tester,
  ) async {
    final state = await pump(tester);

    expect(state.lenses, {Lens.difficulty, Lens.electricBicycle});
    expect(state.modes, {TravelMode.mtb});
    expect(inLegend('Missing difficulty or e-bike rule'), findsOne);
  });

  testWidgets('ticking rules accumulates — they are not alternatives', (
    tester,
  ) async {
    final state = await pump(tester);

    await tester.tap(find.text(Lens.electricBicycle.label));
    await tester.pumpAndSettle();
    expect(state.lenses, {Lens.difficulty});

    await tester.tap(find.text(Lens.access.label));
    await tester.pumpAndSettle();
    expect(state.lenses, {Lens.access, Lens.difficulty});
  });

  testWidgets('the legend spells out whatever combination is ticked', (
    tester,
  ) async {
    final state = await pump(tester);

    state.setLenses({Lens.difficulty});
    await tester.pumpAndSettle();
    expect(inLegend('Missing difficulty'), findsOneWidget);

    state.setLenses({Lens.access});
    await tester.pumpAndSettle();
    expect(
      inLegend('Access unknown'),
      findsOneWidget,
      reason: 'the access rule asks about access, not about a missing tag',
    );
  });

  testWidgets('the rating colours are explained whatever is ticked', (
    tester,
  ) async {
    final state = await pump(tester);

    // A line's colour is its rating and nothing else, so the legend says so
    // even with every rule cleared — see docs/specs/map_view.md.
    for (final lenses in [Lens.values.toSet(), const <Lens>{}]) {
      state.setLenses(lenses);
      await tester.pumpAndSettle();
      for (final tier in [
        'Un-rated',
        'Beginner & Easy',
        'Medium',
        'Difficult',
        'Expert & Pro Line',
      ]) {
        expect(inLegend(tier), findsOneWidget, reason: tier);
      }
    }
  });

  testWidgets('the legend names the two glows that are always live', (
    tester,
  ) async {
    await pump(tester);

    // Neither depends on what is ticked: a trail is selected or it isn't, and
    // it has an edit waiting on it or it doesn't.
    expect(inLegend('Selected'), findsOneWidget);
    expect(
      inLegend('Change staged — glows the rating it will carry'),
      findsOneWidget,
    );
  });

  testWidgets('clear all empties the selection and the map goes plain', (
    tester,
  ) async {
    final state = await pump(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Clear all'));
    await tester.pumpAndSettle();

    expect(state.lenses, isEmpty);
    expect(
      find.descendant(
        of: find.byType(Legend),
        matching: find.textContaining('Missing'),
      ),
      findsNothing,
      reason: 'nothing is being asked, so nothing can be missing',
    );
  });

  testWidgets('the access rule is withdrawn when nobody is being asked about', (
    tester,
  ) async {
    final state = await pump(tester);
    state.setLenses({Lens.access, Lens.difficulty});
    await tester.pumpAndSettle();

    // Untick the one mode that was on: with nobody selected, "is access
    // recorded?" is a question about nothing.
    await tester.tap(find.text(TravelMode.mtb.label));
    await tester.pumpAndSettle();

    expect(state.modes, isEmpty);
    expect(state.lenses, {Lens.difficulty});
    expect(find.text(Lens.access.label), findsNothing);
    expect(
      inLegend('Not open to mountain bikes'),
      findsNothing,
      reason: 'nothing is drawn as shut when nobody is being asked about',
    );
  });

  group('the kind toggles', () {
    testWidgets('both modes can be asked about at once', (tester) async {
      final state = await pump(tester);

      await tester.tap(find.text(TravelMode.foot.label));
      await tester.pumpAndSettle();

      expect(state.modes, {TravelMode.mtb, TravelMode.foot});
      expect(
        inLegend('Not open to mountain bikes or walkers & hikers'),
        findsOneWidget,
      );
    });

    testWidgets('everything but informal starts off, and can be asked for', (
      tester,
    ) async {
      final state = await pump(tester);

      expect(state.kinds, {TrailKind.informal});

      await tester.tap(find.text(TrailKind.paved.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TrailKind.footway.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TrailKind.track.label));
      await tester.pumpAndSettle();

      expect(state.kinds, {
        TrailKind.informal,
        TrailKind.paved,
        TrailKind.footway,
        TrailKind.track,
      });
    });

    testWidgets('the legend stops explaining a kind nobody is drawing', (
      tester,
    ) async {
      final state = await pump(tester);
      expect(inLegend('Informal / unofficial'), findsOneWidget);

      state.setKindEnabled(TrailKind.informal, false);
      await tester.pumpAndSettle();
      expect(inLegend('Informal / unofficial'), findsNothing);
    });
  });
}
