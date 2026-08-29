import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:slab_steward/src/model/difficulty.dart';
import 'package:slab_steward/src/model/sidebar_section.dart';
import 'package:slab_steward/src/model/staged_edit.dart';
import 'package:slab_steward/src/model/trail.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/account_panel.dart';
import 'package:slab_steward/src/ui/map_controls.dart';
import 'package:slab_steward/src/ui/selection_panel.dart';
import 'package:slab_steward/src/ui/sidebar.dart';
import 'package:slab_steward/src/ui/slab_theme.dart';
import 'package:slab_steward/src/ui/staged_changes.dart';
import 'package:slab_steward/src/ui/trail_list_panel.dart';
import 'package:slab_steward/src/ui/trail_panel.dart';

/// One two-node way, whatever is asked for.
const _wayJson =
    '{"elements":['
    '{"type":"node","id":1,"lat":47.5,"lon":-122.0},'
    '{"type":"node","id":2,"lat":47.51,"lon":-122.01},'
    '{"type":"way","id":42,"version":7,"nodes":[1,2],'
    '"tags":{"name":"Gravy Train","highway":"path"}}]}';

Future<StewardState> pumpSidebar(
  WidgetTester tester, {
  StewardState? state,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final s =
      state ??
      StewardState(
        osmApi: OsmApi(
          client: MockClient((_) async => http.Response(_wayJson, 200)),
        ),
      );
  addTearDown(s.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: slabTheme(),
      home: Scaffold(
        body: Row(
          children: [
            ListenableBuilder(
              listenable: s,
              builder: (context, _) =>
                  StewardSidebar(state: s, maxPaneWidth: 700),
            ),
            // Stands in for the map: the sidebar's whole job is to sit beside
            // it rather than on top of it.
            const Expanded(child: ColoredBox(color: Color(0xFFEDE7D8))),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('opens on the map pane, and the rail collapses it', (
    tester,
  ) async {
    final state = await pumpSidebar(tester);

    expect(state.activeSection, SidebarSection.map);
    expect(find.byType(MapControlsPanel), findsOneWidget);

    await tester.tap(find.byTooltip(SidebarSection.map.tooltip));
    await tester.pumpAndSettle();

    expect(state.activeSection, isNull);
    expect(
      find.byType(MapControlsPanel),
      findsNothing,
      reason: 'a rail button pressed twice gives the map its width back',
    );
  });

  testWidgets('one pane at a time', (tester) async {
    final state = await pumpSidebar(tester);

    await tester.tap(find.byTooltip(SidebarSection.trails.tooltip));
    await tester.pumpAndSettle();
    expect(state.activeSection, SidebarSection.trails);
    expect(find.byType(TrailListPanel), findsOneWidget);
    expect(find.byType(MapControlsPanel), findsNothing);

    await tester.tap(find.byTooltip(SidebarSection.account.tooltip));
    await tester.pumpAndSettle();
    expect(find.byType(AccountPanel), findsOneWidget);
    expect(find.byType(TrailListPanel), findsNothing);
  });

  testWidgets('picking a trail brings the editor forward, and dropping it '
      'puts the rider back where they were', (tester) async {
    final state = await pumpSidebar(tester);

    await state.selectFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});
    await tester.pumpAndSettle();

    expect(state.activeSection, SidebarSection.selection);
    expect(find.byType(TrailPanel), findsOneWidget);
    expect(
      find.text('Gravy Train'),
      findsOneWidget,
      reason: 'the pane heading names what is being edited',
    );

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();
    expect(state.hasSelection, isFalse);
    expect(
      state.activeSection,
      SidebarSection.map,
      reason: 'the editor displaced the Map pane, so it hands it back',
    );

    // And when nothing was open, nothing is: the map keeps the width.
    state.closeSection();
    await state.selectFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});
    await tester.pumpAndSettle();
    expect(state.activeSection, SidebarSection.selection);
    state.clearSelection();
    await tester.pumpAndSettle();
    expect(state.activeSection, isNull);
  });

  testWidgets('several trails get the bulk editor in the same pane', (
    tester,
  ) async {
    final state = await pumpSidebar(tester);

    await state.selectFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});
    state.addFromTiles([
      {'OSM_ID': 9, 'name': 'Bootcamp'},
    ]);
    await tester.pumpAndSettle();

    expect(find.byType(SelectionPanel), findsOneWidget);
    expect(find.text('2 trails selected'), findsOneWidget);
  });

  testWidgets('the rail carries the staged count, and opens the review', (
    tester,
  ) async {
    final state = await pumpSidebar(tester);
    state.stageEdit(
      StagedEdit.difficulty(
        const Trail(
          osmWayId: 42,
          tags: {'name': 'Gravy Train'},
          isAuthoritative: true,
          version: 7,
        ),
        Difficulty.medium,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip(SidebarSection.staged.tooltip));
    await tester.pumpAndSettle();
    expect(find.byType(StagedChangesPanel), findsOneWidget);
  });

  testWidgets('the selection button stays shut while nothing is selected', (
    tester,
  ) async {
    final state = await pumpSidebar(tester);

    await tester.tap(find.byTooltip(SidebarSection.selection.tooltip));
    await tester.pumpAndSettle();
    expect(
      state.activeSection,
      SidebarSection.map,
      reason: 'an empty editor is not a pane worth opening',
    );
  });

  testWidgets('the sidebar sits beside the map, and swallows its own clicks', (
    tester,
  ) async {
    await pumpSidebar(tester);

    // On web the map is a platform view the browser feeds directly, so
    // painting a pane over it is not enough to stop a scroll or a drag
    // reaching it. Two things prevent that here, and both are load-bearing:
    // the sidebar is laid out beside the map rather than over it, and it is
    // wrapped in a PointerInterceptor for anything that still overlaps.
    expect(
      find.descendant(
        of: find.byType(StewardSidebar),
        matching: find.byType(PointerInterceptor),
      ),
      findsOneWidget,
    );

    final sidebar = tester.getRect(find.byType(StewardSidebar));
    final map = tester.getRect(find.byType(ColoredBox).last);
    expect(sidebar.right, lessThanOrEqualTo(map.left));
  });

  testWidgets('every pane survives the narrowest window it can be given', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = StewardState(
      osmApi: OsmApi(
        client: MockClient((_) async => http.Response(_wayJson, 200)),
      ),
    );
    addTearDown(state.dispose);
    await state.selectFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});
    state.setVisibleTrails([
      {'OSM_ID': 42, 'name': 'Gravy Train', 'mtb:scale:imba': '2'},
      {'OSM_ID': 9, 'name': 'Bootcamp'},
    ]);
    state.stageEdit(
      StagedEdit.difficulty(state.selectedTrails.single, Difficulty.medium),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: slabTheme(),
        home: Scaffold(
          body: Row(
            children: [
              ListenableBuilder(
                listenable: state,
                builder: (context, _) =>
                    StewardSidebar(state: state, maxPaneWidth: 300),
              ),
              const Expanded(child: ColoredBox(color: Color(0xFFEDE7D8))),
            ],
          ),
        ),
      ),
    );

    for (final section in SidebarSection.values) {
      state.openSection(section);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '${section.name} overflowed a 300px pane',
      );
    }
  });

  testWidgets('the pane gives way rather than squeezing the map', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = StewardState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: slabTheme(),
        home: Scaffold(
          body: Row(
            children: [
              ListenableBuilder(
                listenable: state,
                builder: (context, _) =>
                    StewardSidebar(state: state, maxPaneWidth: 300),
              ),
              const Expanded(child: ColoredBox(color: Color(0xFFEDE7D8))),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(tester.getRect(find.byType(StewardSidebar)).width, lessThan(400));
  });
}
