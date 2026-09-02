import 'package:flutter/material.dart';

import 'map/steward_map_view.dart';
import 'state/steward_state.dart';
import 'ui/bottom_bar.dart';
import 'ui/sidebar.dart';
import 'ui/slab_theme.dart';

class StewardApp extends StatefulWidget {
  const StewardApp({super.key});

  @override
  State<StewardApp> createState() => _StewardAppState();
}

class _StewardAppState extends State<StewardApp> {
  final _state = StewardState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SLAB Steward',
      debugShowCheckedModeBanner: false,
      // SLAB's design system — dark forest and gold, from
      // docs/requirements/SLAB Design System - Mockups v2.html. The chrome is
      // dark on purpose: the map is the bright thing on screen and the rail
      // and pane are what surrounds it, exactly as the sister app treats its
      // own map screen.
      theme: slabTheme(),
      home: _HomePage(state: _state),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.state});

  final StewardState state;

  /// How much of a narrow window the pane may claim before it starts eating
  /// the map. Half: below that the map stops being a map.
  static const _maxPaneFraction = 0.5;

  /// Under this, the rail and pane side by side leave too little width to be
  /// worth either, and the layout turns ninety degrees — see
  /// [StewardBottomBar].
  ///
  /// A rail is 64 and the narrowest pane is 360, so a window this wide is
  /// already giving the map less than half of itself; a phone held upright is
  /// nowhere near it. Measured on the window rather than the platform because
  /// what is too narrow is the window: a desktop browser dragged down to a
  /// column has the same problem a phone does, and answers to the same fix.
  static const _bottomBarBelow = 720.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth < _bottomBarBelow
            ? _mobileLayout(constraints)
            : _wideLayout(constraints),
      ),
    );
  }

  /// The chrome listens to the app's state; the map is left out of every one
  /// of these builders on purpose. It reads the same state through its own
  /// listener and repaints the parts that changed — rebuilding it from up here
  /// as well would re-encode a stylesheet every time a checkbox moved.
  Widget _listening(WidgetBuilder builder) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => builder(context),
  );

  /// A row, not a stack. Every panel Steward has used to float over the map,
  /// which meant the map was always partly hidden and — on web, where the map
  /// is a platform view the browser feeds directly — every click and scroll
  /// over a panel had to be fended off before it reached the map. Beside it,
  /// neither problem exists. See [StewardSidebar].
  Widget _wideLayout(BoxConstraints constraints) => Row(
    children: [
      _listening(
        (context) => StewardSidebar(
          state: state,
          maxPaneWidth: constraints.maxWidth * _maxPaneFraction,
        ),
      ),
      // The map keeps whatever is left, and resizes as the pane opens and
      // closes rather than being covered by it.
      Expanded(child: StewardMapView(state: state)),
    ],
  );

  /// The same layout stood on end: map, then the open pane, then the bar. The
  /// pane is a band between the two rather than a sheet over the map, for the
  /// same reason the wide layout puts it beside one.
  ///
  /// Only the map settings button floats, because it is the one control that
  /// is about the map itself.
  Widget _mobileLayout(BoxConstraints constraints) => Column(
    children: [
      Expanded(
        child: Stack(
          fit: StackFit.expand,
          children: [
            StewardMapView(state: state),
            _listening((context) => MapSettingsButton(state: state)),
          ],
        ),
      ),
      _listening(
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.activeSection case final section?)
              StewardMobilePane(
                state: state,
                section: section,
                height: mobilePaneHeight(constraints.maxHeight),
              ),
            StewardBottomBar(state: state),
          ],
        ),
      ),
    ],
  );
}
