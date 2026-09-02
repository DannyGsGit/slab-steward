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
import 'package:slab_steward/src/ui/bottom_bar.dart';
import 'package:slab_steward/src/ui/map_controls.dart';
import 'package:slab_steward/src/ui/slab_theme.dart';
import 'package:slab_steward/src/ui/trail_list_panel.dart';
import 'package:slab_steward/src/ui/trail_panel.dart';

/// One two-node way, whatever is asked for.
const _wayJson =
    '{"elements":['
    '{"type":"node","id":1,"lat":47.5,"lon":-122.0},'
    '{"type":"node","id":2,"lat":47.51,"lon":-122.01},'
    '{"type":"way","id":42,"version":7,"nodes":[1,2],'
    '"tags":{"name":"Gravy Train","highway":"path"}}]}';

/// The phone layout, stood up the way `_HomePage` builds it: the map (stood in
/// for here), the settings button over its top-right corner, the open pane,
/// and the bar.
Future<StewardState> _pumpPhone(
  WidgetTester tester, {
  StewardState? state,
  Size size = const Size(390, 780),
}) async {
  tester.view.physicalSize = size;
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
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Stands in for the map.
                    const ColoredBox(key: Key('map'), color: Color(0xFFEDE7D8)),
                    MapSettingsButton(state: s),
                  ],
                ),
              ),
              if (s.activeSection case final section?)
                StewardMobilePane(
                  state: s,
                  section: section,
                  height: mobilePaneHeight(size.height),
                ),
              StewardBottomBar(state: s),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('the bar carries the work, and the map keeps its own settings', (
    tester,
  ) async {
    final state = await _pumpPhone(tester);
    state.closeSection();
    await tester.pumpAndSettle();

    for (final section in SidebarSection.bottomBar) {
      expect(
        find.descendant(
          of: find.byType(StewardBottomBar),
          matching: find.text(section.shortLabel),
        ),
        findsOneWidget,
        reason: '${section.name} has no slot in the bar',
      );
    }
    expect(
      find.descendant(
        of: find.byType(StewardBottomBar),
        matching: find.text(SidebarSection.map.shortLabel),
      ),
      findsNothing,
      reason: 'the Map pane is reached from the map, not from the bar',
    );

    // The brand mark is the one thing on the rail that isn't a control, and
    // the bar has no width to spend on it.
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.byTooltip(SidebarSection.map.tooltip));
    await tester.pumpAndSettle();

    expect(state.activeSection, SidebarSection.map);
    expect(find.byType(MapControlsPanel), findsOneWidget);
  });

  testWidgets('the map settings button sits in the map\'s top-right corner', (
    tester,
  ) async {
    await _pumpPhone(tester);

    final button = tester.getRect(find.byTooltip(SidebarSection.map.tooltip));
    final window = tester.getRect(find.byType(Scaffold));
    expect(button.right, greaterThan(window.width * 0.8));
    expect(button.top, lessThan(window.height * 0.2));
  });

  testWidgets('a bar button opens its pane, and pressed again collapses it', (
    tester,
  ) async {
    final state = await _pumpPhone(tester);
    state.closeSection();
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(StewardBottomBar),
        matching: find.text(SidebarSection.trails.shortLabel),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.activeSection, SidebarSection.trails);
    expect(find.byType(TrailListPanel), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(StewardBottomBar),
        matching: find.text(SidebarSection.trails.shortLabel),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.activeSection, isNull);
    expect(
      find.byType(TrailListPanel),
      findsNothing,
      reason: 'a bar button pressed twice gives the map its height back',
    );
  });

  testWidgets('one pane at a time, and it gets the full width', (tester) async {
    await _pumpPhone(tester);

    await tester.tap(find.text(SidebarSection.account.shortLabel));
    await tester.pumpAndSettle();

    expect(find.byType(AccountPanel), findsOneWidget);
    expect(find.byType(MapControlsPanel), findsNothing);

    final pane = tester.getRect(find.byType(StewardMobilePane));
    final window = tester.getRect(find.byType(Scaffold));
    expect(pane.width, window.width);
    expect(
      pane.height,
      lessThan(window.height * 0.7),
      reason: 'the map has to keep a usable square above the pane',
    );
  });

  testWidgets('the pane sits above the bar rather than over the map', (
    tester,
  ) async {
    final state = await _pumpPhone(tester);
    await tester.tap(find.text(SidebarSection.trails.shortLabel));
    await tester.pumpAndSettle();

    final map = tester.getRect(find.byKey(const Key('map')));
    final pane = tester.getRect(find.byType(StewardMobilePane));
    final bar = tester.getRect(find.byType(StewardBottomBar));
    expect(map.bottom, lessThanOrEqualTo(pane.top));
    expect(pane.bottom, lessThanOrEqualTo(bar.top));

    // On web the map is a platform view the browser feeds directly, so both
    // bands need a real DOM element in front of it. See [StewardSidebar].
    expect(
      find.descendant(
        of: find.byType(StewardBottomBar),
        matching: find.byType(PointerInterceptor),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(StewardMobilePane),
        matching: find.byType(PointerInterceptor),
      ),
      findsOneWidget,
    );
    expect(state.activeSection, SidebarSection.trails);
  });

  testWidgets('the bar carries the staged count and the selection', (
    tester,
  ) async {
    final state = await _pumpPhone(tester);
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

    // Nothing selected is not a pane worth opening.
    await tester.tap(find.text(SidebarSection.selection.shortLabel));
    await tester.pumpAndSettle();
    expect(state.activeSection, isNot(SidebarSection.selection));

    await state.selectFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});
    await tester.pumpAndSettle();
    expect(state.activeSection, SidebarSection.selection);
    expect(find.byType(TrailPanel), findsOneWidget);
  });

  testWidgets('every pane survives the narrowest phone', (tester) async {
    final state = StewardState(
      osmApi: OsmApi(
        client: MockClient((_) async => http.Response(_wayJson, 200)),
      ),
    );
    await state.selectFromTile({'OSM_ID': 42, 'name': 'Gravy Train'});
    state.setVisibleTrails([
      {'OSM_ID': 42, 'name': 'Gravy Train', 'mtb:scale:imba': '2'},
      {'OSM_ID': 9, 'name': 'Bootcamp'},
    ]);
    state.stageEdit(
      StagedEdit.difficulty(state.selectedTrails.single, Difficulty.medium),
    );
    await _pumpPhone(tester, state: state, size: const Size(320, 568));

    for (final section in SidebarSection.values) {
      state.openSection(section);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '${section.name} overflowed a 320-wide phone',
      );
    }
  });
}
